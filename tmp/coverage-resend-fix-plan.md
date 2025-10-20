# Plan: Prevent re-sending fences for an unfinished coverage test (while allowing crash recovery)

Owner: iOS Client
Date: 2025-10-17

## Problem Statement

Foreground transitions can re-send “persisted” fences while a coverage test is still running because:

- `applicationWillEnterForeground` → `onStart(false)` → `checkNews()` calls
  `NetworkCoverageFactory().persistedFencesSender.resendPersistentAreas()` unconditionally (Sources/RMBTAppDelegate.swift:43–76).
- Completed fences are persisted during a run (when a fence closes) and the final fence is persisted on stop().
- The resender groups by `testUUID` and sends whatever is persisted, without knowing whether the test is finished.

Result: mid-test foreground toggles can create premature `/coverageResult` submits (partial data), risking duplicates/conflicts on the server.

## Goals

1) Do not re-send fences for an unfinished test during warm foreground.
2) Allow crash/quit recovery: on cold start, resend fences for unfinished tests from prior runs.
3) Keep behavior simple, explicit, and testable.

## Non-Goals

- No server-side changes; assume one consolidated submit per `test_uuid` is expected.

## Related Code / Docs / Tests

- AppDelegate foreground/start flow: `Sources/RMBTAppDelegate.swift`.
- Stop path and final submit: `Sources/NetworkCoverage/NetworkCoverageViewModel.swift`.
- Resender: `Sources/NetworkCoverage/Persistence/PersistedFencesResender.swift`.
- SDD: `docs/NetworkCoverage/sdd/network-coverage.md` (Persistence & Result Submission).
- Unit tests: `RMBTTests/NetworkCoverage/Persistence/FencePersistenceTests.swift`.

## Proposed Fix (Phased)

### Phase 1 — Pass cold/warm flag from AppDelegate and gate resend

- Distinguish cold vs warm via AppDelegate:
  - `application(_:didFinishLaunching:)` → `onStart(true)` (cold start)
  - `applicationWillEnterForeground` → `onStart(false)` (warm foreground)
- Thread this boolean into `checkNews(isLaunched:)` and then into the resender.

Implementation sketch (RMBTAppDelegate.swift):

```swift
private func checkNews(isLaunched: Bool) {
    RMBTControlServer.shared.getSettings {
        Task {
            try? await NetworkCoverageFactory().persistedFencesSender.resendPersistentAreas(isLaunched: isLaunched)
        }
    } error: { _ in }
    // ... existing news fetch
}
```

### Phase 2 — Minimal session model and resend filtering

- Add a minimal SwiftData model to mark finished tests:

```swift
@Model
final class PersistentCoverageSession {
    @Attribute(.unique) var testUUID: String
    var startedAt: UInt64        // µs since epoch
    var finalizedAt: UInt64?     // µs since epoch; set in stop()
}
```

- Lifecycle hooks:
  - On `CoverageMeasurementSessionInitializer.startNewSession()` upsert a session record with `startedAt`.
  - On `NetworkCoverageViewModel.stop()` set `finalizedAt` for the current `testUUID`.

- Change `PersistedFencesResender.resendPersistentAreas(isLaunched:)` to filter groups:
  - If `isLaunched == true` (cold start): include both finalized and unfinished sessions (crash/quit recovery).
  - If `isLaunched == false` (warm foreground or pre-registration): include only sessions with `finalizedAt != nil` (finished tests).

Tests to add:
- Cold start with unfinished session → resend.
- Warm foreground with unfinished session → skip.
- Finalized session → resend in both modes.

### Phase 3 — Age cleanup and ordering (unchanged)

- Keep existing behavior:
  - Delete persisted fences older than 7 days before resend.
  - Group by testUUID, sort groups by earliest timestamp (descending), and sort fences within a group ascending by timestamp.

### Phase 4 — Telemetry and Logging

- Add logs to clarify decisions:
  - ViewModel stop: `Stopping coverage test: sending N fences` (already added).
  - Resender: mode (cold/warm), skipped unfinished in warm, sent groups and sizes, deletions by age.

## Migration / Compatibility

- `PersistentCoverageSession` is additive; no migration needed for `PersistentFence`.
- For legacy persisted fences lacking a session record, treat them as finalized only when older than a reasonable threshold (e.g., 15 minutes) or create a session record on first resend based on earliest fence timestamp.

## Risks and Mitigations

- Risk: If stop() crashes before marking `finalizedAt`, a finished test could be treated as unfinished on cold start.
  - Mitigation: Cold start resends unfinished tests by design (crash recovery), satisfying delivery.
- Risk: Skipping unfinished tests during warm foreground delays delivery.
  - Mitigation: Delivery occurs on next cold start or after finalization.

## Rollout Plan

1) Thread `isLaunched` through AppDelegate → checkNews → resender; implement filtering.
2) Add `PersistentCoverageSession` and lifecycle writes (start/stop).
3) Keep existing age cleanup + ordering.
4) Add unit tests for cold vs warm and finalized vs unfinished.
5) Add logging.

## Acceptance Criteria

- Warm foreground (onStart(false)) does not trigger `/coverageResult` for unfinished tests.
- Cold start (onStart(true)) triggers resend for unfinished tests (crash/quit recovery) and finalized tests.
- After stopping, the final submit includes all fences and subsequent resends include the finalized test.
- Unit tests cover cold vs warm filtering based on `isLaunched` and session.finalizedAt, plus legacy data and age cleanup.
