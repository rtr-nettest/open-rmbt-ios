# Development Plan: Resend Policy + Session Persistence

Owner: iOS Client
Date: 2025-10-17

This plan describes tests to add first, then implementation steps, ensuring all user stories in docs/NetworkCoverage/user-stories/standalone/ are covered. Follow docs/unit-testing-best-practices.md (WHEN-THEN naming, makeSUT factories, spies, result injection).

## 1) Unit Tests To Add (first)

Guiding principles
- Prefer business-focused scenarios (WHEN-THEN naming, Testing framework).
- Use in-memory SwiftData ModelContext to avoid I/O.
- Capture resend behavior via spy send service and persistence assertions.

### A. FencePersistenceTests additions (low-level resend + cleanup)

1. whenColdStart_andUnfinishedSession_thenResendsUnfinishedAndFinalized
- Arrange: Insert PersistentFence group for test T (unfinished session: PersistentCoverageSession(testUUID: T, finalizedAt: nil)). Insert group for U (finalizedAt set). Call resendPersistentAreas(isLaunched: true).
- Assert: sendService captured groups [T, U] (order by recency), fences per group match persisted.

2. whenWarmForeground_andUnfinishedSession_thenSkipsUnfinished
- Arrange: Unfinished session T + fences; finalized U + fences. Call resendPersistentAreas(isLaunched: false).
- Assert: Only U sent; T not sent.

3. whenWarmForeground_andOnlyUnfinishedSessions_thenSendsNothing
- Arrange: Unfinished sessions with fences only. Call resendPersistentAreas(isLaunched: false).
- Assert: No groups sent.

4. whenCleanup_thenDeletesOldFences_andOldSessions_andOrphanSessions_butNotForUnfinishedCurrent
- Arrange: Insert fences older than max age; insert session older than max age with no recent fences; insert orphan session (no fences).
- And insert an unfinished session W with some fences (representing a currently running test).
- Act: Call resendPersistentAreas(isLaunched: false) (warm) and also isLaunched: true (cold).
- Assert (warm): Old fences deleted; old/orphan sessions deleted; fences for unfinished session W are NOT deleted.
- Assert (cold): Old fences deleted; old/orphan sessions deleted; fences for unfinished session W are NOT deleted (they will be resent, not deleted).

5. whenLegacyFencesWithoutSessionRecord_thenColdStartResends_andWarmForegroundSkips
- Arrange: Insert fences for V without any PersistentCoverageSession record (legacy). Use threshold (e.g., 15 min) to consider them resendable on cold start.
- Act: Call resendPersistentAreas(isLaunched: true) and then isLaunched: false.
- Assert: Cold start sends V; warm foreground skips V.

Notes
- Extend existing helpers in FencePersistenceTests (makeInMemoryModelContext, makePersistentFence, SendCoverageResultsServiceFactory) to also create/read PersistentCoverageSession.
- Add simple helper to create session: makeSession(testUUID: String, started: UInt64, finalized: UInt64?).

### B. NetworkCoverageViewModelTests additions (VM start/stop integration)

6. whenStartNewMeasurement_thenMarksSessionStarted
- Arrange: Inject a FencePersistenceServiceSpy supporting markSessionStarted/markSessionFinalized.
- Act: await sut.startTest(). Trigger first location to ensure testUUID exists via initializer.
- Assert: Spy captured one markSessionStarted(testUUID:…) call with a plausible startedAt.

7. whenStopMeasurement_thenMarksSessionFinalized
- Arrange: Start; feed some locations to create fences; Spy persistence.
- Act: await sut.stopTest().
- Assert: markSessionFinalized(testUUID:…) captured.

8. whenStopMeasurement_thenSendsAllFencesOnce
- Arrange: Provide SendCoverageResultsServiceSpy.
- Act: start → feed updates → stop.
- Assert: send called once with all fences (N == sut.fenceItems.count at stop).

Test infra updates
- Extend makeSUT in NetworkCoverageViewModelTests to accept a FencePersistenceServiceSpy conforming to the new protocol.

### C. CoverageMeasurementSessionInitializerTests additions (session start behavior)

9. whenStartNewSession_thenUpsertsPersistentCoverageSessionStartedAt
- Arrange: In-memory ModelContext; mock control server; call initializer.startNewSession().
- Assert: PersistentCoverageSession exists for returned test_uuid with startedAt set and finalizedAt == nil.

### D. Optional thin integration test (policy end-to-end)

10. whenColdStart_thenResenderIncludesUnfinished_andWhenWarmForeground_thenSkips
- Arrange: Seed DB with unfinished+finished sessions; call resender with isLaunched true then false; assert send calls accordingly.
- (This is largely covered by A.1–A.3; include only if helpful.)

Mapping to stories
- Warm FG skip unfinished: Foreground resend policy feature.
- Cold start resend unfinished: Crash/quit recovery story.
- Cleanup sessions: Age cleanup feature.
- Submit on stop: Submission feature.

## 2) Implementation Steps (second)

### 2.1 Data model + container
- Add SwiftData model PersistentCoverageSession { testUUID (unique), startedAt: UInt64, finalizedAt: UInt64? }.
- Update UserDatabase.container to include PersistentCoverageSession.

### 2.2 Protocols + services
- Extend FencePersistenceService with session lifecycle methods:
  - markSessionStarted(testUUID: String, startedAt: Date) throws
  - markSessionFinalized(testUUID: String, finalizedAt: Date) throws
- Implement in SwiftDataFencePersistenceService:
  - Upsert session on markSessionStarted.
  - Set finalizedAt on markSessionFinalized.
- Provide simple queries for resender: fetch sessions by testUUID; cleanup stale/orphan.

### 2.3 Wire start/stop events
- Session start:
  - CoverageMeasurementSessionInitializer.startNewSession(): after obtaining test_uuid, call persistenceService.markSessionStarted(testUUID, now()).
  - If initializer doesn’t have persistenceService, pass a closure or small SessionRecorder dependency from NetworkCoverageFactory.
- Session stop:
  - NetworkCoverageViewModel.stop(): after closing last fence (existing) call persistenceService.markSessionFinalized(testUUID, timeNow()).
  - Keep existing sendResultsService.send(fences:).

### 2.4 Resend filtering + cleanup
- Change signature: PersistedFencesResender.resendPersistentAreas(isLaunched: Bool).
- Before sending:
  - deleteOldPersistentFences()
  - deleteOldPersistentCoverageSessions() (older than max age, no recent fences)
  - deleteOrphanSessions()
  - IMPORTANT: Never delete fences belonging to sessions with `finalizedAt == nil` (unfinished/current tests).
- Group by testUUID; for each group consult PersistentCoverageSession:
  - If isLaunched == true → allow both finalized (finalizedAt != nil) and unfinished (finalizedAt == nil).
  - If isLaunched == false → allow only finalized.
- Send; on success delete sent fences (keep session; optional: keep session until open data fetched; not required).

### 2.5 AppDelegate plumbing
- Change RMBTAppDelegate.checkNews(isLaunched: Bool) and calls from onStart(true|false).
- Pass isLaunched to resendPersistentAreas.

### 2.6 Logging
- Already added: “Stopping coverage test: sending N fences”.
- Add logs in resender: mode (cold/warm), filtered groups, counts, cleanup actions.

### 2.7 Tests & doubles
- Update FencePersistenceTests SUT factory to register PersistentCoverageSession in ModelContainer and expose helpers to insert sessions.
- Add FencePersistenceServiceSpy for VM tests with markSessionStarted/Finalized capture.
- Update makeSUT in NetworkCoverageViewModelTests to take the spy and to assert calls.
- Add tests per section 1.

## Suites & Files to touch
- New model: Sources/NetworkCoverage/Persistence/PersistentCoverageSession.swift
- Update: Sources/NetworkCoverage/NetworkCoverageFactory.swift (container includes model; wire session recorder)
- Update: Sources/NetworkCoverage/Persistence/SwiftDataFencePersistenceService.swift (new methods)
- Update: Sources/NetworkCoverage/Persistence/PersistedFencesResender.swift (isLaunched param, filtering, cleanup sessions)
- Update: Sources/NetworkCoverage/CoverageMeasurementSession/CoverageMeasurementSessionInitializer.swift (markSessionStarted)
- Update: Sources/NetworkCoverage/NetworkCoverageViewModel.swift (markSessionFinalized)
- Update: Sources/RMBTAppDelegate.swift (checkNews signature and call sites)
- Tests:
  - RMBTTests/NetworkCoverage/Persistence/FencePersistenceTests.swift (add 1–5)
  - RMBTTests/NetworkCoverage/NetworkCoverageViewModelTests.swift (add 6–8 + spy)
  - RMBTTests/NetworkCoverage/CoverageMeasurementSessionInitializerTests.swift (add 9)

## Done Criteria
- All new tests pass.
- Resend filtering matches user stories (warm FG skip unfinished; cold start resends unfinished).
- Session and fence cleanup executed on resend.
- Logs appear as specified.
