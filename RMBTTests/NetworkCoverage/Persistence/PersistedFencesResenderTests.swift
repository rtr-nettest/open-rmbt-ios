//
//  PersistedFencesResenderTests.swift
//  RMBTTests
//
//  Created by Jiri Urbasek on 20.10.2025.
//

import Testing
import Foundation
import SwiftData
@testable import RMBT

@MainActor
struct PersistedFencesResenderTests {
    @Test func whenColdStart_andUnfinishedSession_thenResendsUnfinishedAndFinalized() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let finalizedFenceBase = now.addingTimeInterval(-120)

        let (sut, persistence, sendService) = makeResenderSUT(dateNow: { now })

        let unfinishedUUID = "unfinished-test"
        let finalizedUUID = "finalized-test"

        let unfinishedSession = makePersistentSession(testUUID: unfinishedUUID, startedAt: now.addingTimeInterval(-60).microsecondsTimestamp)
        let unfinishedFences = [
            makePersistentFence(testUUID: unfinishedUUID, timestamp: now.addingTimeInterval(-30).microsecondsTimestamp),

            makePersistentFence(testUUID: unfinishedUUID, timestamp: now.addingTimeInterval(-20).microsecondsTimestamp)
        ]
        let finalizedSession = makePersistentSession(
            testUUID: finalizedUUID,
            startedAt: now.addingTimeInterval(-600).microsecondsTimestamp,
            finalizedAt: finalizedFenceBase.microsecondsTimestamp
        )
        let finalizedFences = [
            makePersistentFence(testUUID: finalizedUUID, timestamp: finalizedFenceBase.addingTimeInterval(-40).microsecondsTimestamp),
            makePersistentFence(testUUID: finalizedUUID, timestamp: finalizedFenceBase.addingTimeInterval(-50).microsecondsTimestamp)
        ]
        try persistence.saveMocked(
            coverageSessions: [unfinishedSession, finalizedSession],
            fences: unfinishedFences + finalizedFences
        )

        try await sut.resendPersistentAreas(isLaunched: true)

        try expect(capturedSendCalls: sendService.capturedSendCalls, equals: [(
                testUUID: unfinishedUUID,
                fenceDates: [
                    now.addingTimeInterval(-30),
                    now.addingTimeInterval(-20)
                ]
            ),(
                testUUID: finalizedUUID,
                fenceDates: [
                    finalizedFenceBase.addingTimeInterval(-40),
                    finalizedFenceBase.addingTimeInterval(-50)
                ]
            )]
        )
    }

    @Test func whenWarmForeground_andUnfinishedSession_thenSkipsUnfinished() async throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let (sut, persistence, sendService) = makeResenderSUT(dateNow: { now })

        let unfinishedUUID = "unfinished-test"
        let finalizedUUID = "finalized-test"

        let unfinishedSession = makePersistentSession(testUUID: unfinishedUUID, startedAt: now.addingTimeInterval(-45).microsecondsTimestamp)
        let unfinishedFences = [
            makePersistentFence(testUUID: unfinishedUUID, timestamp: now.addingTimeInterval(-30).microsecondsTimestamp)
        ]

        let finalizedSession = makePersistentSession(
            testUUID: finalizedUUID,
            startedAt: now.addingTimeInterval(-600).microsecondsTimestamp,
            finalizedAt: now.addingTimeInterval(-300).microsecondsTimestamp
        )
        let finalizedFences = [
            makePersistentFence(testUUID: finalizedUUID, timestamp: now.addingTimeInterval(-400).microsecondsTimestamp),
            makePersistentFence(testUUID: finalizedUUID, timestamp: now.addingTimeInterval(-320).microsecondsTimestamp)
        ]

        try persistence.saveMocked(
            coverageSessions: [unfinishedSession, finalizedSession],
            fences: unfinishedFences + finalizedFences
        )

        try await sut.resendPersistentAreas(isLaunched: false)

        try expect(
            capturedSendCalls: sendService.capturedSendCalls,
            equals: [
                (
                    testUUID: finalizedUUID,
                    fenceDates: [
                        now.addingTimeInterval(-400),
                        now.addingTimeInterval(-320)
                    ]
                )
            ]
        )
    }

    @Test func whenWarmForeground_andOnlyUnfinishedSessions_thenSendsNothing() async throws {
        let now = Date(timeIntervalSince1970: 30_000)
        let (sut, persistence, sendService) = makeResenderSUT(dateNow: { now })

        let unfinishedPairs = ["unfinished-1", "unfinished-2"].enumerated().map { index, uuid -> (PersistentCoverageSession, PersistentFence) in
            let session = makePersistentSession(
                testUUID: uuid,
                startedAt: now.addingTimeInterval(Double(-20 - index)).microsecondsTimestamp
            )
            let fence = makePersistentFence(
                testUUID: uuid,
                timestamp: now.addingTimeInterval(-10 + Double(index)).microsecondsTimestamp
            )
            return (session, fence)
        }

        try persistence.saveMocked(
            coverageSessions: unfinishedPairs.map(\.0),
            fences: unfinishedPairs.map(\.1)
        )

        try await sut.resendPersistentAreas(isLaunched: false)

        #expect(sendService.capturedSendCalls.isEmpty)
    }

    @Test func whenCleanup_thenDeletesOldFences_andOldSessions_andOrphanSessions_butNotForUnfinishedCurrent() async throws {
        let maxAge: TimeInterval = 60 * 60 * 24
        let now = Date(timeIntervalSince1970: 40_000)
        let (sut, persistence, _) = makeResenderSUT(maxResendAge: maxAge, dateNow: { now })

        let oldTimestamp = now.addingTimeInterval(-(maxAge + 60)).microsecondsTimestamp
        let recentTimestamp = now.addingTimeInterval(-maxAge / 2).microsecondsTimestamp

        let oldUUID = "old-test"
        let orphanUUID = "orphan"
        let unfinishedUUID = "unfinished"

        let sessions = [
            makePersistentSession(testUUID: oldUUID, startedAt: oldTimestamp, finalizedAt: oldTimestamp + 1_000_000),
            makePersistentSession(testUUID: orphanUUID, startedAt: oldTimestamp, finalizedAt: oldTimestamp + 500_000),
            makePersistentSession(testUUID: unfinishedUUID, startedAt: recentTimestamp)
        ]
        let fences = [
            makePersistentFence(testUUID: oldUUID, timestamp: oldTimestamp),
            makePersistentFence(testUUID: unfinishedUUID, timestamp: recentTimestamp)
        ]

        try persistence.saveMocked(coverageSessions: sessions, fences: fences)

        try await sut.resendPersistentAreas(isLaunched: false)

        let fencesAfterWarm = try persistence.persistedFences()
        let sessionsAfterWarm = try persistence.persistentSessions()

        #expect(fencesAfterWarm.allSatisfy { $0.testUUID == unfinishedUUID })
        #expect(sessionsAfterWarm.map { $0.testUUID }.sorted() == [unfinishedUUID])

        try await sut.resendPersistentAreas(isLaunched: true)

        let fencesAfterCold = try persistence.persistedFences()
        let sessionsAfterCold = try persistence.persistentSessions()

        #expect(fencesAfterCold.allSatisfy { $0.testUUID == unfinishedUUID })
        #expect(sessionsAfterCold.map { $0.testUUID }.sorted() == [unfinishedUUID])
    }

    @Test func whenLegacyFencesWithoutSessionRecord_thenResendsInAnyMode() async throws {
        let now = Date(timeIntervalSince1970: 50_000)
        let legacyUUID = "legacy-test"
        let (sut, persistence, sendService) = makeResenderSUT(dateNow: { now })

        func seedLegacyFences() throws {
            try persistence.saveMocked(
                fences: [
                    makePersistentFence(testUUID: legacyUUID, timestamp: now.addingTimeInterval(-1_800).microsecondsTimestamp)
                ]
            )
        }

        try seedLegacyFences()
        try await sut.resendPersistentAreas(isLaunched: false)
        try expect(
            capturedSendCalls: sendService.capturedSendCalls,
            equals: [
                (
                    testUUID: legacyUUID,
                    fenceDates: [now.addingTimeInterval(-1_800)]
                )
            ]
        )

        try seedLegacyFences()
        try await sut.resendPersistentAreas(isLaunched: true)
        try expect(
            capturedSendCalls: sendService.capturedSendCalls,
            equals: [
                (
                    testUUID: legacyUUID,
                    fenceDates: [now.addingTimeInterval(-1_800)]
                ),
                (
                    testUUID: legacyUUID,
                    fenceDates: [now.addingTimeInterval(-1_800)]
                )
            ]
        )
    }
}

// MARK: - Test Helpers

@MainActor
private func makeResenderSUT(
    maxResendAge: TimeInterval = Date().timeIntervalSince1970 * 1000,
    dateNow: @escaping () -> Date = Date.init,
    sendResults: [Result<Void, Error>] = Array(repeating: .success(()), count: 10)
) -> (sut: PersistedFencesResender, persistence: ResenderPersistenceLayerSpy, sendServiceFactory: ResenderSendCoverageResultsServiceFactory) {
    let database = UserDatabase(useInMemoryStore: true)
    let persistence = ResenderPersistenceLayerSpy(modelContext: database.modelContext)
    let factory = NetworkCoverageFactory(database: database, maxResendAge: maxResendAge, dateNow: dateNow)
    let sendServiceFactory = ResenderSendCoverageResultsServiceFactory(sendResults: sendResults)

    let sut = factory.makeResender { testUUID, startDate in
        sendServiceFactory.createService(for: testUUID, startDate: startDate)
    }

    return (sut, persistence, sendServiceFactory)
}

private final class ResenderPersistenceLayerSpy {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveMocked(
        coverageSessions: [PersistentCoverageSession]? = nil,
        fences: [PersistentFence]? = nil
    ) throws {
        coverageSessions.map(insert)
        fences.map(insert)
        try save()
    }

    func insert(session: PersistentCoverageSession) {
        modelContext.insert(session)
    }

    func insert(fence: PersistentFence) {
        modelContext.insert(fence)
    }

    func insert(fences: [PersistentFence]) {
        fences.forEach { insert(fence: $0) }
    }

    func insert(sessions: [PersistentCoverageSession]) {
        sessions.forEach { insert(session: $0) }
    }

    func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    func persistedFences() throws -> [PersistentFence] {
        try modelContext.fetch(FetchDescriptor<PersistentFence>())
    }

    func persistentSessions() throws -> [PersistentCoverageSession] {
        try modelContext.fetch(FetchDescriptor<PersistentCoverageSession>())
    }
}

private func makePersistentSession(testUUID: String, startedAt: UInt64, finalizedAt: UInt64? = nil) -> PersistentCoverageSession {
    PersistentCoverageSession(testUUID: testUUID, startedAt: startedAt, finalizedAt: finalizedAt)
}

private func expect(
    capturedSendCalls: [ResenderSendCoverageResultsServiceFactory.SendCall],
    equals expected: [(testUUID: String, fenceDates: [Date])],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    #expect(capturedSendCalls.count == expected.count, sourceLocation: sourceLocation)

    for (actual, expectedCall) in zip(capturedSendCalls, expected) {
        #expect(actual.testUUID == expectedCall.testUUID, sourceLocation: sourceLocation)
        let actualDates = actual.fences.map(\.dateEntered).sorted()
        #expect(actualDates == expectedCall.fenceDates.sorted(), sourceLocation: sourceLocation)
    }
}

private final class ResenderSendCoverageResultsServiceFactory {
    struct SendCall: Equatable {
        let testUUID: String
        let fences: [Fence]
        let startDate: Date?
    }

    private(set) var capturedSendCalls: [SendCall] = []
    private var sendResults: [Result<Void, Error>]

    init(sendResults: [Result<Void, Error>] = [.success(())]) {
        self.sendResults = sendResults
    }

    func createService(for testUUID: String, startDate: Date?) -> SendCoverageResultsServiceWrapper {
        let result = sendResults.isEmpty ? .success(()) : sendResults.removeFirst()
        let service = SendCoverageResultsServiceSpy(sendResult: result)

        return SendCoverageResultsServiceWrapper(
            originalService: service,
            onSend: { [weak self] fences in
                self?.capturedSendCalls.append(SendCall(testUUID: testUUID, fences: fences, startDate: startDate))
            }
        )
    }
}
