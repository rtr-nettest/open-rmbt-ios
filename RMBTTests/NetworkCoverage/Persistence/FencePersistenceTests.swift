//
//  FencePersistenceTests.swift
//  RMBTTest
//
//  Created by Jiri Urbasek on 30.05.2025.
//  Copyright 2025 appscape gmbh. All rights reserved.
//

import Testing
@testable import RMBT
import SwiftData
import CoreLocation

@MainActor
struct FencePersistenceTests {
    @Suite("Given Has No Previously Persisted Data")
    struct GivenHasNoPreviouslyPersitedData {
        @Test func whenPersistedFences_thenTheyArePresentInPersistenceLayer() async throws {
            let sessionID = "session-1"
            let (sut, persistence, _) = makeSUT(testUUID: "dummy")

            try await inSession(sessionID: sessionID, with: sut) {
                try await sut.persist(fence: makeFence(lat: 1, lon: 2, date: Date(timeIntervalSinceReferenceDate: 1), technology: "LTE"))
                try await sut.persist(fence: makeFence(lat: 3, lon: 4, date: Date(timeIntervalSinceReferenceDate: 2), technology: "3G"))
            }

            let persistedFences = try persistence.allPersistedFences()
            try #require(persistedFences.count == 2)

            #expect(persistedFences[0].latitude == 1)
            #expect(persistedFences[0].longitude == 2)
            #expect(persistedFences[0].timestamp == Date(timeIntervalSinceReferenceDate: 1).microsecondsTimestamp)
            #expect(persistedFences[0].technology == "LTE")

            #expect(persistedFences[1].latitude == 3)
            #expect(persistedFences[1].longitude == 4)
            #expect(persistedFences[1].timestamp == Date(timeIntervalSinceReferenceDate: 2).microsecondsTimestamp)
            #expect(persistedFences[1].technology == "3G")

            let persistedSessions = try persistence.persistedSession(forSessionID: sessionID)
            #expect(persistedSessions.count == 1)
            #expect(persistedSessions.first?.testUUID == sessionID)
        }

        @Test func whenSendingFencesSucceds_thenTheyAreRemovedFromPersistenceLayer() async throws {
            let sessionID = "session-1"
            let (sut, persistence, sendService) = makeSUT(testUUID: sessionID, sendResults: [.success(())])
            let fences = [
                makeFence(lat: 1, lon: 2, technology: "LTE"),
                makeFence(lat: 3, lon: 4, technology: "3G")
            ]

            try await sut.persistAndSend(fences: fences, sessionID: sessionID)

            #expect(try persistence.allPersistedFences().count == 0)
            #expect(try persistence.allPersistedSessions().count == 0)
            #expect(sendService.capturedSendCalls.count == 1)
        }

        @Test func whenSendingFenceFails_thenTheyAreKeptInPersistenceLayer() async throws {
            let sessionID = "session-1"
            let (sut, persistence, sendService) = makeSUT(testUUID: sessionID, sendResults: [.failure(TestError.sendFailed)])
            let fences = [
                makeFence(lat: 1, lon: 2, date: Date(timeIntervalSinceReferenceDate: 1), technology: "LTE"),
                makeFence(lat: 3, lon: 4, date: Date(timeIntervalSinceReferenceDate: 2), technology: "3G")
            ]

            await #expect(throws: TestError.sendFailed) {
                try await sut.persistAndSend(fences: fences, sessionID: sessionID)
            }

            let persistedFences = try persistence.persistedFences(forSessionID: sessionID)
            #expect(sendService.capturedSendCalls.count == 1)
            #expect(persistedFences.count == 2)

            let persistedSessions = try persistence.persistedSession(forSessionID: sessionID)
            #expect(persistedSessions.count == 1)
        }
    }

    @Suite("Given Has Previously Persisted Data")
    struct GivenHasPreviouslyPersitedData {
        @Test func whenSendingFencesSucceeds_thenAttemptsToSendAndRemovesAlsoPreviouslyPersistedFences() async throws {
            let testUUID = "test-uuid"
            let prevTestUUID = "prev-test-uuid"
            let prevSession = PersistentCoverageSession(testUUID: prevTestUUID, startedAt: 10, anchorAt: 10, finalizedAt: 20)
            let prevPersistedFences = [
                makePersistentFence(timestamp: 10),
                makePersistentFence(timestamp: 11)
            ]
            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .success(())],
                previouslyPersistedSessions: [(prevSession, prevPersistedFences)]
            )
            let newFences = [makeFence(), makeFence(), makeFence()]

            try await sut.persistAndSend(fences: newFences, sessionID: testUUID)

            let remainingFences = try persistence.allPersistedFences()
            #expect(remainingFences.count == 0)
            #expect(sendService.capturedSendCalls.count == 2)
            #expect(sendService.capturedSendCalls.map(\.testUUID) == [testUUID, prevTestUUID])
            #expect(sendService.capturedSendCalls.map(\.fences.count) == [newFences.count, prevPersistedFences.count])

            let remainingSessions = try persistence.allPersistedSessions()
            #expect(remainingSessions.count == 0)
        }

        @Test func whenAttemptToSendPreviouslyPersistedFencesFails_thenKeepsThoseFencesPersisted() async throws {
            let testUUID = "test-uuid"
            let prevTestUUID = "prev-test-uuid"
            let prevPrevTestUUID = "prev-prev-test-uuid" // will fail to send

            let prevSession = PersistentCoverageSession(testUUID: prevTestUUID, startedAt: 100, anchorAt: 100, finalizedAt: 120)
            let prevPersistedFences = [
                makePersistentFence(timestamp: 100),
                makePersistentFence(timestamp: 110),
            ]

            let prevPrevSession = PersistentCoverageSession(testUUID: prevPrevTestUUID, startedAt: 10, anchorAt: 10, finalizedAt: 20)
            let prevPrevPersistedFences = [
                makePersistentFence(timestamp: 10),
                makePersistentFence(timestamp: 12),
                makePersistentFence(timestamp: 14),
                makePersistentFence(timestamp: 16)
            ]
            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .failure(TestError.sendFailed), .success(())],
                previouslyPersistedSessions: [(prevSession, prevPersistedFences), (prevPrevSession, prevPrevPersistedFences)]
            )
            let newFences = [makeFence(), makeFence(), makeFence()]

            try await sut.persistAndSend(fences: newFences, sessionID: testUUID)

            // Assert DB state
            #expect(try persistence.persistedFences(forSessionID: prevPrevTestUUID).count == prevPrevPersistedFences.count)
            #expect(try persistence.persistedFences(forSessionID: prevTestUUID).count == 0)

            let remainingSessions = try persistence.allPersistedSessions()
            #expect(remainingSessions.count == 1)
            #expect(remainingSessions.first?.testUUID == prevPrevTestUUID)

            // Assert send spy state
            #expect(sendService.capturedSendCalls.count == 3)
            #expect(sendService.capturedSendCalls.map(\.testUUID) == [testUUID, prevPrevTestUUID, prevTestUUID])
            #expect(sendService.capturedSendCalls.map(\.fences.count) == [newFences.count, prevPrevPersistedFences.count, prevPersistedFences.count])
        }

        @Test func whenSendingPreviouslyPersistedFences_thenMappsThemProperlyToDomainObjects() async throws {
            let persistedTestUUID = "persisted-uuid"
            let newTestUUID = "main-uuid"
            let expectedLat = 50.123456
            let expectedLon = 14.654321
            let expectedPing = 120
            let expectedTimestamp: UInt64 = 1640995200000000 // 2022-01-01 00:00:00 in microseconds
            let expectedTechnology = "5G"

            let persistentSession = PersistentCoverageSession(testUUID: persistedTestUUID, startedAt: expectedTimestamp, anchorAt: expectedTimestamp, finalizedAt: expectedTimestamp + 1000)
            let persistentFence = PersistentFence(
                timestamp: expectedTimestamp,
                latitude: expectedLat,
                longitude: expectedLon,
                avgPingMilliseconds: expectedPing,
                technology: expectedTechnology,
                radiusMeters: 20
            )
            let (sut, _, sendService) = makeSUT(
                testUUID: newTestUUID,
                sendResults: [.success(()), .success(())],
                previouslyPersistedSessions: [(persistentSession, [persistentFence])]
            )

            try await sut.persistAndSend(fences: [makeFence()], sessionID: newTestUUID)

            let mappedFence = try #require(sendService.capturedSendCalls.last?.fences.first)

            #expect(mappedFence.startingLocation.coordinate.latitude == expectedLat)
            #expect(mappedFence.startingLocation.coordinate.longitude == expectedLon)
            #expect(mappedFence.dateEntered == expectedTimestamp.dateFromMicroseconds)
            #expect(mappedFence.significantTechnology == expectedTechnology)
            #expect(mappedFence.averagePing == expectedPing)
        }
    }

    @Suite("Given Has Persistent Fences Older Than Max Resend Age")
    struct GivenHasPersistentFencesOlderThenMaxResendAge {
        @Test func whenPersistedFencesAreOlderThanMaxAge_thenTheyAreDeletedWithoutSending() async throws {
            let testUUID = "current-test"
            let oldTestUUID = "old-test"
            let maxAgeSeconds: TimeInterval = 3600 // 1 hour
            let currentTime = Date()

            // Create old fences (older than maxAge)
            let oldTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds - 1).microsecondsTimestamp
            let oldSession = PersistentCoverageSession(testUUID: oldTestUUID, startedAt: oldTimestamp, anchorAt: oldTimestamp, finalizedAt: oldTimestamp + 2000)
            let oldFences = [
                makePersistentFence(testUUID: oldTestUUID, timestamp: oldTimestamp),
                makePersistentFence(testUUID: oldTestUUID, timestamp: oldTimestamp + 1000)
            ]

            // Create recent fences (within maxAge)
            let recentTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds + 600).microsecondsTimestamp
            let recentSession = PersistentCoverageSession(testUUID: "recent-test", startedAt: recentTimestamp, anchorAt: recentTimestamp, finalizedAt: recentTimestamp + 1000)
            let recentFences = [
                makePersistentFence(testUUID: "recent-test", timestamp: recentTimestamp)
            ]

            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .success(())],
                previouslyPersistedSessions: [(oldSession, oldFences), (recentSession, recentFences)],
                maxResendAge: maxAgeSeconds
            )

            try await sut.persistAndSend(fences: [makeFence()], sessionID: testUUID)

            #expect(try persistence.allPersistedFences().count == 0)
            #expect(try persistence.allPersistedSessions().count == 0)

            #expect(sendService.capturedSendCalls.count == 2) // newFences + recentFences (old fences not sent)
            #expect(sendService.capturedSendCalls.map(\.testUUID).contains(oldTestUUID) == false)
        }

        @Test func whenPersistedFencesAreWithinMaxAge_thenTheyAreKeptAndSent() async throws {
            let testUUID = "current-test"
            let recentTestUUID = "recent-test"
            let maxAgeSeconds: TimeInterval = 3600 // 1 hour
            let currentTime = Date()

            // Create recent fences (within maxAge)
            let recentTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds + 600).microsecondsTimestamp
            let recentSession = PersistentCoverageSession(testUUID: recentTestUUID, startedAt: recentTimestamp, anchorAt: recentTimestamp, finalizedAt: recentTimestamp + 2000)
            let recentFences = [
                makePersistentFence(timestamp: recentTimestamp),
                makePersistentFence(timestamp: recentTimestamp + 1000)
            ]

            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .success(())],
                previouslyPersistedSessions: [(recentSession, recentFences)],
                maxResendAge: maxAgeSeconds
            )

            try await sut.persistAndSend(fences: [makeFence()], sessionID: testUUID)

            #expect(try persistence.allPersistedFences().count == 0) // All should be sent and removed
            #expect(try persistence.allPersistedSessions().count == 0) // All should be sent and removed

            #expect(sendService.capturedSendCalls.count == 2) // newFences + recentFences
            #expect(sendService.capturedSendCalls.map(\.testUUID) == [testUUID, recentTestUUID])
            #expect(sendService.capturedSendCalls.map(\.fences.count) == [1, 2])
        }

        @Test func whenSendingRecentFencesFailsButOldFencesExist_thenOnlyOldFencesAreDeleted() async throws {
            let testUUID = "current-test"
            let recentTestUUID = "recent-test"
            let oldTestUUID = "old-test"
            let maxAgeSeconds: TimeInterval = 3600 // 1 hour
            let currentTime = Date()

            // Create old fences (older than maxAge)
            let oldTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds - 1).microsecondsTimestamp
            let oldSession = PersistentCoverageSession(testUUID: oldTestUUID, startedAt: oldTimestamp, anchorAt: oldTimestamp, finalizedAt: oldTimestamp + 1000)
            let oldFences = [makePersistentFence(timestamp: oldTimestamp)]

            // Create recent fences (within maxAge)
            let recentTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds + 600).microsecondsTimestamp
            let recentSession = PersistentCoverageSession(testUUID: recentTestUUID, startedAt: recentTimestamp, anchorAt: recentTimestamp, finalizedAt: recentTimestamp + 1000)
            let recentFences = [makePersistentFence(timestamp: recentTimestamp)]

            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .failure(TestError.sendFailed)], // recent fences fail to send
                previouslyPersistedSessions: [(oldSession, oldFences), (recentSession, recentFences)],
                maxResendAge: maxAgeSeconds
            )

            try await sut.persistAndSend(fences: [makeFence()], sessionID: testUUID)

            let remainingFences = try persistence.allPersistedFences()
            let remainingSessions = try persistence.allPersistedSessions()
            // Only recent fences should remain (old fences deleted, recent fences kept due to send failure)
            #expect(remainingFences.count == 1)
            #expect(remainingSessions.count == 1)
            #expect(remainingSessions.first?.testUUID == recentTestUUID)

            #expect(sendService.capturedSendCalls.count == 2) // current + attempt to send recent
            #expect(sendService.capturedSendCalls.map(\.testUUID).contains(oldTestUUID) == false)
        }
    }

    // MARK: - New Session-Based Persistence Tests

    @Suite("Session-Based Persistence")
    struct SessionBasedPersistence {
        @Test func whenDeletingNilUUIDSession_thenOrphanedFencesAreDeleted() async throws {
            let baseTime = makeBaseTime()
            let (sut, persistence, _) = makeSUT(testUUID: nil)

            try await sut.beginSession(startedAt: baseTime)
            try await sut.persist(fence: makeFence(date: baseTime))
            try await sut.finalizeCurrentSession(at: baseTime.addingTimeInterval(1))
            try await sut.deleteFinalizedNilUUIDSessions()

            let sessions = try persistence.allPersistedSessions()
            #expect(sessions.isEmpty)

            let fences = try persistence.allPersistedFences()
            #expect(fences.isEmpty)
        }

        @Test func whenStoppedWithoutUUID_thenSessionDeleted() async throws {
            let startTime = Date(timeIntervalSinceReferenceDate: 0)
            let (sut, persistence, _) = makeSUT(testUUID: nil)

            try await sut.beginSession(startedAt: startTime)
            try await sut.finalizeCurrentSession(at: startTime.addingTimeInterval(10))
            try await sut.deleteFinalizedNilUUIDSessions()

            let sessions = try persistence.allPersistedSessions()
            #expect(sessions.isEmpty)
        }

        @Test func whenWarmSubmit_thenReturnsOnlyFinalizedSessions() async throws {
            let baseTime = Date(timeIntervalSinceReferenceDate: 100)
            let (sut, persistence, _) = makeSUT(testUUID: nil)

            // Create unfinished session (should NOT be included in warm submit)
            try await sut.beginSession(startedAt: baseTime)
            try await sut.assignTestUUIDAndAnchor("unfinished", anchorNow: baseTime)

            // Create finalized session (should be included in warm submit)
            try await sut.beginSession(startedAt: baseTime.addingTimeInterval(20))
            try await sut.assignTestUUIDAndAnchor("finalized", anchorNow: baseTime.addingTimeInterval(20))
            try await sut.finalizeCurrentSession(at: baseTime.addingTimeInterval(30))

            // Verify database state: both sessions exist
            let allSessions = try persistence.allPersistedSessions()
            #expect(allSessions.count == 2)

            // Verify warm submit behavior: only finalized sessions with testUUID
            let finalizedSessions = allSessions.filter { $0.finalizedAt != nil && $0.testUUID != nil }
            #expect(finalizedSessions.count == 1)
            #expect(finalizedSessions.first?.testUUID == "finalized")
        }

        @Test func whenColdSubmit_thenReturnsAllSessionsWithUUID_includingUnfinished() async throws {
            let baseTime = Date(timeIntervalSinceReferenceDate: 500)
            let (sut, persistence, _) = makeSUT(testUUID: nil)

            // Create older finalized session
            try await sut.beginSession(startedAt: baseTime.addingTimeInterval(-300))
            try await sut.assignTestUUIDAndAnchor("A", anchorNow: baseTime.addingTimeInterval(-300))
            try await sut.finalizeCurrentSession(at: baseTime.addingTimeInterval(-200))

            // Create newer finalized session
            try await sut.beginSession(startedAt: baseTime.addingTimeInterval(-100))
            try await sut.assignTestUUIDAndAnchor("B", anchorNow: baseTime.addingTimeInterval(-100))
            try await sut.finalizeCurrentSession(at: baseTime.addingTimeInterval(-50))

            // Create unfinished session (should be included in cold submit)
            try await sut.beginSession(startedAt: baseTime)
            try await sut.assignTestUUIDAndAnchor("C-unfinished", anchorNow: baseTime)

            // Verify database state: all sessions with testUUID
            let allSessionsWithUUID = try persistence.allPersistedSessions()
                .filter { $0.testUUID != nil }
                .sorted { ($0.finalizedAt ?? 0) > ($1.finalizedAt ?? 0) }

            try #require(allSessionsWithUUID.count == 3)

            // Cold submit should return ALL sessions with UUID, sorted by finalizedAt (nil last)
            // Note: Sessions with nil finalizedAt will sort to the end
            let finalizedSessions = allSessionsWithUUID.filter { $0.finalizedAt != nil }
            #expect(finalizedSessions.count == 2)
            #expect(finalizedSessions.first?.testUUID == "B")
            #expect(finalizedSessions.last?.testUUID == "A")

            let unfinalizedSessions = allSessionsWithUUID.filter { $0.finalizedAt == nil }
            #expect(unfinalizedSessions.count == 1)
            #expect(unfinalizedSessions.first?.testUUID == "C-unfinished")
        }
    }
}

// MARK: - Test Helpers

private struct SendCall {
    let testUUID: String
    let fences: [Fence]
}

private func makeSUT(
    testUUID: String?,
    sendResults: [Result<Void, Error>] = [.success(())],
    previouslyPersistedSessions: [(PersistentCoverageSession, [PersistentFence])] = [],
    maxResendAge: TimeInterval = Date().timeIntervalSince1970 * 1000,
    dateNow: @escaping () -> Date = Date.init
) -> (sut: SUT, persistence: PersistenceLayerSpy, sendService: SendCoverageResultsServiceFactory) {
    let database = UserDatabase(useInMemoryStore: true)
    let persistence = PersistenceLayerSpy(modelContext: database.modelContext)
    let sendServiceFactory = SendCoverageResultsServiceFactory(sendResults: sendResults)

    // Insert prefilled sessions with their fences into modelContext
    for (session, fences) in previouslyPersistedSessions {
        session.fences = fences
        database.modelContext.insert(session)
    }
    try! database.modelContext.save()

    let services = NetworkCoverageFactory(
        database: database,
        maxResendAge: maxResendAge
    ).services(testUUID: testUUID, startDate: Date(timeIntervalSinceReferenceDate: 0), dateNow: dateNow, sendResultsServiceMaker: { testUUID, _ in
        sendServiceFactory.createService(for: testUUID)
    })
    let sut = SUT(fencePersistenceService: services.0, sendResultsServices: services.1)

    return (sut, persistence, sendServiceFactory)
}

final class SUT {
    private let fencePersistenceService: any FencePersistenceService
    private let sendResultsServices: any SendCoverageResultsService

    init(fencePersistenceService: some FencePersistenceService, sendResultsServices: some SendCoverageResultsService) {
        self.fencePersistenceService = fencePersistenceService
        self.sendResultsServices = sendResultsServices
    }

    func startSession(on date: Date) async throws {
        try await fencePersistenceService.sessionStarted(at: date)
    }

    func recordSessionID(id: String, on date: Date) async throws {
        try await fencePersistenceService.assignTestUUIDAndAnchor(id, anchorNow: date)
    }

    func stopSession(on date: Date) async throws {
        try await fencePersistenceService.sessionFinalized(at: date)
    }

    func persist(fence: Fence) async throws {
        try await fencePersistenceService.save(fence)
    }

    func persist(fences: [Fence]) async throws {
        for fence in fences {
            try await persist(fence: fence)
        }
    }

    func send(fences: [Fence]) async throws {
        try await sendResultsServices.send(fences: fences)
    }

    /// Helper to persist fences within a single session and then send them
    func persistAndSend(fences: [Fence], sessionID: String) async throws {
        try await inSession(sessionID: sessionID, with: self) {
            try await self.persist(fences: fences)
        }
        try await self.send(fences: fences)
    }

    // MARK: - Session-Based Helpers

    /// Begins a new session. Equivalent to calling sessionStarted.
    func beginSession(startedAt date: Date) async throws {
        try await fencePersistenceService.sessionStarted(at: date)
    }

    /// Assigns test UUID and anchor to the current session
    func assignTestUUIDAndAnchor(_ testUUID: String, anchorNow: Date) async throws {
        try await fencePersistenceService.assignTestUUIDAndAnchor(testUUID, anchorNow: anchorNow)
    }

    /// Finalizes the current session
    func finalizeCurrentSession(at date: Date) async throws {
        try await fencePersistenceService.sessionFinalized(at: date)
    }

    /// Deletes finalized sessions that have nil UUID
    func deleteFinalizedNilUUIDSessions() async throws {
        try await fencePersistenceService.deleteFinalizedNilUUIDSessions()
    }
}

private func inSession(
    started: Date = Date(timeIntervalSinceReferenceDate: 1),
    finalized: Date = Date(timeIntervalSinceReferenceDate: 2),
    sessionID: String = UUID().uuidString,
    with sut: SUT,
    action: () async throws -> Void
) async throws {
    try await sut.startSession(on: started)
    try await sut.recordSessionID(id: sessionID, on: started)

    try await action()

    try await sut.stopSession(on: finalized)
}

private final class PersistenceLayerSpy {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func allPersistedFences() throws -> [PersistentFence] {
        try modelContext.fetch(FetchDescriptor<PersistentFence>())
    }

    func persistedFences(forSessionID testUUID: String) throws -> [PersistentFence] {
        let sessions = try persistedSession(forSessionID: testUUID)
        return sessions
            .map(\.fences)
            .flatMap { $0 }
    }

    func allPersistedSessions() throws -> [PersistentCoverageSession] {
        try modelContext.fetch(FetchDescriptor<PersistentCoverageSession>())
    }

    func persistedSession(forSessionID testUUID: String) throws -> [PersistentCoverageSession] {
        let descriptor = FetchDescriptor<PersistentCoverageSession>(
            predicate: #Predicate { $0.testUUID ==  testUUID}
        )
        return try modelContext.fetch(descriptor)
    }
}

private func makeFence(
    lat: CLLocationDegrees = Double.random(in: -90...90),
    lon: CLLocationDegrees = Double.random(in: -180...180),
    date: Date = Date(timeIntervalSinceReferenceDate: TimeInterval.random(in: 0...10000)),
    technology: String? = ["3G", "4G", "5G", "LTE"].randomElement(),
    averagePing: Int? = nil
) -> Fence {
    var fence = Fence(
        startingLocation: CLLocation(latitude: lat, longitude: lon),
        dateEntered: date,
        technology: technology,
        radiusMeters: Double.random(in: 1...100)
    )

    if let ping = averagePing {
        fence.append(ping: PingResult(result: .interval(.milliseconds(ping)), timestamp: date))
    }

    return fence
}

func makePersistentFence(testUUID: String = "TODO: Delete", timestamp: UInt64) -> PersistentFence {
    .init(
        timestamp: timestamp,
        latitude: Double.random(in: -90...90),
        longitude: Double.random(in: -180...180),
        avgPingMilliseconds: Int.random(in: 10...500),
        technology: ["3G", "4G", "5G", "LTE"].randomElement(),
        radiusMeters: 20
    )
}

private func makeBaseTime() -> Date {
    Date()
}

private enum TestError: Error {
    case sendFailed
}

extension Date {
    var microsecondsTimestamp: UInt64 {
        let microseconds = timeIntervalSince1970 * 1_000_000
        guard microseconds > 0 else { return 0 }
        return UInt64(microseconds)
    }
}

extension UInt64 {
    var dateFromMicroseconds: Date {
        Date(timeIntervalSince1970: Double(self) / 1_000_000)
    }
}

private final class SendCoverageResultsServiceFactory {
    private(set) var capturedSendCalls: [SendCall] = []
    private var sendResults: [Result<Void, Error>]

    init(sendResults: [Result<Void, Error>] = [.success(())]) {
        self.sendResults = sendResults
    }

    func createService(for testUUID: String) -> SendCoverageResultsServiceWrapper {
        let service = SendCoverageResultsServiceSpy(sendResult: sendResults.removeFirst())

        return SendCoverageResultsServiceWrapper(
            originalService: service,
            onSend: { [weak self] fences in
                self?.capturedSendCalls.append(SendCall(testUUID: testUUID, fences: fences))
            }
        )
    }
}

final class SendCoverageResultsServiceWrapper: SendCoverageResultsService {
    private let originalService: SendCoverageResultsServiceSpy
    private let onSend: ([Fence]) -> Void

    init(originalService: SendCoverageResultsServiceSpy, onSend: @escaping ([Fence]) -> Void) {
        self.originalService = originalService
        self.onSend = onSend
    }

    func send(fences: [Fence]) async throws {
        onSend(fences)
        try await originalService.send(fences: fences)
    }
}

