//
//  CleanupDuringMeasurementTests.swift
//  RMBTTests
//
//  Tests for the cold start cleanup issue during active measurements
//  TDD approach: Write failing tests first, then fix production code
//

import Testing
import Foundation
import CoreLocation
import SwiftData
@testable import RMBT

@MainActor
struct CleanupDuringMeasurementTests {

    // MARK: - Warm Start Protection

    /// Test that warm start does NOT delete sessions without UUID (protects active measurements)
    /// Warm starts can happen during measurements (app foreground, speed test start)
    @Test func givenSessionWithoutUUID_whenWarmResend_thenSessionPreserved() async throws {
        let now = Date()
        let (sut, _, persistence) = makeSUT(dateNow: { now })

        // Create a session waiting for UUID (active measurement)
        try await persistence.sessionStarted(at: now)

        // Verify session exists
        let allSessions = try await getAllSessions(persistence)
        #expect(allSessions.count == 1, "Session should exist")

        // Warm resend operation (cleanup should NOT run)
        try await sut.resendPersistentAreas(isLaunched: false)

        // EXPECTED: Session preserved (cleanup doesn't run on warm start)
        let remainingSessions = try await getAllSessions(persistence)
        #expect(remainingSessions.count == 1, "Session should be preserved - no cleanup on warm start")
    }

    /// Test that finalized sessions without UUID ARE cleaned up (they can never be sent)
    @Test func givenFinalizedSessionWithoutUUID_whenCleanup_thenShouldBeDeleted() async throws {
        let now = Date()
        let (sut, _, persistence) = makeSUT(dateNow: { now })

        // Create session that started offline, collected fences, but never got UUID
        try await persistence.sessionStarted(at: now.advanced(by: -100))
        try await persistence.save(makeFence(date: now.advanced(by: -90)))
        try await persistence.sessionFinalized(at: now.advanced(by: -80))
        // Note: No assignTestUUIDAndAnchor - it never connected to server

        // Cleanup should remove this session (it can never be sent)
        try await sut.resendPersistentAreas(isLaunched: true)

        let remainingSessions = try await getAllSessions(persistence)
        #expect(remainingSessions.isEmpty, "Finalized session without UUID should be deleted")
    }

    /// Test that sessions with UUID but failed send are NOT deleted
    @Test func givenFinalizedSessionWithUUID_whenSendFails_thenSessionKeptForRetry() async throws {
        let now = Date()
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { now })

        try await persistence.sessionStarted(at: now.advanced(by: -100))
        try await persistence.assignTestUUIDAndAnchor("failed-session", anchorNow: now.advanced(by: -90))
        try await persistence.save(makeFence(date: now.advanced(by: -80)))
        try await persistence.sessionFinalized(at: now.advanced(by: -70))

        // Make send fail, leads to status code 501 error
        sendSpy.shouldFail = true

        // Try to resend
        try? await sut.resendPersistentAreas(isLaunched: true)

        // Session should remain for retry
        let remainingSessions = try await persistence.sessionsToSubmitCold()
        #expect(remainingSessions.count == 1, "Failed session should be kept for retry")
        #expect(remainingSessions.first?.testUUID == "failed-session")
    }

    // MARK: - Session Lifecycle Tests

    /// Test the correct session lifecycle: start → assign UUID → finalize
    @Test func givenSessionStarted_whenUUIDAssigned_thenShouldUpdateExistingSession() async throws {
        let now = Date()
        let (_, _, persistence) = makeSUT(dateNow: { now })

        // 1. Start session (creates session with nil UUID)
        try await persistence.sessionStarted(at: now)

        let sessionsAfterStart = try await getAllSessions(persistence)
        #expect(sessionsAfterStart.count == 1)
        let sessionAfterStart = try #require(sessionsAfterStart.first)
        #expect(sessionAfterStart.testUUID == nil)
        #expect(sessionAfterStart.anchorAt == nil)

        // 2. Assign UUID (should UPDATE the same session, not create new one)
        try await persistence.assignTestUUIDAndAnchor("test-uuid-123", anchorNow: now.advanced(by: 1))

        let sessionsAfterAssign = try await getAllSessions(persistence)
        #expect(sessionsAfterAssign.count == 1, "Should still be 1 session (updated, not created)")
        let sessionAfterAssign = try #require(sessionsAfterAssign.first)
        #expect(sessionAfterAssign.testUUID == "test-uuid-123")
        #expect(sessionAfterAssign.anchorAt != nil)
    }

    /// Test that active (unfinalized) sessions are not sent during resend
    /// Cleanup runs but only affects empty/orphaned sessions, not sessions with UUID+fences
    @Test func givenUnfinalizedSession_whenResend_thenNotSent() async throws {
        let now = Date()
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { now })

        // 1. Start measurement and assign UUID
        try await persistence.sessionStarted(at: now.advanced(by: -10))
        try await persistence.assignTestUUIDAndAnchor("active-session", anchorNow: now.advanced(by: -9))
        try await persistence.save(makeFence(date: now.advanced(by: -8)))
        // Note: NOT finalized yet - measurement is ongoing

        // 2. Resend operation (cleanup runs, but session has UUID+fences so it's preserved)
        try await sut.resendPersistentAreas(isLaunched: false)

        // 3. Unfinalized session should NOT be sent (warm resend only sends finalized)
        #expect(sendSpy.calls.isEmpty, "Unfinalized session should not be sent")

        let remainingSessions = try await getAllSessions(persistence)
        #expect(remainingSessions.count == 1, "Session with UUID+fences should remain")
        #expect(remainingSessions.first?.testUUID == "active-session")
    }

    // MARK: - Cold vs Warm Start Behavior

    /// Test that cold start (app launch) resends all sessions with UUID
    @Test func givenMultipleFinalizedSessions_whenColdStart_thenResendsAll() async throws {
        let now = Date()
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { now })

        // Create 2 finalized sessions from previous runs
        try await persistence.sessionStarted(at: now.advanced(by: -200))
        try await persistence.assignTestUUIDAndAnchor("session1", anchorNow: now.advanced(by: -190))
        try await persistence.save(makeFence(date: now.advanced(by: -180)))
        try await persistence.sessionFinalized(at: now.advanced(by: -170))

        try await persistence.sessionStarted(at: now.advanced(by: -100))
        try await persistence.assignTestUUIDAndAnchor("session2", anchorNow: now.advanced(by: -90))
        try await persistence.save(makeFence(date: now.advanced(by: -80)))
        try await persistence.sessionFinalized(at: now.advanced(by: -70))

        // Cold start should resend both
        try await sut.resendPersistentAreas(isLaunched: true)

        #expect(sendSpy.calls.count == 2, "Cold start should resend all finalized sessions")
        #expect(sendSpy.calls.map { $0.uuid }.contains("session1"))
        #expect(sendSpy.calls.map { $0.uuid }.contains("session2"))
    }

    /// Test that warm start only resends finalized sessions (skips active ones)
    @Test func givenActiveAndFinalizedSessions_whenWarmStart_thenResendsOnlyFinalized() async throws {
        let now = Date()
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { now })

        // Create active session
        try await persistence.sessionStarted(at: now.advanced(by: -100))
        try await persistence.assignTestUUIDAndAnchor("active", anchorNow: now.advanced(by: -90))
        try await persistence.save(makeFence(date: now.advanced(by: -80)))
        // Not finalized

        // Create finalized session
        try await persistence.sessionStarted(at: now.advanced(by: -50))
        try await persistence.assignTestUUIDAndAnchor("finalized", anchorNow: now.advanced(by: -40))
        try await persistence.save(makeFence(date: now.advanced(by: -30)))
        try await persistence.sessionFinalized(at: now.advanced(by: -20))

        // Warm start should only resend finalized
        try await sut.resendPersistentAreas(isLaunched: false)

        #expect(sendSpy.calls.count == 1, "Warm start should only resend finalized sessions")
        #expect(sendSpy.calls.first?.uuid == "finalized")
    }

    // MARK: - Cleanup Edge Cases

    /// Test that empty finalized sessions are cleaned up
    @Test func givenEmptyFinalizedSession_whenCleanup_thenShouldBeDeleted() async throws {
        let now = Date()
        let (sut, _, persistence) = makeSUT(dateNow: { now })

        // Create session that was finalized but never collected any fences
        try await persistence.sessionStarted(at: now.advanced(by: -100))
        try await persistence.assignTestUUIDAndAnchor("empty-session", anchorNow: now.advanced(by: -90))
        // No fences saved
        try await persistence.sessionFinalized(at: now.advanced(by: -80))

        try await sut.resendPersistentAreas(isLaunched: true)

        let remainingSessions = try await getAllSessions(persistence)
        #expect(remainingSessions.isEmpty, "Empty finalized session should be deleted")
    }

    /// Test that sessions older than maxAge are deleted
    @Test func givenOldSession_whenCleanup_thenShouldBeDeleted() async throws {
        let now = Date()
        let maxAge: TimeInterval = 7 * 24 * 3600 // 7 days
        let (sut, _, persistence) = makeSUT(dateNow: { now }, maxResendAge: maxAge)

        // Create session from 8 days ago
        let oldDate = now.advanced(by: -8 * 24 * 3600)
        try await persistence.sessionStarted(at: oldDate)
        try await persistence.assignTestUUIDAndAnchor("old-session", anchorNow: oldDate.advanced(by: 1))
        try await persistence.save(makeFence(date: oldDate.advanced(by: 2)))
        try await persistence.sessionFinalized(at: oldDate.advanced(by: 3))

        try await sut.resendPersistentAreas(isLaunched: true)

        let remainingSessions = try await getAllSessions(persistence)
        #expect(remainingSessions.isEmpty, "Sessions older than maxAge should be deleted")
    }
}

// MARK: - Test Helpers

extension CleanupDuringMeasurementTests {
    func makeSUT(
        dateNow: @escaping () -> Date = Date.init,
        maxResendAge: TimeInterval = 7 * 24 * 3600
    ) -> (
        sut: PersistedFencesResender,
        sendSpy: CleanupTestSendServiceSpy,
        persistence: PersistenceServiceActor
    ) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: PersistentCoverageSession.self, PersistentFence.self,
            configurations: config
        )

        let persistence = PersistenceServiceActor(modelContainer: container)
        let sendSpy = CleanupTestSendServiceSpy()

        let sut = PersistedFencesResender(
            persistence: persistence,
            sendResultsService: { uuid, anchorDate in
                sendSpy.testUUID = uuid
                sendSpy.anchorDate = anchorDate
                return sendSpy
            },
            maxResendAge: maxResendAge,
            dateNow: dateNow
        )

        return (sut, sendSpy, persistence)
    }

    func makeFence(date: Date = Date(), lat: Double = 49.0, lon: Double = 13.0) -> Fence {
        Fence(
            startingLocation: CLLocation(latitude: lat, longitude: lon),
            dateEntered: date,
            technology: "4G/LTE",
            pings: [],
            radiusMeters: 20
        )
    }

    func makeDate(offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: offset)
    }

    func getAllSessions(_ persistence: PersistenceServiceActor) async throws -> [PersistentCoverageSession] {
        // Query all sessions regardless of state
        try await persistence.modelExecutor.modelContext.fetch(FetchDescriptor<PersistentCoverageSession>())
    }
}

// MARK: - Test Spy

@MainActor
class CleanupTestSendServiceSpy: SendCoverageResultsService {
    var testUUID: String?
    var anchorDate: Date?
    var shouldFail = false

    struct Call {
        let uuid: String
        let fenceCount: Int
        let offsets: [Int]?
    }

    var calls: [Call] = []

    func send(fences: [Fence]) async throws {
        if shouldFail {
            throw NSError(domain: "TestError", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not Acceptable"])
        }

        guard let uuid = testUUID, let anchorDate = anchorDate else {
            throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing UUID or anchor"])
        }

        // Calculate offsets like the real service does
        let offsets = fences.map { fence in
            let deltaUs = Int64(fence.dateEntered.microsecondsTimestamp) - Int64(anchorDate.microsecondsTimestamp)
            return Int(deltaUs / 1_000)
        }

        calls.append(Call(uuid: uuid, fenceCount: fences.count, offsets: offsets))
    }
}
