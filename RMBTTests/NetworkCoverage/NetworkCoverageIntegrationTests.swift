//
//  NetworkCoverageIntegrationTests.swift
//  RMBTTests
//
//  Created by Jiri Urbasek on 11/25/25.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Testing
@testable import RMBT
import SwiftData
import CoreLocation
import Clocks

/// Integration tests for session reinitialization bug
///
/// These tests exercise the full stack: NetworkCoverageViewModel + PersistenceServiceActor + SendCoverageResultsService
/// to demonstrate the difference between correct behavior (with resend) and buggy behavior (without resend).
@MainActor
struct NetworkCoverageIntegrationTests {

    // MARK: - Test 1: WITH Resend Between Sessions (Expected Behavior After Fix)

    /// Tests the behavior when resend mechanism is manually triggered between session reinitializations.
    ///
    /// **Scenario:**
    /// 1. Start measurement → Session 1 begins
    /// 2. Collect 2 fences (lat 1.0, 2.0)
    /// 3. Session reinitialization → Session 1 finalized, Session 2 begins
    /// 4. **TRIGGER RESEND MANUALLY** → Session 1 fences sent via resender
    /// 5. Collect 1 fence (lat 3.0)
    /// 6. Stop measurement → Session 2 fences sent, then PersistenceManagingCoverageResultsService
    ///    automatically triggers another resend (but session 1 already sent, so nothing happens)
    ///
    /// **Expected (with production architecture):**
    /// - Send service called 2 times:
    ///   - Call 1 (via manual resend): UUID=session-1, fences=2 (lat 1.0, 2.0)
    ///   - Call 2 (via stop): UUID=session-2, fences=??? (depends on bug fix)
    ///
    /// **Current Status with Bug:** ❌ FAILS
    /// - Call 2 sends ALL accumulated fences (3 instead of 1)
    @Test func whenSessionReinitializedWithResendTriggered_thenEachSessionSentSeparately() async throws {
        let session1UUID = "session-1-uuid"
        let session2UUID = "session-2-uuid"

        let sessionState = CoverageSessionStateTracker()
        let updates = IntegrationTestUpdateStream(sessionState: sessionState)
        let (sut, resender, sendFactory, database) = await makeSUT(updateStream: updates, sessionState: sessionState)

        let measurementTask = Task { await sut.startTest() }
        defer {
            updates.finish()
            measurementTask.cancel()
        }
        await Task.yield()

        await updates.sendSessionInitialized(at: 0, sessionID: session1UUID)
        await updates.sendLocation          (at: 1, lat: 1.0, lon: 1.0)
        await updates.sendPing              (at: 2, ms: 100)
        await updates.sendLocation          (at: 3, lat: 2.0, lon: 2.0)
        await updates.sendPing              (at: 4, ms: 200)
        await updates.sendSessionInitialized(at: 5, sessionID: session2UUID)

        // Wait until the first session is finalized in persistence before triggering resend.
        await waitForFinalizedSessions(1, in: database)

        // Warm-start resend happens immediately after new session UUID assignment
        try await resender.resendPersistentAreas(isLaunched: false)

        await sendFactory.waitForCallCount(1)

        var calls = await sendFactory.sendCalls
        try #require(calls.count == 1, "Resend should have sent session 1")
        #expect(calls[0].testUUID == session1UUID)
        #expect(calls[0].fences.count == 1, "Session 1 has only 1 CLOSED fence at this point (lat 1.0). Fence at lat 2.0 is still open.")

        #expect(calls[0].fences.first?.startingLocation.coordinate.latitude == 1.0)

        await updates.sendLocation          (at: 6, lat: 3.0, lon: 3.0)
        await updates.sendPing              (at: 7, ms: 300)

        await sut.stopTest()
        await measurementTask.value

        await sendFactory.waitForCallCount(2)

        calls = await sendFactory.sendCalls
        try #require(calls.count == 2, "Stop should have sent session 2")

        let stopCall = calls[1]
        #expect(stopCall.testUUID == session2UUID)
        #expect(
            stopCall.fences.count == 2,
            "Stop should send session 2 fences: reassigned fence (lat 2.0) + new fence (lat 3.0)"
        )

        let stopLatitudes = stopCall.fences.map { $0.startingLocation.coordinate.latitude }.sorted()
        #expect(stopLatitudes == [2.0, 3.0], "Should send both fences from session 2")

        await database.wipeAll()
    }

    // MARK: - Test 2: WITHOUT Manual Resend (Documents Production Behavior + Bug)

    /// Verifies correct behavior when NO manual resend is triggered, relying only on automatic resend after stop.
    ///
    /// **Scenario:**
    /// 1. Start measurement → Session 1 begins
    /// 2. Collect 2 fences (lat 1.0, 2.0 - both created in session 1)
    /// 3. Session reinitialization → Session 1 finalized, Session 2 begins
    /// 4. **NO manual resend triggered**
    /// 5. Collect 1 fence (lat 3.0 - created in session 2)
    /// 6. Stop measurement → PersistenceManagingCoverageResultsService:
    ///    - First sends session 2 fences (current session)
    ///    - Then automatically triggers resend for finalized sessions (session 1)
    ///
    /// **Expected (after fix):**
    /// - Send service called 2 times:
    ///   - Call 1 (via stop for session 2): UUID=session-2, fences=1 (lat 3.0)
    ///   - Call 2 (via automatic resend): UUID=session-1, fences=2 (lat 1.0, 2.0)
    @Test func whenSessionReinitializedWithoutResend_thenEachSessionSentCorrectly() async throws {
        let session1UUID = "session-1-uuid"
        let session2UUID = "session-2-uuid"

        let sessionState = CoverageSessionStateTracker()
        let updates = IntegrationTestUpdateStream(sessionState: sessionState)
        let (sut, _, sendFactory, database) = await makeSUT(updateStream: updates, sessionState: sessionState)

        let measurementTask = Task { await sut.startTest() }
        defer {
            updates.finish()
            measurementTask.cancel()
        }
        await Task.yield()

        await updates.sendSessionInitialized(at: 0, sessionID: session1UUID)
        await updates.sendLocation          (at: 1, lat: 1.0, lon: 1.0)
        await updates.sendPing              (at: 2, ms: 100)
        await updates.sendLocation          (at: 3, lat: 2.0, lon: 2.0)
        await updates.sendPing              (at: 4, ms: 200)
        await updates.sendSessionInitialized(at: 5, sessionID: session2UUID)

        await waitForFinalizedSessions(1, in: database)

        // no resending logic triggered

        await updates.sendLocation          (at: 6, lat: 3.0, lon: 3.0)
        await updates.sendPing              (at: 7, ms: 300)

        await sut.stopTest()
        await measurementTask.value

        await sendFactory.waitForCallCount(2)

        let calls = await sendFactory.sendCalls
        try #require(calls.count == 2, "Stop should send session 2, then automatic resend sends session 1")

        let stopCall = calls[0]
        #expect(stopCall.testUUID == session2UUID)
        #expect(stopCall.fences.count == 2, "Stop should send session 2 fences (reassigned fence + new fence)")

        let stopLatitudes = stopCall.fences.map { $0.startingLocation.coordinate.latitude }.sorted()
        #expect(stopLatitudes == [2.0, 3.0], "Fence at lat 2.0 was reassigned to session 2, plus fence at lat 3.0 created in session 2")

        let resendCall = calls[1]
        #expect(resendCall.testUUID == session1UUID)
        #expect(resendCall.fences.count == 1, "Session 1 has only 1 fence (lat 1.0). Fence at lat 2.0 was reassigned to session 2.")
        let resendLatitudes = resendCall.fences.map { $0.startingLocation.coordinate.latitude }.sorted()
        #expect(resendLatitudes == [1.0], "Only fence closed before session reinitialization")

        await database.wipeAll()
    }
}

// MARK: - PersistenceManagingCoverageResultsService Integration Tests

/// Integration tests for PersistenceManagingCoverageResultsService filtering logic
///
/// These tests verify that the service correctly filters fences by sessionUUID and handles edge cases:
/// - Filters fences to only send those matching the current test UUID
/// - Triggers resend-only path when no fences match
/// - Handles mixed UUID scenarios correctly
/// - Properly manages persistence cleanup
@Suite("PersistenceManagingCoverageResultsService")
@MainActor
struct PersistenceManagingCoverageResultsServiceTests {

    // MARK: - Filtering Logic Tests

    @Test func whenAllFencesMatchCurrentSession_thenAllFencesSent() async throws {
        let testUUID = "test-uuid-123"
        let (sut, sendSpy, database) = await makePersistenceSUT(currentTestUUID: testUUID)

        let fences = [
            makeFence(lat: 1.0, lon: 1.0, sessionUUID: testUUID),
            makeFence(lat: 2.0, lon: 2.0, sessionUUID: testUUID),
            makeFence(lat: 3.0, lon: 3.0, sessionUUID: testUUID)
        ]

        try await sut.send(fences: fences)

        let sentFences = await sendSpy.capturedSentFences
        #expect(sentFences.count == 1, "Should have sent fences once")
        #expect(sentFences[0].count == 3, "Should send all 3 matching fences")
        #expect(sentFences[0].map { $0.startingLocation.coordinate.latitude } == [1.0, 2.0, 3.0])

        await database.wipeAll()
    }

    @Test func whenFencesHaveMixedSessionUUIDs_thenOnlyMatchingFencesSent() async throws {
        let currentUUID = "current-session"
        let oldUUID = "old-session"
        let (sut, sendSpy, database) = await makePersistenceSUT(currentTestUUID: currentUUID)

        let fences = [
            makeFence(lat: 1.0, lon: 1.0, sessionUUID: oldUUID),
            makeFence(lat: 2.0, lon: 2.0, sessionUUID: currentUUID),
            makeFence(lat: 3.0, lon: 3.0, sessionUUID: oldUUID),
            makeFence(lat: 4.0, lon: 4.0, sessionUUID: currentUUID)
        ]

        try await sut.send(fences: fences)

        let sentFences = await sendSpy.capturedSentFences
        #expect(sentFences.count == 1, "Should have sent fences once")
        #expect(sentFences[0].count == 2, "Should send only 2 fences matching current UUID")

        let sentLatitudes = sentFences[0].map { $0.startingLocation.coordinate.latitude }
        #expect(sentLatitudes == [2.0, 4.0], "Should only send fences from current session")

        await database.wipeAll()
    }

    @Test func whenNoFencesMatchCurrentSession_thenResendOnlyPathTriggered() async throws {
        let currentUUID = "current-session"
        let oldUUID = "old-session"
        let (sut, sendSpy, database) = await makePersistenceSUT(currentTestUUID: currentUUID)

        let fences = [
            makeFence(lat: 1.0, lon: 1.0, sessionUUID: oldUUID),
            makeFence(lat: 2.0, lon: 2.0, sessionUUID: oldUUID)
        ]

        try await sut.send(fences: fences)

        let sentFences = await sendSpy.capturedSentFences
        #expect(sentFences.isEmpty, "Should not send any fences when none match current session")

        await database.wipeAll()
    }

    @Test func whenAllFencesHaveNilSessionUUID_thenResendOnlyPathTriggered() async throws {
        let currentUUID = "current-session"
        let (sut, sendSpy, database) = await makePersistenceSUT(currentTestUUID: currentUUID)

        let fences = [
            makeFence(lat: 1.0, lon: 1.0, sessionUUID: nil),
            makeFence(lat: 2.0, lon: 2.0, sessionUUID: nil)
        ]

        try await sut.send(fences: fences)

        let sentFences = await sendSpy.capturedSentFences
        #expect(sentFences.isEmpty, "Should not send fences with nil sessionUUID")

        await database.wipeAll()
    }

    @Test func whenEmptyFencesArray_thenResendOnlyPathTriggered() async throws {
        let currentUUID = "current-session"
        let (sut, sendSpy, database) = await makePersistenceSUT(currentTestUUID: currentUUID)

        try await sut.send(fences: [])

        let sentFences = await sendSpy.capturedSentFences
        #expect(sentFences.isEmpty, "Should not send empty array")

        await database.wipeAll()
    }

    @Test func whenMixedNilAndMatchingUUIDs_thenOnlyMatchingFencesSent() async throws {
        let currentUUID = "current-session"
        let (sut, sendSpy, database) = await makePersistenceSUT(currentTestUUID: currentUUID)

        let fences = [
            makeFence(lat: 1.0, lon: 1.0, sessionUUID: nil),
            makeFence(lat: 2.0, lon: 2.0, sessionUUID: currentUUID),
            makeFence(lat: 3.0, lon: 3.0, sessionUUID: nil),
            makeFence(lat: 4.0, lon: 4.0, sessionUUID: currentUUID)
        ]

        try await sut.send(fences: fences)

        let sentFences = await sendSpy.capturedSentFences
        #expect(sentFences.count == 1)
        #expect(sentFences[0].count == 2, "Should send only fences with matching UUID")

        let sentLatitudes = sentFences[0].map { $0.startingLocation.coordinate.latitude }
        #expect(sentLatitudes == [2.0, 4.0])

        await database.wipeAll()
    }

    // MARK: - Error Handling Tests

    @Test func whenMissingTestUUID_thenThrowsError() async throws {
        let (sut, _, database) = await makePersistenceSUT(currentTestUUID: nil)

        let fences = [makeFence(lat: 1.0, lon: 1.0, sessionUUID: "some-uuid")]

        await #expect(throws: PersistenceManagingCoverageResultsService.ServiceError.missingTestUUID) {
            try await sut.send(fences: fences)
        }

        await database.wipeAll()
    }

    // MARK: - Persistence Cleanup Tests

    @Test func whenSendSucceeds_thenSessionDeletedFromDatabase() async throws {
        let testUUID = "test-uuid-456"
        let (sut, _, database) = await makePersistenceSUT(currentTestUUID: testUUID)

        // Create a session in the database
        let now = Date()
        let session = PersistentCoverageSession(
            testUUID: testUUID,
            startedAt: UInt64(now.timeIntervalSince1970 * 1_000_000),
            finalizedAt: nil
        )
        database.modelContext.insert(session)
        try database.modelContext.save()

        let fences = [makeFence(lat: 1.0, lon: 1.0, sessionUUID: testUUID)]

        try await sut.send(fences: fences)

        // Verify session was deleted
        let descriptor = FetchDescriptor<PersistentCoverageSession>(
            predicate: #Predicate { $0.testUUID == testUUID }
        )
        let remainingSessions = try database.modelContext.fetch(descriptor)
        #expect(remainingSessions.isEmpty, "Session should be deleted after successful send")

        await database.wipeAll()
    }

    @Test func whenSendFails_thenSessionRemainsInDatabase() async throws {
        let testUUID = "test-uuid-789"
        let sendError = NSError(domain: "test", code: 500, userInfo: nil)
        let (sut, _, database) = await makePersistenceSUT(
            currentTestUUID: testUUID,
            sendResult: .failure(sendError)
        )

        // Create a session in the database
        let now = Date()
        let session = PersistentCoverageSession(
            testUUID: testUUID,
            startedAt: UInt64(now.timeIntervalSince1970 * 1_000_000),
            finalizedAt: nil
        )
        database.modelContext.insert(session)
        try database.modelContext.save()

        let fences = [makeFence(lat: 1.0, lon: 1.0, sessionUUID: testUUID)]

        do {
            try await sut.send(fences: fences)
            Issue.record("Expected send to fail")
        } catch {
            // Expected error
        }

        // Verify session was NOT deleted
        let descriptor = FetchDescriptor<PersistentCoverageSession>(
            predicate: #Predicate { $0.testUUID == testUUID }
        )
        let remainingSessions = try database.modelContext.fetch(descriptor)
        #expect(remainingSessions.count == 1, "Session should remain in database after failed send")

        await database.wipeAll()
    }

    @Test func whenSuccessfulSend_thenResendTriggeredForRemainingSession() async throws {
        let currentUUID = "current-session"
        let (sut, sendSpy, database) = await makePersistenceSUT(currentTestUUID: currentUUID)

        // Create a finalized session that should be picked up by resend
        let now = Date()
        let oldSession = PersistentCoverageSession(
            testUUID: "old-session-uuid",
            startedAt: UInt64(now.addingTimeInterval(-3600).timeIntervalSince1970 * 1_000_000),
            finalizedAt: UInt64(now.addingTimeInterval(-1800).timeIntervalSince1970 * 1_000_000)
        )
        database.modelContext.insert(oldSession)

        // Create a fence for the old session using the Fence domain model
        let oldFence = makeFence(lat: 5.0, lon: 5.0, sessionUUID: "old-session-uuid")
        let persistentFence = PersistentFence(from: oldFence)
        oldSession.fences.append(persistentFence)
        database.modelContext.insert(persistentFence)
        try database.modelContext.save()

        let fences = [makeFence(lat: 1.0, lon: 1.0, sessionUUID: currentUUID)]

        try await sut.send(fences: fences)

        // Should have sent current session fences plus triggered resend for old session
        let sentFences = await sendSpy.capturedSentFences
        #expect(sentFences.count >= 1, "Should have sent current session fences")
        #expect(sentFences[0].count == 1, "First call should send current session fence")

        await database.wipeAll()
    }
}

// MARK: - Test Helpers

// MARK: - PersistenceManagingCoverageResultsService Test Helpers

/// Creates PersistenceManagingCoverageResultsService with real dependencies and spy for send service
@MainActor
private func makePersistenceSUT(
    currentTestUUID: String?,
    sendResult: Result<Void, Error> = .success(())
) async -> (
    sut: PersistenceManagingCoverageResultsService,
    sendSpy: SendCoverageResultsServiceSpy,
    database: UserDatabase
) {
    let database = UserDatabase(useInMemoryStore: true)
    let sendSpy = SendCoverageResultsServiceSpy(sendResult: sendResult)

    let factory = NetworkCoverageFactory(
        database: database,
        maxResendAge: 7 * 24 * 3600,
        dateNow: { Date() }
    )

    let resender = factory.makeResender { _, _ in sendSpy }

    let sut = PersistenceManagingCoverageResultsService(
        modelContext: database.modelContext,
        testUUID: currentTestUUID,
        sendResultsService: { _ in sendSpy },
        resender: resender
    )

    return (sut, sendSpy, database)
}

/// Factory method to create Fence with optional sessionUUID
private func makeFence(
    lat: CLLocationDegrees,
    lon: CLLocationDegrees,
    sessionUUID: String? = nil,
    dateEntered: Date = Date(timeIntervalSinceReferenceDate: 0),
    technology: String? = nil,
    pings: [PingResult] = [],
    radiusMeters: CLLocationDistance = 20
) -> Fence {
    var fence = Fence(
        startingLocation: CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: 1,
            verticalAccuracy: 1,
            timestamp: dateEntered
        ),
        dateEntered: dateEntered,
        technology: technology,
        pings: pings,
        radiusMeters: radiusMeters
    )
    fence.sessionUUID = sessionUUID
    return fence
}

// MARK: - NetworkCoverageViewModel Test Helpers

/// Creates NetworkCoverageViewModel with real persistence and resender, spy for send service
@MainActor
private func makeSUT(
    updateStream: IntegrationTestUpdateStream,
    sessionState: CoverageSessionStateTracker,
    dateProvider: @escaping () -> Date = { Date(timeIntervalSinceReferenceDate: 0) },
    clock: any Clock<Duration> = ContinuousClock()
) async -> (
    vm: NetworkCoverageViewModel,
    resender: PersistedFencesResender,
    sendServiceFactory: IntegrationTestSendServiceFactory,
    database: UserDatabase
) {
    let database = UserDatabase(useInMemoryStore: true)

    // Create send service factory that captures all calls
    let sendServiceFactory = IntegrationTestSendServiceFactory()

    // Use NetworkCoverageFactory to create services with proper architecture
    let factory = NetworkCoverageFactory(
        database: database,
        maxResendAge: 7 * 24 * 3600,
        dateNow: dateProvider
    )

    // Create services using factory - this gives us PersistenceManagingCoverageResultsService
    let (persistenceService, sendResultsService) = factory.services(
        testUUID: sessionState.currentTestUUID,
        startDate: dateProvider(),
        dateNow: dateProvider,
        sendResultsServiceMaker: { testUUID, startDate in
            sendServiceFactory.createServiceSync(for: testUUID, startDate: startDate)
        }
    )

    // Create resender using factory
    let resender = factory.makeResender { testUUID, startDate in
        sendServiceFactory.createServiceSync(for: testUUID, startDate: startDate)
    }

    // Create view model with factory-created services
    let vm = NetworkCoverageViewModel(
        fences: [],
        refreshInterval: 1,
        minimumLocationAccuracy: 100,
        locationInaccuracyWarningInitialDelay: 3.0,
        insufficientAccuracyAutoStopInterval: 30 * 60,
        updates: { updateStream.stream.asOpaque() },
        currentRadioTechnology: RadioTechnologyServiceStub(),
        sendResultsService: sendResultsService,
        persistenceService: persistenceService,
        locale: Locale(identifier: "en_US"),
        timeNow: dateProvider,
        clock: clock,
        maxTestDuration: { 4 * 60 * 60 }
    )

    return (vm, resender, sendServiceFactory, database)
}

/// Factory that creates SendCoverageResultsService instances and captures all send calls
actor IntegrationTestSendServiceFactory {
    struct SendCall {
        let testUUID: String
        let fences: [Fence]
        let timestamp: Date
    }

    private(set) var sendCalls: [SendCall] = []
    private var services: [String: IntegrationTestSendService] = [:]

    func createService(for testUUID: String, startDate: Date?) -> IntegrationTestSendService {
        if let existing = services[testUUID] {
            return existing
        }

        let service = IntegrationTestSendService(
            testUUID: testUUID,
            onSend: { [weak self] fences in
                await self?.recordSend(testUUID: testUUID, fences: fences)
            }
        )
        services[testUUID] = service
        return service
    }

    nonisolated func createServiceSync(for testUUID: String, startDate: Date?) -> IntegrationTestSendService {
        // Create service without storing it, just for resender
        return IntegrationTestSendService(
            testUUID: testUUID,
            onSend: { [weak self] fences in
                await self?.recordSend(testUUID: testUUID, fences: fences)
            }
        )
    }

    private func recordSend(testUUID: String, fences: [Fence]) {
        sendCalls.append(SendCall(testUUID: testUUID, fences: fences, timestamp: Date()))
    }

    func waitForCallCount(
        _ expected: Int,
        clock testClock: TestClock<Duration>? = nil,
        timeout: Duration = .milliseconds(500)
    ) async {
        let continuousClock = ContinuousClock()
        let start = continuousClock.now
        while sendCalls.count < expected {
            if continuousClock.now - start > timeout {
                return
            }
            if let testClock {
                await testClock.advance(by: .nanoseconds(1))
            } else {
                await Task.yield()
            }
        }
    }
}

/// Wrapper that captures send calls while implementing SendCoverageResultsService
final class IntegrationTestSendService: SendCoverageResultsService {
    private let testUUID: String
    private let onSend: ([Fence]) async -> Void

    init(testUUID: String, onSend: @escaping ([Fence]) async -> Void) {
        self.testUUID = testUUID
        self.onSend = onSend
    }

    func send(fences: [Fence]) async throws {
        await onSend(fences)
        // Don't actually send to server in tests
    }
}

@MainActor
private final class CoverageSessionStateTracker {
    private(set) var currentTestUUID: String?
    private(set) var currentStartDate: Date?

    func registerSession(id: String, startedAt date: Date) {
        currentTestUUID = id
        currentStartDate = date
    }
}

@MainActor
private final class IntegrationTestUpdateStream {
    let stream: AsyncStream<NetworkCoverageViewModel.Update>
    private let sessionState: CoverageSessionStateTracker
    private let continuation: AsyncStream<NetworkCoverageViewModel.Update>.Continuation

    init(sessionState: CoverageSessionStateTracker) {
        self.sessionState = sessionState
        var continuation: AsyncStream<NetworkCoverageViewModel.Update>.Continuation!
        self.stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func sendSessionInitialized(at offset: TimeInterval, sessionID: String) async {
        let update = makeSessionInitializedUpdate(at: offset, sessionID: sessionID)
        if case .sessionInitialized(let payload) = update {
            sessionState.registerSession(id: payload.sessionID, startedAt: payload.timestamp)
        }
        continuation.yield(update)
        await Task.yield()
    }

    func sendLocation(at offset: TimeInterval, lat: CLLocationDegrees, lon: CLLocationDegrees) async {
        continuation.yield(makeLocationUpdate(at: offset, lat: lat, lon: lon))
        await Task.yield()
    }

    func sendPing(at offset: TimeInterval, ms: some BinaryInteger) async {
        continuation.yield(makePingUpdate(at: offset, ms: ms))
        await Task.yield()
    }

    func finish() {
        continuation.finish()
    }
}

private func makeDateProvider(
    clock: TestClock<Duration>,
    baseDate: Date = Date(timeIntervalSinceReferenceDate: 0)
) -> () -> Date {
    let initialInstant = clock.now
    return {
        let delta = initialInstant.duration(to: clock.now)
        return baseDate.addingTimeInterval(delta.timeInterval)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        let seconds = TimeInterval(components.seconds)
        let attoseconds = TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
        return seconds + attoseconds
    }
}

@MainActor
private func waitForFinalizedSessions(
    _ expectedCount: Int,
    in database: UserDatabase,
    clock testClock: TestClock<Duration>? = nil,
    timeout: Duration = .milliseconds(500),
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let continuousClock = ContinuousClock()
    let start = continuousClock.now
    while true {
        let descriptor = FetchDescriptor<PersistentCoverageSession>(predicate: #Predicate { $0.finalizedAt != nil })
        let sessions = (try? database.modelContext.fetch(descriptor)) ?? []
        if sessions.count >= expectedCount {
            return
        }
        if continuousClock.now - start > timeout {
            Issue.record("Timed out waiting for finalized sessions", sourceLocation: sourceLocation)
            return
        }
        if let testClock {
            await testClock.advance(by: .nanoseconds(1))
        } else {
            await Task.yield()
        }
    }
}

extension UserDatabase {
    @MainActor
    func wipeAll() async {
        // Clean up the in-memory database after tests
        do {
            try modelContext.delete(model: PersistentCoverageSession.self)
            try modelContext.delete(model: PersistentFence.self)
            try modelContext.save()
        } catch {
            print("Failed to wipe database: \(error)")
        }
    }
}
