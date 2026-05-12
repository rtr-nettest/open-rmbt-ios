//
//  ResenderSessionBasedTests.swift
//  RMBTTests
//

import Testing
import Foundation
import CoreLocation
import SwiftData
@testable import RMBT

@MainActor
struct ResenderSessionBasedTests {
    @Test func whenReinitialized_thenSubmitsTwoSessions_withNegativeOffsetsInFirst() async throws {
        let baseTime = makeDate(offset: 100)
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { baseTime })

        // Create first session with pre-anchor and post-anchor fences
        try await persistence.sessionStarted(at: baseTime.advanced(by: -100))
        try await persistence.save(makeFence(dateEntered: baseTime.advanced(by: -90)))
        try await persistence.assignTestUUIDAndAnchor("S1", anchorNow: baseTime.advanced(by: -80))
        try await persistence.save(makeFence(dateEntered: baseTime.advanced(by: -70)))
        try await persistence.sessionFinalized(at: baseTime.advanced(by: -60))

        // Create second session
        try await persistence.sessionStarted(at: baseTime.advanced(by: -50))
        try await persistence.assignTestUUIDAndAnchor("S2", anchorNow: baseTime.advanced(by: -49))
        try await persistence.save(makeFence(dateEntered: baseTime.advanced(by: -48)))
        try await persistence.sessionFinalized(at: baseTime.advanced(by: -40))

        try await sut.resendPersistentAreas(isLaunched: true)

        try #require(sendSpy.calls.count == 2)
        let firstCall = try #require(sendSpy.calls.first)
        #expect(firstCall.uuid == "S1")
        #expect(firstCall.offsets?.first ?? 0 < 0, "First fence should have negative offset (pre-anchor)")

        let secondCall = try #require(sendSpy.calls.last)
        #expect(secondCall.uuid == "S2")
        #expect(secondCall.offsets?.allSatisfy { $0 >= 0 } == true, "All fences should have positive offsets")
    }

    @Test func whenWarmForeground_thenSubmitsOnlyFinalizedSessions() async throws {
        let now = makeDate(offset: 10_000)
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { now })

        // Create unfinished session (with fences)
        try await persistence.sessionStarted(at: now.advanced(by: -300))
        try await persistence.assignTestUUIDAndAnchor("unfinished", anchorNow: now.advanced(by: -290))
        try await persistence.save(makeFence(dateEntered: now.advanced(by: -285)))

        // Create finished session (with fences)
        try await persistence.sessionStarted(at: now.advanced(by: -200))
        try await persistence.assignTestUUIDAndAnchor("finished", anchorNow: now.advanced(by: -190))
        try await persistence.save(makeFence(dateEntered: now.advanced(by: -185)))
        try await persistence.sessionFinalized(at: now.advanced(by: -180))

        try await sut.resendPersistentAreas(isLaunched: false)

        #expect(sendSpy.calls.map { $0.uuid } == ["finished"])
    }

    @Test func whenOfflineStart_thenLateAnchorProducesNegativeOffsets() async throws {
        let t0 = makeDate(offset: 0)
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { t0 })

        // Save fences before anchor is set
        try await persistence.sessionStarted(at: t0)
        try await persistence.save(makeFence(dateEntered: t0.advanced(by: -5)))
        try await persistence.save(makeFence(dateEntered: t0.advanced(by: 3)))
        try await persistence.assignTestUUIDAndAnchor("S1", anchorNow: t0.advanced(by: 1))
        try await persistence.sessionFinalized(at: t0.advanced(by: 10))

        try await sut.resendPersistentAreas(isLaunched: true)

        let offsets = try #require(sendSpy.calls.first?.offsets)
        #expect(offsets.first == -6000, "First fence at t0-5 relative to anchor t0+1")
        #expect(offsets.last == 2000, "Second fence at t0+3 relative to anchor t0+1")
    }

    @Test func whenResending_thenCleansUpEmptyAndOldSessions() async throws {
        let (sut, _, persistence) = makeSUT()
        let now = Date()

        // Create empty session
        try await persistence.sessionStarted(at: now.advanced(by: -10_000))

        // Create old nil-UUID finalized session
        try await persistence.sessionStarted(at: now.advanced(by: -10_000))
        try await persistence.sessionFinalized(at: now.advanced(by: -9_999))

        try await sut.resendPersistentAreas(isLaunched: true)

        let remaining = try await persistence.sessionsToSubmitCold()
        #expect(remaining.isEmpty)
    }

    // MARK: - Empty Session Guard Tests

    @Test func whenColdResendingSessionWithZeroFences_thenSkipsSubmissionAndDeletesSession() async throws {
        let now = makeDate(offset: 500)
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { now })

        try await persistence.sessionStarted(at: now.advanced(by: -100))
        try await persistence.assignTestUUIDAndAnchor("empty-session", anchorNow: now.advanced(by: -90))
        try await persistence.sessionFinalized(at: now.advanced(by: -80))

        try await sut.resendPersistentAreas(isLaunched: true)

        #expect(sendSpy.calls.isEmpty, "Empty session should not be submitted")
        let remaining = try await persistence.sessionsToSubmitCold()
        #expect(remaining.isEmpty, "Empty session should be deleted")
    }

    @Test func whenWarmResendingFinalizedSessionWithZeroFences_thenSkipsSubmissionAndDeletesSession() async throws {
        let now = makeDate(offset: 500)
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { now })

        try await persistence.sessionStarted(at: now.advanced(by: -100))
        try await persistence.assignTestUUIDAndAnchor("empty-warm", anchorNow: now.advanced(by: -90))
        try await persistence.sessionFinalized(at: now.advanced(by: -80))

        try await sut.resendPersistentAreas(isLaunched: false)

        #expect(sendSpy.calls.isEmpty, "Empty session should not be submitted on warm start")
        let remaining = try await persistence.sessionsToSubmitWarm()
        #expect(remaining.isEmpty, "Empty session should be deleted on warm start")
    }

    @Test func whenWarmResendingMixOfEmptyAndNonEmptySessions_thenOnlySubmitsNonEmpty() async throws {
        let now = makeDate(offset: 500)
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { now })

        // Session S1 with 1 fence (finalized)
        try await persistence.sessionStarted(at: now.advanced(by: -200))
        try await persistence.assignTestUUIDAndAnchor("S1", anchorNow: now.advanced(by: -190))
        try await persistence.save(makeFence(dateEntered: now.advanced(by: -185)))
        try await persistence.sessionFinalized(at: now.advanced(by: -180))

        // Session S2 with 0 fences (finalized)
        try await persistence.sessionStarted(at: now.advanced(by: -100))
        try await persistence.assignTestUUIDAndAnchor("S2", anchorNow: now.advanced(by: -90))
        try await persistence.sessionFinalized(at: now.advanced(by: -80))

        try await sut.resendPersistentAreas(isLaunched: false)

        #expect(sendSpy.calls.count == 1, "Only non-empty session should be submitted")
        #expect(sendSpy.calls.first?.uuid == "S1")
        let remaining = try await persistence.sessionsToSubmitWarm()
        #expect(remaining.isEmpty, "Both sessions should be deleted")
    }

    // MARK: - Issue #60: Late anchoring of fully-offline sessions

    @Test func whenStrandedNilUUIDSessionWithFences_thenAnchorsAndSubmitsWithNegativeOffsets() async throws {
        let now = makeDate(offset: 1_000)
        let anchoringSpy = SessionAnchoringServiceSpy(scriptedTestUUIDs: ["LATE-ANCHOR"], anchorAt: now)
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { now }, sessionAnchoring: anchoringSpy)

        try await persistence.sessionStarted(at: now.advanced(by: -100))
        try await persistence.save(makeFence(dateEntered: now.advanced(by: -90)))
        try await persistence.save(makeFence(lat: 2, dateEntered: now.advanced(by: -60)))
        try await persistence.sessionFinalized(at: now.advanced(by: -30))

        try await sut.resendPersistentAreas(isLaunched: true)

        #expect(anchoringSpy.callCount == 1, "Stranded session must be anchored exactly once")
        try #require(sendSpy.calls.count == 1)
        let call = sendSpy.calls[0]
        #expect(call.uuid == "LATE-ANCHOR")
        let offsets = try #require(call.offsets)
        #expect(offsets.count == 2)
        #expect(offsets[0] == -90_000, "First offline fence (now-90s) → -90 000 ms relative to anchor=now")
        #expect(offsets[1] == -60_000, "Second offline fence (now-60s) → -60 000 ms relative to anchor=now")

        let remaining = try await persistence.sessionsToSubmitCold()
        #expect(remaining.isEmpty, "Session deleted after successful resend")
    }

    @Test func whenAnchoringFails_thenSessionPreservedForNextRound() async throws {
        let now = makeDate(offset: 200)
        let anchoringSpy = SessionAnchoringServiceSpy.alwaysFailing()
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { now }, sessionAnchoring: anchoringSpy)

        try await persistence.sessionStarted(at: now.advanced(by: -50))
        try await persistence.save(makeFence(dateEntered: now.advanced(by: -40)))
        try await persistence.sessionFinalized(at: now.advanced(by: -10))

        try await sut.resendPersistentAreas(isLaunched: false)

        #expect(anchoringSpy.callCount == 1)
        #expect(sendSpy.calls.isEmpty, "Send must not happen if anchoring failed")

        let allSessions = try await persistence.modelExecutor.modelContext.fetch(FetchDescriptor<PersistentCoverageSession>())
        #expect(allSessions.count == 1)
        #expect(allSessions.first?.testUUID == nil)
        #expect(allSessions.first?.fences.count == 1)
    }

    @Test func whenMultipleStrandedSessions_thenEachAnchoredSeparately() async throws {
        let now = makeDate(offset: 5_000)
        let anchoringSpy = SessionAnchoringServiceSpy(scriptedTestUUIDs: ["LATE-1", "LATE-2"], anchorAt: now)
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { now }, sessionAnchoring: anchoringSpy)

        try await persistence.sessionStarted(at: now.advanced(by: -300))
        try await persistence.save(makeFence(dateEntered: now.advanced(by: -290)))
        try await persistence.sessionFinalized(at: now.advanced(by: -280))

        try await persistence.sessionStarted(at: now.advanced(by: -200))
        try await persistence.save(makeFence(lat: 2, dateEntered: now.advanced(by: -190)))
        try await persistence.sessionFinalized(at: now.advanced(by: -180))

        try await sut.resendPersistentAreas(isLaunched: true)

        #expect(anchoringSpy.callCount == 2, "Each stranded session is anchored independently")
        #expect(sendSpy.calls.count == 2)
        let uuids = sendSpy.calls.map { $0.uuid }.sorted()
        #expect(uuids == ["LATE-1", "LATE-2"])
    }

    @Test func whenResenderHasNoAnchoringService_thenStrandedSessionsRemain() async throws {
        let now = makeDate(offset: 0)
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { now }, sessionAnchoring: nil)

        try await persistence.sessionStarted(at: now.advanced(by: -10))
        try await persistence.save(makeFence(dateEntered: now.advanced(by: -8)))
        try await persistence.sessionFinalized(at: now.advanced(by: -5))

        try await sut.resendPersistentAreas(isLaunched: true)

        #expect(sendSpy.calls.isEmpty)
        let allSessions = try await persistence.modelExecutor.modelContext.fetch(FetchDescriptor<PersistentCoverageSession>())
        #expect(allSessions.count == 1)
    }

    @Test func whenResendingSessionWithFences_thenSubmitsAndDeletesSession() async throws {
        let now = makeDate(offset: 500)
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { now })

        try await persistence.sessionStarted(at: now.advanced(by: -100))
        try await persistence.assignTestUUIDAndAnchor("with-fences", anchorNow: now.advanced(by: -90))
        try await persistence.save(makeFence(dateEntered: now.advanced(by: -85)))
        try await persistence.save(makeFence(lat: 2.0, dateEntered: now.advanced(by: -80)))
        try await persistence.sessionFinalized(at: now.advanced(by: -70))

        try await sut.resendPersistentAreas(isLaunched: true)

        #expect(sendSpy.calls.count == 1, "Non-empty session should be submitted")
        #expect(sendSpy.calls.first?.uuid == "with-fences")
        let remaining = try await persistence.sessionsToSubmitCold()
        #expect(remaining.isEmpty, "Session should be deleted after submission")
    }
}

// MARK: - Test Helpers

private func makeSUT(
    dateNow: @escaping () -> Date = Date.init,
    sessionAnchoring: (any SessionAnchoringService)? = nil
) -> (sut: PersistedFencesResender, sendSpy: SendServiceSpy, persistence: PersistenceServiceActor) {
    let database = UserDatabase(useInMemoryStore: true)
    let persistence = PersistenceServiceActor(modelContainer: database.container)
    let sendSpy = SendServiceSpy()
    let sut = PersistedFencesResender(
        persistence: persistence,
        sendResultsService: { uuid, anchor in
            CapturingSendService(sendSpy: sendSpy, uuid: uuid, anchor: anchor)
        },
        maxResendAge: 7 * 24 * 3600,
        dateNow: dateNow,
        sessionAnchoring: sessionAnchoring
    )
    return (sut, sendSpy, persistence)
}

private final class SessionAnchoringServiceSpy: SessionAnchoringService, @unchecked Sendable {
    private var scriptedTestUUIDs: [String]
    private let anchorAt: Date
    private let shouldFail: Bool
    private(set) var callCount = 0

    init(scriptedTestUUIDs: [String], anchorAt: Date) {
        self.scriptedTestUUIDs = scriptedTestUUIDs
        self.anchorAt = anchorAt
        self.shouldFail = false
    }

    private init(failing: Bool) {
        self.scriptedTestUUIDs = []
        self.anchorAt = Date()
        self.shouldFail = failing
    }

    static func alwaysFailing() -> SessionAnchoringServiceSpy {
        SessionAnchoringServiceSpy(failing: true)
    }

    func anchorOfflineSession() async throws -> (testUUID: String, anchorAt: Date) {
        callCount += 1
        if shouldFail {
            throw NSError(domain: "AnchoringFailed", code: -1)
        }
        guard !scriptedTestUUIDs.isEmpty else {
            throw NSError(domain: "AnchoringExhausted", code: -2)
        }
        return (scriptedTestUUIDs.removeFirst(), anchorAt)
    }
}


// MARK: - Test Doubles

private final class SendServiceSpy {
    struct Call {
        let uuid: String
        let anchor: Date
        let offsets: [Int]?
    }

    private(set) var calls: [Call] = []

    func recordSend(uuid: String, anchor: Date, offsets: [Int]?) {
        calls.append(.init(uuid: uuid, anchor: anchor, offsets: offsets))
    }
}

private struct CapturingSendService: SendCoverageResultsService {
    let sendSpy: SendServiceSpy
    let uuid: String
    let anchor: Date

    func send(fences: [Fence]) async throws {
        let request = SendCoverageResultRequest(
            fences: fences,
            testUUID: uuid,
            coverageStartDate: anchor
        )
        let offsets = request.fences.map { $0.offsetMiliseconds }
        sendSpy.recordSend(uuid: uuid, anchor: anchor, offsets: offsets)
    }
}

private struct MockSendService: SendCoverageResultsService {
    func send(fences: [Fence]) async throws {}
}
