# Foreground vs. Background UDP Ping Behaviour

## Overview

The coverage module’s UDP ping loop emits a new measurement every 100 ms while allowing multiple pings to be outstanding (500 ms timeout). When the app is in the foreground this cadence closely matches true network RTT because the system delivers both send and receive callbacks promptly. In the background—even with `location` background mode and an active `CLBackgroundActivitySession`—iOS deprioritises our work, causing delayed completions and inflated ping durations.

| Aspect | Foreground | Background (location mode) |
| --- | --- | --- |
| Dispatch scheduling | Timers and continuations run on-time | Queues downgraded; wakes coalesced |
| Network delivery | UDP callbacks delivered immediately | Packets batched or deferred |
| Energy policy | Full CPU/radio budget | Duty-cycle enforcement; throttling |
| Ping measurement | RTT ~= network latency | RTT includes OS-induced delay |

## Impact on Measurements

- **Inflated durations** – The ping stopwatch starts when we send and stops only when `receive()` resumes. Background throttling pauses that continuation, so the elapsed time includes OS delay rather than solely network RTT.
- **Burst processing** – Batches of `receive()` callbacks resume together, producing clusters of long/short RTTs rather than a steady stream.
- **Timeout drift** – With 500 ms timeout and 100 ms cadence, multiple continuations can be waiting simultaneously. Background stalls increase the number of outstanding pings, stressing server/backoff logic if not handled.

## Mitigation Tips

1. **Server-assisted timing**  
   Embed a send timestamp (or sequence) in each packet and have the server echo it back. Compute RTT with `(server_echo_time - client_send_time)` to factor out local delivery delays.

2. **Tolerance-aware UI/analytics**  
   Flag readings collected while the app is backgrounded and treat them separately (e.g., display as “approximate” or exclude from latency aggregates).

3. **Adaptive send cadence**  
   When in background, widen the ping interval or cap the number of concurrent continuations to reduce pressure on iOS throttling. The new single receive loop already limits `NWConnection.receive()` fan-out.

4. **Explicit wake management**  
   Continue using `CLBackgroundActivitySession`, but also monitor `ProcessInfo.processInfo.isLowPowerModeEnabled` and other cues; consider suspending pings during severe throttling to avoid misleading data.

5. **Error handling**  
   Resume pending continuations with `.networkIssue` if the receive loop encounters transport errors (already implemented) so hanging background requests do not accumulate.

## Takeaways

- The crash we observed stemmed from queuing thousands of `NWConnection.receive()` calls while backgrounded; moving to a single receive loop fixes the stack exhaustion without reducing logical concurrency.
- RTT values obtained in background mode are inherently noisier and should not be relied upon as direct analogues of foreground latency unless additional timing data is collected.

---

# Debugging UDP Ping Delivery (IPv4/IPv6)

Use the checklist below whenever pings appear to send successfully but no replies arrive.

## 1. Instrument the App
- **Log send/receive** in `UDPConnection` (Sources/NetworkCoverage/Pings/UDPConnection.swift) with sequence numbers, token hash, and `NWConnection.stateUpdateHandler` transitions (`.ready`, `.waiting`, `.failed`).
- **Count consecutive timeouts** in `PingMeasurementService`; after N failures, emit `.needsReinitialization` so a new session is requested.
- **Surface background throttling** (e.g., log when `ProcessInfo.processInfo.isLowPowerModeEnabled` or when the app enters background) to correlate with lost replies.

## 2. Capture Packets (Simulator)
- Run `sudo tcpdump -nni lo0 udp port <pingPort>` while the simulator runs; substitute Wireshark if preferred. Simulator traffic egresses over the Mac’s network stack.
- Inspect payloads: requests are `RP01|seq|token`, replies should be `RR01` or `RE01`.

## 3. Capture Packets (Physical Device)
- Enable a Remote Virtual Interface: `rvictl -s <device-udid>` then `sudo tcpdump -nni rvi0 udp port <pingPort>`. Use `rvictl -x` to disconnect when done.
- For IPv4 vs. IPv6, filter by address (`udp and host <v4>` or `udp and ip6 and host <v6>`) to confirm which family is in use.
- If you cannot tether, collect a sysdiagnose right after reproducing (`volume-up + volume-down + side button`) and inspect the contained pcap files.

## 4. Compare IPv4 vs. IPv6 Behaviour
- Examine the control server response (`CoverageMeasurementSessionInitializer`) to see which IP version is requested.
- Capture both families separately; if IPv6 shows outbound packets but no inbound replies, suspect NAT64/firewall issues.
- Use `dig AAAA <host>` or `nslookup` on the device (via a debugging shell) to ensure the host has valid AAAA records.

## 5. Monitor System Diagnostics
- Stream networking logs: `log stream --level debug --predicate 'subsystem == "com.apple.network"'` while the device is connected via USB.
- Enable the “Networking” profile from the Feedback Assistant developer menu to gather Network.framework traces automatically.

## 6. Validate Server Side
- Ask RTR backend to log received `RP01` packets (test UUID + sequence). If the server never sees them, the issue lies in the client/path; if it does but stays silent, it’s a backend problem.

## 7. Health Checks / Automation
- Add a CI integration test hitting a staging control server that asserts at least N `RR01` replies arrive over both IPv4 and IPv6. Run it after network-related changes.

Keep this checklist nearby to quickly determine whether missing replies stem from client logic, device/network environment, or the server path. 
