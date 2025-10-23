# FencePersistenceTests - Comprehensive Documentation

## Overview

This test suite validates the fence persistence and resending functionality for network coverage measurements. It ensures that coverage fences (geographic points with network measurements) are correctly saved, retrieved, and submitted to the server even across app restarts, network failures, and session reinitializations.

## Architecture Context

### Session-Based Persistence Model

The app uses a session-based persistence model where:

- **PersistentCoverageSession**: Represents a coverage measurement session with:
  - `testUUID`: Unique identifier for the session (nil until `/coverageRequest` succeeds)
  - `loopUUID`: Optional chaining identifier for reinitializations
  - `startedAt`: Microseconds since epoch when session began
  - `anchorAt`: Microseconds since epoch when `/coverageRequest` succeeded (time zero for offset calculations)
  - `finalizedAt`: Microseconds since epoch when session ended
  - `fences`: Related fences collected during this session

- **PersistentFence**: Represents a single fence with:
  - `timestamp`, `latitude`, `longitude`, `avgPingMilliseconds`, `technology`, `exitTimestamp`, `radiusMeters`
  - `session`: Relationship to parent session (cascade delete)

###Human: continue Key Services

**PersistenceServiceActor** (`@ModelActor`):
- Thread-safe SwiftData operations for sessions and fences
- Methods: `beginSession`, `assignTestUUIDAndAnchor`, `finalizeCurrentSession`, `save`, `sessionsToSubmitWarm/Cold`, `delete`, `deleteFinalizedNilUUIDSessions`

**PersistedFencesResender**:
- Resends previously persisted fences that failed to send
- Implements warm (foreground resume) vs cold (app launch) logic
- Handles cleanup of old sessions

**PersistenceManagingCoverageResultsService**:
- Coordinates current fence sending with resending of old fences
- Delegates to resender after each send operation

**NetworkCoverageFactory**:
- Creates properly configured persistence and sending services
- Wires dependencies together

## Test Organization

The test suite is organized into four main suites:

### 1. "Given Has No Previously Persisted Data"

**Purpose**: Validates basic fence persistence and sending when starting fresh

**Key Tests**:
- `whenPersistedFences_thenTheyArePresentInPersistenceLayer`: Verifies fences are correctly saved to SwiftData
- `whenSendingFencesSucceds_thenTheyAreRemovedFromPersistenceLayer`: Confirms successful sends delete persisted fences
- `whenSendingFenceFails_thenTheyAreKeptInPersistenceLayer`: Ensures failed sends retain fences for retry

**Rationale**: These tests establish the foundation - fences must be persisted reliably and cleaned up after successful submission.

### 2. "Given Has Previously Persisted Data"

**Purpose**: Validates resending logic when old fences exist from previous sessions

**Key Tests**:
- `whenSendingFencesSucceeds_thenAttemptsToSendAndRemovesAlsoPreviouslyPersistedFences`: Verifies the resender sends both current and old fences
- `whenAttemptToSendPreviouslyPersistedFencesFails_thenKeepsThoseFencesPersisted`: Ensures failed resends keep fences for next attempt
- `whenSendingPreviouslyPersistedFences_thenMappsThemProperlyToDomainObjects`: Validates correct mapping from SwiftData models to domain objects

**Rationale**: Network failures are common in mobile apps. Fences must survive app restarts and be retried. This suite ensures the resending mechanism works correctly.

### 3. "Given Has Persistent Fences Older Than Max Resend Age"

**Purpose**: Validates TTL (time-to-live) cleanup to prevent unbounded storage growth

**Key Tests**:
- `whenPersistedFencesAreOlderThanMaxAge_thenTheyAreDeletedWithoutSending`: Old sessions are pruned
- `whenPersistedFencesAreWithinMaxAge_thenTheyAreKeptAndSent`: Recent sessions are sent
- `whenSendingRecentFencesFailsButOldFencesExist_thenOnlyOldFencesAreDeleted`: Cleanup is independent of send failures

**Rationale**: Without TTL, failed sessions could accumulate indefinitely. This suite ensures old data is cleaned up while recent data is preserved for retry.

### 4. "Session-Based Persistence"

**Purpose**: Validates session-specific behaviors introduced in the new architecture

**Key Tests**:
- `whenFenceSavedDuringFinalization_thenRaceConditionHandledCorrectly`: Concurrent fence saves and finalizations don't cause data loss
- `whenDeletingNilUUIDSession_thenOrphanedFencesAreDeleted`: Sessions without UUIDs (offline-only) are cleaned properly
- `whenStoppedWithoutUUID_thenSessionDeleted`: Offline measurements that never succeed are removed
- `whenWarmSubmit_thenReturnsOnlyFinalizedSessions`: Warm resends skip unfinished sessions
- `whenColdSubmit_thenReturnsAllFinalizedSessions_mostRecentFirst`: Cold resends send all finalized sessions in LIFO order

**Rationale**: The session-based architecture supports offline start, reinitializations, and crash recovery. These tests ensure sessions are managed correctly across these scenarios.

## Test Infrastructure

### System Under Test (SUT)

The `SUT` class wraps the persistence and sending services to simulate the real application flow:

```swift
final class SUT {
    private let fencePersistenceService: any FencePersistenceService
    private let sendResultsServices: any SendCoverageResultsService
    private let testUUID: String?

    func persist(fence: Fence) async throws
    func persistAndSend(fences: [Fence]) async throws
}
```

**Key Behavior**:
- `persistAndSend` creates a session, assigns UUID/anchor, persists fences, sends them, then finalizes
- This simulates a complete measurement cycle
- The `sendResultsServices` triggers the resender, which sends old fences

### Test Helpers

**makeSUT**:
- Creates in-memory SwiftData database
- Pre-populates with previous sessions if provided
- Wires `NetworkCoverageFactory` services with test spies

**SendCoverageResultsServiceFactory**:
- Spy that captures send calls
- Returns configurable success/failure results
- Handles exhausted results gracefully (defaults to success)

**PersistenceLayerSpy**:
- Direct SwiftData query access for verification
- `persistedFences()`: Returns all fences (synchronous, no await needed)

**makeFence** / **makePersistentFence**:
- Generate test data with realistic values
- Support session sharing for multi-fence sessions

## Key Design Decisions

### Why Session-Based Instead of UUID-Based?

**Old Approach** (pre-f237bd7):
- Fences had `testUUID` property
- Resend grouped fences by UUID string
- No explicit session lifecycle

**Problems**:
- Reinitializations created new UUIDs but no session boundaries
- Offsets computed from single "coverage start date" instead of per-session anchor
- Warm resends could send incomplete data mid-measurement
- Offline start wasn't supported (no UUID until `/coverageRequest`)

**New Approach** (f237bd7+):
- `PersistentCoverageSession` represents sub-sessions
- Fences relate to sessions via relationship
- Each session has `anchorAt` for offset calculations
- Sessions can be created with `testUUID = nil` for offline start

**Benefits**:
- Offline measurements work (collect fences before UUID exists)
- Reinitializations have clear boundaries (finalize old, begin new)
- Warm resends skip unfinished sessions (avoid incomplete data)
- Per-session offsets are accurate (each reinit has its own anchor)

### Why @MainActor on Tests?

SwiftData `ModelContext` is not `Sendable` and must be accessed from a single actor. The production code uses `PersistenceServiceActor` to isolate SwiftData operations. However, tests need to:
1. Create in-memory databases
2. Pre-populate test data
3. Verify persisted state

Using `@MainActor` on tests ensures all SwiftData operations happen on the same actor, avoiding "ModelContexts are not Sendable" crashes.

### Why Separate makeSUT from makeDirectPersistenceActor?

**makeSUT**: Creates the full service stack (persistence + sending + resending)
- Used for integration-style tests that validate the complete flow
- Tests interaction between persistence and resending

**makeDirectPersistenceActor**: Creates just the `PersistenceServiceActor`
- Used for unit-style tests of session lifecycle
- Tests specific actor methods (beginSession, assignUUID, finalize)

This separation allows testing at different levels of abstraction.

## Common Failure Modes & How Tests Catch Them

### SwiftData Relationship Errors

**Symptom**: "Cannot remove PersistentCoverageSession from relationship session on PersistentFence"

**Cause**: Trying to delete a session while fences still reference it without cascade delete

**Prevention**: Tests verify `@Relationship(deleteRule: .cascade)` works correctly

### Offset Calculation Errors

**Symptom**: Negative offsets rejected by server, or offsets computed from wrong anchor

**Cause**: Using session `startedAt` instead of `anchorAt` for offsets

**Prevention**: `whenSendingPreviouslyPersistedFences_thenMappsThemProperlyToDomainObjects` validates mapping

### Premature Resending

**Symptom**: Incomplete measurements sent during warm foreground resume

**Cause**: Resender sends unfinished sessions

**Prevention**: `whenWarmSubmit_thenReturnsOnlyFinalizedSessions` ensures only finalized sessions are sent

### Unbounded Storage Growth

**Symptom**: App storage grows indefinitely with failed sessions

**Cause**: No TTL cleanup

**Prevention**: "Given Has Persistent Fences Older Than Max Resend Age" suite validates cleanup

### Concurrency Crashes

**Symptom**: "ModelContexts are not Sendable" or duplicate registration

**Cause**: Using ModelContext across actors

**Prevention**: All tests use `@MainActor` and actor-isolated persistence

## How to Add New Tests

### For New Fence Scenarios

1. Identify the scenario (e.g., "send succeeds with network delay")
2. Choose the appropriate suite (or create new if needed)
3. Use `makeSUT` with appropriate `sendResults` configuration
4. Create test data with `makeFence` / `makePersistentFence`
5. Call `persistAndSend` or individual methods
6. Verify with `persistence.persistedFences()` and `sendService.capturedSendCalls`

Example:
```swift
@Test @MainActor func whenNetworkDelayDuringSend_thenRetriesSucceed() async throws {
    let (sut, persistence, sendService) = makeSUT(
        testUUID: "test",
        sendResults: [.failure(NetworkError.timeout), .success(())]
    )

    try await sut.persistAndSend(fences: [makeFence()])

    #expect(sendService.capturedSendCalls.count == 2) // retry succeeded
    #expect(try persistence.persistedFences().isEmpty) // cleaned up
}
```

### For New Session Scenarios

1. Use `makeDirectPersistenceActor()` for direct session manipulation
2. Call session lifecycle methods explicitly
3. Verify session state with `sessionsToSubmitWarm/Cold`

Example:
```swift
@Test @MainActor func whenSessionReinitializedQuickly_thenBoundariesRespected() async throws {
    let sut = makeDirectPersistenceActor()

    try await sut.beginSession(startedAt: Date(), loopUUID: nil)
    try await sut.assignTestUUIDAndAnchor("uuid1", anchorNow: Date())
    try await sut.finalizeCurrentSession(at: Date())

    try await sut.beginSession(startedAt: Date(), loopUUID: "uuid1")
    try await sut.assignTestUUIDAndAnchor("uuid2", anchorNow: Date())

    let sessions = try await sut.sessionsToSubmitWarm()
    #expect(sessions.count == 1) // only finalized session
}
```

## Running the Tests

### Command Line

```bash
xcodebuild -workspace RMBT.xcworkspace \
  -scheme RMBT \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' \
  test -only-testing:RMBTTests/FencePersistenceTests
```

### Xcode

1. Open `RMBT.xcworkspace`
2. Select `RMBT` scheme
3. Choose simulator (e.g., iPhone 17 Pro)
4. Test Navigator → Right-click `FencePersistenceTests` → Test

## Maintenance Notes

### When Adding New Persistence Features

- Add corresponding test in appropriate suite
- Consider both success and failure paths
- Test with and without previous data
- Verify SwiftData relationships remain valid

### When Modifying Session Lifecycle

- Update "Session-Based Persistence" suite
- Verify warm vs cold behavior still works
- Check TTL cleanup interactions

### When Changing Resend Logic

- Update "Given Has Previously Persisted Data" suite
- Verify order of sends (LIFO vs FIFO)
- Check TTL interactions

## References

- Design Document: `tmp/persistent-coverage-sessions.md`
- Implementation Commit: f237bd7079
- Related Code: `Sources/NetworkCoverage/Persistence/`
