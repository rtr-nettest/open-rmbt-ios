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
  - Fence grouping by proximity (default radius 20 m).
  - Location-accuracy awareness with warning and auto‑stop behavior.
  - Wi‑Fi connection awareness (blocks measurement on Wi‑Fi).
  - Reliable result submission with local persistence and resend.

Defaults (from factory):
- Fence radius: 20 m.
- Minimum acceptable location accuracy: production 5 m; read‑only/preview 10 m.
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
- `timestamp` (µs since epoch of `dateEntered`), `latitude`, `longitude`, `avgPingMilliseconds?`, `technology?`, `testUUID`, `exitTimestamp?` (µs), `radiusMeters`.

SendCoverageResultRequest (API payload):
- Top level: `fences`, `test_uuid`, `client_uuid?`.
- Fence item:
  - `timestamp_microseconds`, `location` (lat, lon, accuracy?, altitude?, heading?, speed?),
  - `avg_ping_ms?`, `offset_ms`, `duration_ms?`, `technology?`, `technology_id?`, `radius_m`.

Notes:
- `offset_ms` is relative to coverage session start (`CoverageMeasurementSessionInitializer.lastTestStartDate`).
- `duration_ms` present only if fence has an exit time.
- `technology/technology_id` derived from the fence’s last technology code.

---

## Measurement Lifecycle

1) Start
- Start background activity; reset state; clear previous fences.
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
- Each tick either initiates a UDP ping session (if needed) or sends a ping within the current session.
- Errors yield `.error` pings except when the error requires reinitialization, in which case nothing is emitted on that tick and a reinit is scheduled.

UDP session and protocol
- `UDPPingSession` (actor) encapsulates the RTR UDP ping protocol.
- Request packet: ASCII `"RP01"` + 32‑bit big‑endian sequence + Base64‑decoded token bytes.
- Response handling:
  - `RR01` with matching sequence → ping succeeds.
  - `RE01` with matching sequence → fail with `needsReinitialization`.
  - `RE01` with unmatched sequence (incl. seq 0x0) while any ping is pending → treat as global reinit signal; all pending pings fail with `needsReinitialization`.
- Timeouts: pending pings exceeding `timeoutIntervalMs` (default 1000 ms) are completed with `timedOut`.
- UDP connection start parameters come from the coverage request (host/port/ip version). `ipVersion` may be nil.

Session reinitialization triggers
- Per‑session measurement time limit reached (server `max_coverage_measurement_seconds`).
- UDP server signals `RE01` (as above).
- On each reinit, `PingMeasurementService` marks the session as needing initiation; the next cadence tick performs `/coverageRequest` and continues.

Chaining sessions (`loop_uuid`)
- `CoverageMeasurementSessionInitializer` passes the previous `test_uuid` as the next request’s `loop_uuid` when reinitializing.
- The initializer also exposes server‑provided limits:
  - `maxCoverageSessionDuration` (stop everything when reached).
  - `maxCoverageMeasurementDuration` (reinitialize ping session when reached).

---

## Location Accuracy Handling

Accuracy threshold and windows
- A location is “precise enough” when `horizontalAccuracy ≤ minimumLocationAccuracy` (prod 5 m).
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
  - Ignore measurement updates (no fence creation/progression and no ping assignment), but continue UI updates and warnings.
- When switching back to cellular: hide the Wi‑Fi warning and resume normal processing.

---

## Fence Management

Creation and updates
- On a precise location update:
  - If there is no current fence → open a new fence at this location.
  - Else if `distance(from: startingLocation) ≥ fenceRadius` (default 20 m) → close the current fence at the update timestamp, persist it, and start a new fence at the new location.
  - Else → append location to the current fence and, if available, append the current technology code.

Ping assignment to fences
- For each successful ping, find the fence active at `ping.timestamp` (entered < t < exited; the last fence is open‑ended) and append the ping there.
- Pings occurring inside an “inaccurate location window” are ignored.

Average ping and technology
- `averagePing` is the mean over successful pings within the fence.
- The “significant” technology of a fence is the last recorded code; the UI displays mapped labels (2G, 3G, 4G, 5G NSA, 5G SA) and colors.

---

## Persistence & Result Submission

Persistence
- Completed fences are persisted to SwiftData immediately when a new fence is opened; the last fence is closed and persisted on stop.
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
- Payload includes `radius_m`, location extras (accuracy/altitude/heading/speed when available), `offset_ms`, and optional `duration_ms`.

---

## UI Behavior

- Map overlay shows fence centers (radius 20 m by default) with technology color coding:
  - 2G: #fca636, 3G: #e16462, 4G: #b12a90, 5G NSA: #6a00a8, 5G SA: #0d0887, unknown: #d9d9d9.
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
- Reinit chains sessions by passing the previous `test_uuid` as `loop_uuid`.
- Timed reinit: when `max_coverage_measurement_seconds` elapses, reinit the UDP session seamlessly (no UI interruption).
- Stop on `max_coverage_session_seconds` elapse.
- Protocol mapping: `RP01` request; `RR01` (match) → success; `RE01` (match) → needs reinit; `RE01` (unmatched/0x0) → global reinit of all pending pings.
- Persist/submit: fences collected under a given `test_uuid` are sent with that `test_uuid`; older persisted sessions are resent, newest groups first.

Location accuracy warning (docs/NetworkCoverage/user-stories/location-accuracy-warning.md)
- Hidden before start; initial delay of 3 s after start.
- If after the delay the latest location is worse than 5 m (prod), show “Waiting for GPS”.
- Hidden when accuracy improves; hidden on stop.
- Auto‑stop after 30 minutes with no accurate location ever received; records stop reason and ends measurement.

Wi‑Fi connection warning (docs/NetworkCoverage/user-stories/wifi-connection-warning.md)
- Hidden before start.
- When on Wi‑Fi: display “Disable Wi‑Fi”, ignore ping and location updates for measurement; fences are not affected.
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
