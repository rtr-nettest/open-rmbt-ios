# Software Design Document: Network Coverage (as implemented)

This document reflects the current behavior verified by unit tests in `RMBTTests/NetworkCoverage/` and the production code in `Sources/NetworkCoverage/` (as of the current repository state).

## Contents
- Overview
- Architecture
- Domain & Transport Models
- Measurement Lifecycle
- Ping Subsystem (UDP) and Reinitialization
- Location Accuracy Handling
- Wi‑Fi Gating
- Fence Management
- Persistence & Result Submission
- UI Behavior
- User Stories Coverage
- External Dependencies
- Testing Strategy
- Security
- Performance Notes

---

## Overview

- Purpose: Measure network latency while moving and associate the results with geographic “fences” (areas) to visualize coverage.
- Scope: SwiftUI UI, MVVM logic, UDP ping measurement, Core Location, persistence via SwiftData, and server sync using the existing control server API.
- Key features:
  - Continuous ping measurement on a fixed cadence (default 100 ms).
  - Fence grouping by proximity using a dynamic per-location fence radius with a 15 m minimum fallback.
  - Location-accuracy awareness with warning and auto‑stop behavior.
  - Wi‑Fi connection awareness (blocks measurement on Wi‑Fi).
  - Reliable result submission with local persistence and resend.

Defaults (from factory):
- Minimum fence radius fallback: 15 m.
- Minimum acceptable location accuracy: production 15 m; read‑only/preview 10 m.
- Location inaccuracy warning initial delay: 3 s.
- Auto‑stop if no accurate location ever appears within: 30 minutes.
- Ping frequency: 100 ms.
- UDP ping timeout: 1000 ms.
- Max total coverage session duration: server value when provided, else 4 h.
- Max per‑ping‑session measurement duration: server value when provided; triggers reinit when reached.

---

## Architecture

- Pattern: MVVM with Swift Concurrency and AsyncAlgorithms.
- Composition: `NetworkCoverageFactory` wires concrete services and constants.
- Reactive inputs: merged async streams of pings, locations, and network connection type updates.

Module layout (selected):
- View model: `Sources/NetworkCoverage/NetworkCoverageViewModel.swift`.
- Ping subsystem: `Sources/NetworkCoverage/Pings/` (`PingMeasurementService`, `UDPPingSession`).
- Location updates: `Sources/NetworkCoverage/LocationUpdates/`.
- Network type: `Sources/NetworkCoverage/NetworkType/` (Reachability‑based in production, simulator stub in debug).
- Persistence & resend: `Sources/NetworkCoverage/Persistence/`.
- Control‑server integration: `Sources/NetworkCoverage/CoverageMeasurementSession/` and `SendResult/`.

---

## Domain & Transport Models

Fence (domain):
- Fields: `startingLocation: CLLocation`, `dateEntered: Date`, `dateExited: Date?`, `pings: [PingResult]`, `technologies: [String]`, `radiusMeters: CLLocationDistance`, `id: UUID`.
- Derived:
  - `averagePing: Int?` (ms; average of successful pings in the fence).
  - `significantTechnology: String?` (last recorded code, if any).
  - `coordinate: CLLocationCoordinate2D` (from `startingLocation`).

PingResult (domain):
- `result: .interval(Duration) | .error`, `timestamp: Date`.

LocationUpdate (transport):
- `location: CLLocation`, `timestamp: Date`.

PersistentFence (SwiftData):
- `timestamp` (µs since epoch of `dateEntered`), `latitude`, `longitude`, `avgPingMilliseconds?`, `technology?`, `testUUID`, `exitTimestamp?` (µs), `radiusMeters`, `accuracy?`, `altitude?`, `bearing?`, `speed?` (location extras carried so resent fences resubmit them).

SendCoverageResultRequest (API payload):
- Top level: `fences`, `test_uuid`, `client_uuid?`.
- Fence item:
  - `timestamp_microseconds`, `location` (latitude, longitude, accuracy?, altitude?, bearing?, speed?),
  - `avg_ping_ms?`, `offset_ms`, `duration_ms?`, `technology?`, `technology_id?`, `radius`.

Notes:
- All `location` values and `avg_ping_ms` are encoded as JSON numbers via `Decimal` (not `Double`) so the wire form has no floating-point tail (e.g. `48.2082`, not `48.208199999999998`).
- `latitude`/`longitude` keep full precision. Everything else is rounded per its unit (issue #92): meter values (`accuracy`, `altitude`) to 1 decimal, `bearing` to 0 decimals (whole degrees), `speed` and `avg_ping_ms` to 2 decimals. `radius` stays a whole-meter integer.
- `bearing` is sourced from `CLLocation.course` (degrees from true north) and matches the Android `geo_locations` field name.
- `accuracy` is omitted when the source reading had no valid horizontal accuracy (`<= 0`), rather than reported as `0`. Resent fences preserve whatever accuracy was persisted.
- `offset_ms` is relative to the session anchor used for submission.
- For the live in-memory session, that anchor is the control-server session initialization time.
- For persisted resend, that anchor is the stored `PersistentCoverageSession.anchorAt`.
- `duration_ms` present only if fence has an exit time.
- `technology/technology_id` derived from the fence’s last technology code.

---

## Measurement Lifecycle

1) Start
- Start background activity; reset state; clear previous fences.
- Reset `currentTestUUID` to `nil` and create a new unfinished persisted session immediately.
- Schedule: location inaccuracy warning gate (3 s) and auto‑stop due to prolonged inaccuracy (30 min).
- Start iteration over merged streams: pings, locations, network type updates.

2) Iterate updates
- Enforce overall max duration (server or 4 h) and stop when reached.
- Handle each update on main actor to keep UI consistent.

3) Stop
- Close the last open fence (if any), persist, then submit all fences.
- Cancel background activity and timers.

Ping timestamps and cadence
- Pings are produced on a fixed cadence; the emitted `PingResult.timestamp` corresponds to the scheduled tick time, not the actual network completion time (validated by tests with `TestClock`).
- Before the first full UI refresh interval completes, the “latest ping” label shows “-”.
- With no pings at all it shows “N/A”.

---

## Ping Subsystem (UDP) and Reinitialization

High‑level flow
- `PingMeasurementService.pings2` drives periodic ticks (default 100 ms) using a `Clock`.
- The action for a tick is decided **in the cadence loop itself** (`PingSessionStateController.actionForTick`), before the tick's work is handed to a child task. Child tasks complete out of order, so every rule that depends on time (pausing, failure thresholds, backoff deadlines, the per-session time limit) is evaluated on the ordered tick and never on a completion timestamp.
- Each tick either prepares/activates a session, sends a ping in the session currently in use, or skips.
- Ping send/receive errors yield `.error` pings. A preparation failure yields no ping — nothing was measured.
- Session state is one of `idle` / `preparing(generation:old:)` / `active`. `old` is the previous session, which keeps measuring while a replacement is being fetched.
- `PingSessionStateController` is serialised with a lock rather than being an actor, precisely so that deciding a tick's action introduces no suspension point between reading the tick's timestamp and acting on it.
- Every outcome carries the `generation` of the session it was sent in. It is accepted only if that session is still the one in use and the measurement is not paused; rejected outcomes are neither counted nor reported.
- In production the factory injects `NetworkReachabilityOnlineStatusService`, so a failing `/coverageRequest` is suspended inside the initializer until reachability reports the device is online again — the cadence then proceeds without a busy retry loop. A preparation that fails while no usable session is left is retried no sooner than `RecoveryPolicy.retryDelay` (1 s), so a failing UDP activation cannot produce `/coverageRequest` calls at the 10 Hz cadence.

Two‑phase session bring‑up (make before break)
- `PingSending` splits session bring‑up into `prepareSession()` and `activateSession(_:)`:
  - `prepareSession()` performs `/coverageRequest` only. It can take arbitrarily long (and may park until the device is online) but **must not touch the transport**.
  - `activateSession(_:)` points `udpConnection` at the prepared host/port/`ip_version` and fails any requests still pending on the previous transport. Fast, but destructive.
- `UDPPingSession` owns a single `udpConnection`, and starting it cancels the live connection first. Splitting the phases is what makes recovery safe without a second transport: throughout the long phase the previous session keeps sending, and the only window in which nothing can send is the activation. That window is normally sub-second (UDP connection readiness) and is bounded by its own, much tighter `RecoveryPolicy.activationTimeout` (5 s) rather than the 15 s credentials-fetch bound.
- Sends queued for the session being replaced are rejected while a transport swap is in flight (`isActivating`), so a stale send can neither push a datagram through a half-swapped connection nor seed a receive loop on the outgoing one.
- Because the credentials fetch is what announces the new `test_uuid` (and makes the view model close the active fence), the controller drops the previous session exactly at that commit point. If activation then fails, the state goes to `idle` rather than resurrecting the previous session. The *goal* is that the controller never disagrees with the UUID the view model already committed to.
- **Known residual (design goal, not a proven invariant):** `sessionInitialized` is emitted inside the credentials fetch, before the controller flips its generation, so there is a short window — and a same-instant race if the fetch completes exactly as its timeout fires — in which the view model has committed the new UUID while an old-session ping is still accepted and reported into the new UUID's fence. Closing it means splitting announce-from-fetch, which changes the view-model contract; that is a separate change.

Pausing on Wi‑Fi
- The cadence samples `CurrentNetworkTypeProvider` on every tick. While the active path is Wi‑Fi no pings are sent and no `PingResult`s are produced, and outcomes that complete during the pause are rejected.
- An unsatisfied path (`nil`, e.g. no connectivity at all) is treated like cellular: pings keep being sent and keep reporting failures, because those failures are what renders a fence as "no coverage".
- On the simulator the provider is `nil` (no `NWPathMonitor`), so the pause never applies there.

UDP transport
- The UDP transport is abstracted behind the `UDPConnectable` protocol (`send(data:)` is enqueue‑only / synchronous; `receive()` is async).
- Two concrete implementations exist:
  - `NWUDPConnection` (default): connected `NWConnection`‑based transport. A connected UDP endpoint only accepts replies from the address the client sent to — the desired strict behavior now that the UDP ping server responds from the correct source address (rtr-nettest/open-rmbt-ios-private#32).
  - `AsyncSocketUDPConnection`: unconnected `GCDAsyncUdpSocket` that binds to an ephemeral local port and sends each datagram with an explicit destination host/port, accepting replies from any server source address. Used as a workaround while the server responded from a different IPv6 address; kept for diagnostics only and **not** wired into production — it binds a wildcard port with no interface scoping, so it cannot satisfy the cellular pinning below.
- Response validity is additionally determined by protocol fields and sequence/token semantics.
- `NWUDPConnection` sends with `.contentProcessed` and logs the outcome (failure transitions, plus a running
  accepted/rejected total every 100 datagrams). This is what lets a run of failed pings be attributed: datagrams
  accepted by the network stack but unanswered points at the server or the return path, whereas rejected datagrams
  point at the client's route or `ip_version`.

Cellular pinning
- On physical devices `NWUDPConnection` sets `NWParameters.requiredInterfaceType = .cellular`, and after `.ready` it
  rejects any path that does not use cellular or that also uses Wi‑Fi (`isPathAcceptable`). A rejected path takes the
  same route as `.failed`: the connection is cancelled and `start` throws, so no connection is ever installed on an
  unverified path.
- This is a guarantee rather than a preference, and it is deliberately redundant with the Wi‑Fi pause above. The pause
  samples the device's **primary** path once per tick, so Wi‑Fi that is associated but not primary would leave it
  unaware while the socket could still be carried over Wi‑Fi — the shape behind
  rtr-nettest/open-rmbt-ios-private#70.
- `prohibitedInterfaceTypes` is deliberately **not** set: requiring cellular is the meaningful constraint, and
  prohibiting Wi‑Fi would add no guarantee while adding a way for a valid multi-interface path to be rejected.
  `prohibitExpensivePaths`/`prohibitConstrainedPaths` stay at their `false` defaults — cellular is always expensive
  and is constrained under Low Data Mode, so prohibiting either would contradict the pin.
- Scope: only the ping transport is pinned. `/coverageRequest` goes through `URLSession`, which cannot be *required*
  to use cellular, and is deliberately left unconstrained; its returned `ip_version` is still honoured. Because pings
  are paused while Wi‑Fi is the active path, `/coverageRequest` normally runs while cellular is primary, and the
  session is refreshed on return from a Wi‑Fi epoch. Note this is *not* a refresh on every path change — a
  cellular→cellular or `nil`→cellular change triggers none — so a control request that completed over Wi‑Fi while
  cellular was primary could still yield a family that is unreachable on the cellular path. That failure surfaces as
  a run of activation failures rather than as a bad measurement.
- On the simulator the pin is compiled out (`#if targetEnvironment(simulator)`), because there is no cellular
  interface and a pinned socket could never become ready.
- `usesInterfaceType` reports path *eligibility*, not physical egress: a tunnel whose underlay is cellular satisfies
  the check. A measurement behind a VPN is therefore "cellular + VPN", and one with no usable cellular path at all
  (full-tunnel VPN, cellular denied for the app) will fail to activate and produce no pings.
- Only `NWUDPConnection` can satisfy this; see the transport list above.

UDP session and protocol
- `UDPPingSession` (actor) encapsulates the RTR UDP ping protocol.
- Request packet: ASCII `"RP01"` + 32‑bit big‑endian sequence + Base64‑decoded token bytes.
- Response handling:
  - `RR01` with matching sequence → ping succeeds.
  - `RE01` with matching sequence → fail with `needsReinitialization`.
  - `RE01` with an unmatched sequence (incl. seq 0x0) → **ignored** (logged and dropped); it does not fail pending pings and does not trigger a reinitialization.
- Pending request registration happens before the send so that a fast reply cannot arrive before the continuation is stored.
- Timeouts: pending pings exceeding `timeoutIntervalMs` (default 1000 ms) are completed with `timedOut`.
- UDP connection start parameters come from the coverage request (host/port/ip version). `ipVersion` may be nil.

Session reinitialization triggers
Hard cuts — the session in use must stop being used immediately, and are evaluated **before** the soft recovery gate so a rejected session is never kept as a recovery's fallback:
- Per‑session measurement time limit reached (server `max_coverage_measurement_seconds`).
- UDP server signals `RE01` with a matching sequence (as above). Note that an `RE01` for an *unknown* sequence is ignored, not treated as a global reinitialization signal.
- A hard cut arriving while a replacement is already being prepared drops the previous session but keeps the very same candidate — it never starts a second `/coverageRequest`.

Soft recovery — the session is replaced because its send path looks dead, while it keeps measuring until the replacement's credentials arrive:
- A run of `RecoveryPolicy.maxConsecutiveFailures` (30, ≈3 s at the 100 ms cadence) consecutive failed ping outcomes. "Consecutive" means consecutive *completions*, so a late success can delay recovery by up to roughly the 1 s ping timeout.
- Returning from a Wi‑Fi epoch, because the previous session's `ip_version`, host and token were obtained on the other path. A successful ping does not settle this refresh; only a preparation does.
- Recoveries are throttled by a doubling backoff: the first is immediate, then 10 s, 20 s, 40 s, 80 s, capped at 120 s. A successful ping restarts the ladder and clamps the pending throttle to at most `initialBackoff`, so a working path cannot unlock an immediate recovery storm while, for example, Wi‑Fi keeps flapping.
- The phases are bounded separately: the credentials fetch by `RecoveryPolicy.recoveryPrepareTimeout` (15 s) and the activation by the tighter `RecoveryPolicy.activationTimeout` (5 s), so a worst-case bring-up is ~20 s. On timeout or failure the previous session is restored (preparation) or the state goes `idle` and is retried on the activation backoff ladder described below (activation). Only the very first *credentials fetch* of a run is unbounded — parking until the device gets online is the offline-start behaviour. Activation is always bounded, because it only runs once `/coverageRequest` has already succeeded.
- The two phases fail for different reasons and are reported separately (`didFailPreparation` vs `didFailActivation`), because they want opposite retry policies. A credentials failure usually means the device is briefly offline and keeps a flat, prompt `retryDelay`. An activation failure means the credentials were fine and the transport still would not come up — with the socket pinned to cellular that is frequently permanent for the rest of the run, so attempts escalate on their **own** doubling ladder (`activationBackoff`, first failure not delayed, capped at `maxBackoff`) and only a successful activation resets it. Without this, an unusable cellular path would mint a `/coverageRequest` and a `test_uuid` every few seconds for the whole walk.
- An activation failure always drops the session: `didPrepareSession` has already released the previous one and `activateSession` has already torn down its transport, so `didFailActivation` fails closed into `idle` and never restores it.
- A run of activation failures is surfaced in the rolling field-log summary (`consecutive activation failures: N`), which is what distinguishes "no cellular path available at all" from a genuine dead zone.
- For those bounds to be real, the async bridges the phases sit on are cancellation-aware: `CoreSessionInitializer.request` and `NWUDPConnection.start` resume exactly once via `OneShotContinuation` and drop a late callback. The underlying HTTP request is not itself cancellable, so it may still complete server-side — the client ignores its result, which is what keeps fences consistent.
- Every preparation first runs the persisted-fence resend (`PersistenceAwareSessionInitializer`). That leg is cancellation-aware too: `SendCoverageResultRequest.send` uses the same one-shot bridge, `PersistedFencesResender` checks for cancellation between submissions, and the `try?` around the resend is followed by an explicit `Task.checkCancellation()` so a swallowed cancellation cannot let the attempt proceed into `/coverageRequest`.
- A retry is gated from the moment the failed attempt *started*, not from whichever tick observed the failure: an attempt that failed fast is throttled by `retryDelay`, one that already spent longer than that retries at the next tick.
- An owed recovery is never lost: it is latched per cause and re-latched if the attempt it triggered fails.

Known behaviour shift: a fence whose whole lifetime falls inside an activation gap can carry zero pings. Live, `Fence.isNoCoverage` treats empty pings as pending and keeps the technology colour; rebuilt from history it is drawn grey. Suppressing such fences is tracked separately.

Chaining sessions (`loop_uuid`)
- `CoverageMeasurementSessionInitializer` passes the previous response `loop_uuid` as the next request’s `loop_uuid` when reinitializing.
- The initializer also exposes server‑provided limits:
  - `maxCoverageSessionDuration` (stop everything when reached).
  - `maxCoverageMeasurementDuration` (reinitialize ping session when reached).

---

## Location Accuracy Handling

Accuracy threshold and windows
- A location is “precise enough” when `horizontalAccuracy ≤ minimumLocationAccuracy` (prod 15 m).
- While accuracy is insufficient, the view model opens an “inaccurate location window”; any ping whose timestamp falls within any open window is ignored (not assigned to fences).
- When accuracy improves, the last open window is closed; subsequent pings are processed normally.

Warning popup and auto‑stop
- After an initial delay (default 3 s) following start, if the latest location remains worse than the threshold, the “Waiting for GPS” warning is shown.
- If no accurate location ever arrives within 30 minutes, measurement auto‑stops and records stop reason `insufficientLocationAccuracy(duration: 30 min)`.
- Once at least one accurate location is received (within the timeout window), auto‑stop is canceled.

---

## Wi‑Fi Gating

- A separate async stream reports network connection type (Reachability in production). Types: `.wifi` and `.cellular`.
- While on Wi‑Fi:
  - Show the “Disable Wi‑Fi” warning.
  - Send no pings at all (the cadence pauses — see the ping subsystem section) and drop any ping outcome that completes during the pause, so no ping is assigned to a fence.
  - Keep processing location updates: fences continue to be created and progressed, they just carry no pings.
- When switching back to cellular: hide the Wi‑Fi warning, resume pinging, and refresh the ping session.

**Confirmed behaviour:** only *ping* updates are ignored on Wi‑Fi. Location updates keep being processed into
fences, so a Wi‑Fi stretch still produces fences that track the route — they simply carry no pings. The user story
has been corrected to match.

---

## Fence Management

Creation and updates
- On a precise location update:
  - Compute the candidate fence radius as `max(15 m, 10 m + 2 × horizontalAccuracy, speed_m_s × 1 s)`.
  - If there is no current fence → open a new fence at this location using that computed radius.
  - Else if `distance(from: startingLocation) ≥ currentFence.radiusMeters` → close the current fence at the update timestamp, persist it, and start a new fence at the new location using the newly computed radius.
  - Else → append location to the current fence and, if available, append the current technology code.
- Once a fence is opened, its `radiusMeters` stays frozen for the lifetime of that fence; later location updates do not resize an already-open fence.

Ping assignment to fences
- For each successful ping, find the fence active at `ping.timestamp` (entered < t < exited; the last fence is open‑ended) and append the ping there.
- Pings occurring inside an “inaccurate location window” are ignored.
- When the first session UUID arrives, fences that were still `nil`-tagged are retro-tagged with it.
- When the session UUID **changes** (reinitialization or recovery), the active fence is force-closed at the event timestamp and persisted *before* the new session is anchored, because `save()` writes to the latest unfinished persisted session — which is still the old one at that point. Measurement then continues in a new fence under the new UUID.

Average ping and technology
- `averagePing` is the mean over successful pings within the fence.
- The “significant” technology of a fence is the last recorded code; the UI displays mapped labels (2G, 3G, 4G, 5G NSA, 5G SA) and colors.

---

## Persistence & Result Submission

Persistence
- `sessionStarted(at:)` creates an unfinished `PersistentCoverageSession` even before `test_uuid` is known.
- Completed fences are persisted to SwiftData immediately when a new fence is opened; the last fence is closed and persisted on stop.
- `assignTestUUIDAndAnchor(_:anchorNow:)` attaches the server `test_uuid` and anchor timestamp to the unfinished persisted session. If a different UUID arrives mid-measurement, the current persisted session is finalized and a new persisted session is opened from the new anchor.
- Persisted fields include `exitTimestamp` (if closed) and `radiusMeters`.

Resend on startup / session init
- Before starting a new coverage session, the app attempts to resend any previously persisted fences.
- Behavior:
  - Delete persisted fences older than a configured max age (default 7 days).
  - Group remaining fences by `testUUID` and send newest groups first (by earliest timestamp in the group, descending).
  - On success, delete sent records; on failure, keep them for the next attempt.

Submission
- Uses `ControlServerCoverageResultsService` → `RMBTControlServer.submitCoverageResult`.
- Acceptable status codes: 200..<300.
- Payload includes `radius`, location extras (accuracy/altitude/bearing/speed when available), `offset_ms`, and optional `duration_ms`. `PersistentFence` persists these extras too, so resent fences reconstruct and resubmit the same values; readings without a valid extra stay absent.
- `PersistenceManagingCoverageResultsService` submits only fences whose `sessionUUID` matches the current `test_uuid`.
- If the current session has no matching fences, the send path falls back to resend-only behavior for previously finalized persisted sessions.
- If the current measurement never obtained a `test_uuid`, send fails with `missingTestUUID`; the view model finalizes the local persisted session and **keeps it on disk** (issue #60). The resender will anchor it on the next online opportunity via `SessionAnchoringService`.

---

## UI Behavior

- Map overlay shows fence centers using each fence's stored radius with technology color coding:
  - 2G: #fca636, 3G: #e16462, 4G: #b12a90, 5G NSA: #6a00a8, 5G SA: #0d0887, unknown: #d9d9d9.
- The live settings panel no longer exposes a production fence-radius slider; instead it shows the frozen current-fence radius and the latest computed dynamic radius as diagnostics.
- Selection updates a detail panel with date, technology label, and average ping (e.g., “60 ms”).
- Map rendering strategy is tunable through `FencesRenderingConfiguration` (defaults: `maxCircleCountBeforePolyline = 60`, `minimumSpanForPolylineMode = 0.03`, `visibleRegionPaddingFactor = 1.2`, `cullsToVisibleRegion = true`). The view model maintains derived state (`visibleFenceItems`, `fencePolylineSegments`, `mapRenderMode`) and only recomputes it when fences or the visible map region change, keeping SwiftUI diffs minimal.
- When `mapRenderMode == .circles`, the map shows per-fence annotations and circles; when line count and zoom span exceed the configured thresholds, it switches to `mapRenderMode == .polylines`, grouping contiguous fences with the same technology into colored polylines while clearing any stale selection.
- Polyline segments break only when consecutive fences are separated by a data gap (distance greater than twice the previous fence’s diameter); technology transitions without a data gap remain visually connected by sharing their boundary coordinate.
- The current fence (if any) keeps its circle visible even in polyline mode to retain user context.
- Visible items are culled to the padded map region when `cullsToVisibleRegion` is enabled, so off-screen fences and polyline coordinates do not inflate overlay churn. `onMapCameraChange` reports region updates back to the view model, and read-only screens seed an initial region enclosing all fences before the first camera callback arrives.
- “Latest ping” label:
  - Shows “-” until one full refresh interval completes.
  - After each completed interval, shows the average of pings in the last completed interval.
  - Shows “N/A” if no pings have ever been received.
- Warnings can stack; Wi‑Fi and GPS accuracy warnings may appear at the same time.

---

## User Stories Coverage

UDP pings reinitialization (docs/NetworkCoverage/user-stories/udp-pings-behavior.md)
- Session init uses `ping_host`, `ping_port`, `ping_token`; remembers `test_uuid` for the current session.
- Reinit chains sessions by passing the previous response `loop_uuid` as `loop_uuid`.
- Timed reinit: when `max_coverage_measurement_seconds` elapses, reinit the UDP session seamlessly (no UI interruption).
- Stop on `max_coverage_session_seconds` elapse.
- Protocol mapping: `RP01` request; `RR01` (match) → success; `RE01` (match) → needs reinit; `RE01` (unmatched/0x0) → **ignored** (it does not fail pending pings and does not trigger a reinit).
- No pings are sent at all while the active path is Wi‑Fi; returning to cellular refreshes the session. A run of consecutive failed ping outcomes also triggers a throttled session recovery, during which the previous session keeps measuring.
- Persist/submit: fences collected under a given `test_uuid` are sent with that `test_uuid`; older persisted sessions are resent, newest groups first.
- Offline-start: persisted sessions support negative `offset_ms` and the production composition wires `NetworkReachabilityOnlineStatusService` for mid-measurement recovery (scenario B). For fully-offline runs (scenario A), the resender invokes `/coverageRequest` per stranded session via `SessionAnchoringService`, late-writes `test_uuid` + `anchor_at` onto the persisted session, and submits with all-negative offsets. Sessions that never reach connectivity within `persistenceMaxAgeInterval` (7 days) are dropped by the age-based cleanup.

Location accuracy warning (docs/NetworkCoverage/user-stories/location-accuracy-warning.md)
- Hidden before start; initial delay of 3 s after start.
- If after the delay the latest location is worse than 5 m (prod), show “Waiting for GPS”.
- Hidden when accuracy improves; hidden on stop.
- Auto‑stop after 30 minutes with no accurate location ever received; records stop reason and ends measurement.

Wi‑Fi connection warning (docs/NetworkCoverage/user-stories/wifi-connection-warning.md)
- Hidden before start.
- When on Wi‑Fi: display “Disable Wi‑Fi” and send no pings at all. Location updates are still processed, so fences keep tracking the route but carry no pings for the Wi‑Fi stretch.
- When switching back to cellular: hide the warning and resume.
- Wi‑Fi and GPS warnings can be shown simultaneously.

---

## External Dependencies

- Core Location: live updates and accuracy.
- Core Telephony: technology codes mapped to display strings.
- MapKit: map rendering.
- SwiftData: persistence.
- AsyncAlgorithms: merging and scheduling async streams.
- Reachability (internal): network connection type detection in production; simulator service in debug.
- RMBTControlServer & ObjectMapper: API requests and mapping.

---

## Testing Strategy

- Unit tests cover ping cadence & timestamps, UDP protocol, session reinit, fence creation/assignment, warnings (GPS/Wi‑Fi), persistence and resend, and request encoding (radius, location extras, offset/duration).
- The view model and ping sequence are driven by `TestClock` to validate timing semantics deterministically.

---

## Security

- Location privacy: only fence centers and aggregated metrics are transmitted; no raw continuous traces.
- Transport: HTTPS; UDP ping authenticated by server token.
- Local data: leverages device encryption; stale persisted data is purged automatically.

---

## Performance Notes

- Ping cadence is timer‑driven and lightweight; UDP payloads are minimal.
- UI recomposition is constrained by `@Observable` state; map layers use simple annotations.
- Map overlays are capped by the rendering configuration: circle overlays stop at 60 items by default, polyline segments group adjacent fences by technology, and region-based culling prevents MapKit from rendering or diffing off-screen geometry, eliminating the previous frame drops with 100+ fences.
- No exponential backoff is implemented for result submission retries; reliability relies on persistence+resend on next session.
