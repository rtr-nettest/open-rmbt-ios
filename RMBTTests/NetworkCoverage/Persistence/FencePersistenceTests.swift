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

struct FencePersistenceTests {
    struct GivenHasNoPreviouslyPersitedData {
        @Test func whenPersistedFences_thenTheyArePresentInPersistenceLayer() async throws {
            let (sut, persistence, _) = makeSUT(testUUID: "dummy")

            try sut.persist(fence: makeFence(lat: 1, lon: 2, date: Date(timeIntervalSinceReferenceDate: 1), technology: "LTE"))
            try sut.persist(fence: makeFence(lat: 3, lon: 4, date: Date(timeIntervalSinceReferenceDate: 2), technology: "3G"))

            let persistedFences = try #require(try persistence.persistedFences())
            try #require(persistedFences.count == 2)

            #expect(persistedFences[0].testUUID == "dummy")
            #expect(persistedFences[0].latitude == 1)
            #expect(persistedFences[0].longitude == 2)
            #expect(persistedFences[0].timestamp == Date(timeIntervalSinceReferenceDate: 1).microsecondsTimestamp)
            #expect(persistedFences[0].technology == "LTE")

            #expect(persistedFences[1].testUUID == "dummy")
            #expect(persistedFences[1].latitude == 3)
            #expect(persistedFences[1].longitude == 4)
            #expect(persistedFences[1].timestamp == Date(timeIntervalSinceReferenceDate: 2).microsecondsTimestamp)
            #expect(persistedFences[1].technology == "3G")
        }

        @Test func whenSendingFencesSucceds_thenTheyAreRemovedFromPersistenceLayer() async throws {
            let (sut, persistence, sendService) = makeSUT(testUUID: "dummy", sendResults: [.success(())])
            let fences = [
                makeFence(lat: 1, lon: 2, technology: "LTE"),
                makeFence(lat: 3, lon: 4, technology: "3G")
            ]
            try await sut.persistAndSend(fences: fences)

            let persistedFences = try persistence.persistedFences()
            #expect(persistedFences.count == 0)
            #expect(sendService.capturedSendCalls.count == 1)
        }

        @Test func whenSendingFenceFails_thenTheyAreKeptInPersistenceLayer() async throws {
            let (sut, persistence, sendService) = makeSUT(testUUID: "dummy", sendResults: [.failure(TestError.sendFailed)])
            let fences = [
                makeFence(lat: 1, lon: 2, date: Date(timeIntervalSinceReferenceDate: 1), technology: "LTE"),
                makeFence(lat: 3, lon: 4, date: Date(timeIntervalSinceReferenceDate: 2), technology: "3G")
            ]
            await #expect(throws: TestError.sendFailed) {
                try await sut.persistAndSend(fences: fences)
            }

            let persistedFences = try persistence.persistedFences()
            #expect(sendService.capturedSendCalls.count == 1)
            #expect(persistedFences.count == 2)
        }
    }

    struct GivenHasPreviouslyPersitedData {
        @Test func whenSendingFencesSucceeds_thenAttemptsToSendAndRemovesAlsoPreviouslyPersistedFences() async throws {
            let testUUID = "test-uuid"
            let prevTestUUID = "prev-test-uuid"
            let prevPersistedFences = [
                makePersistentFence(testUUID: prevTestUUID, timestamp: 10),
                makePersistentFence(testUUID: prevTestUUID, timestamp: 11)
            ]
            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .success(())],
                previouslyPersistedFences: prevPersistedFences
            )

            try await sut.persistAndSend(fences: [makeFence(), makeFence(), makeFence()])

            let remainingFences = try persistence.persistedFences()
            #expect(remainingFences.count == 0)
            #expect(sendService.capturedSendCalls.count == 2)
            #expect(sendService.capturedSendCalls.map(\.testUUID) == [testUUID, prevTestUUID])
            #expect(sendService.capturedSendCalls.map(\.fences.count) == [3, prevPersistedFences.count])
        }

        @Test func whenAttemptToSendPreviouslyPersistedFencesFails_thenKeepsThoseFencesPersisted() async throws {
            let testUUID = "test-uuid"
            let prevTestUUID = "prev-test-uuid"
            let prevPrevTestUUID = "prev-prev-test-uuid"
            let prevPersistedFences = [
                makePersistentFence(testUUID: prevTestUUID, timestamp: 100),
                makePersistentFence(testUUID: prevTestUUID, timestamp: 110),
                makePersistentFence(testUUID: prevPrevTestUUID, timestamp: 10),
                makePersistentFence(testUUID: prevPrevTestUUID, timestamp: 12),
                makePersistentFence(testUUID: prevPrevTestUUID, timestamp: 14),
                makePersistentFence(testUUID: prevPrevTestUUID, timestamp: 16)
            ]
            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .failure(TestError.sendFailed), .success(())],
                previouslyPersistedFences: prevPersistedFences
            )

            try await sut.persistAndSend(fences: [makeFence(), makeFence(), makeFence()])

            let remainingFences = try persistence.persistedFences()
            #expect(remainingFences.count == 2)
            #expect(remainingFences.allSatisfy { $0.testUUID == prevTestUUID })

            #expect(sendService.capturedSendCalls.count == 3)
            #expect(sendService.capturedSendCalls.map(\.testUUID) == [testUUID, prevTestUUID, prevPrevTestUUID])
            #expect(sendService.capturedSendCalls.map(\.fences.count) == [3, 2, 4])
        }

        @Test func whenSendingPreviouslyPersistedFences_thenMappsThemProperlyToDomainObjects() async throws {
            let testUUID = "persisted-uuid"
            let expectedLat = 50.123456
            let expectedLon = 14.654321
            let expectedPing = 120
            let expectedTimestamp: UInt64 = 1640995200000000 // 2022-01-01 00:00:00 in microseconds
            let expectedTechnology = "5G"

            let persistentFence = PersistentFence(
                testUUID: testUUID,
                timestamp: expectedTimestamp,
                latitude: expectedLat,
                longitude: expectedLon,
                avgPingMilliseconds: expectedPing,
                technology: expectedTechnology,
                radiusMeters: 20
            )

            let (sut, _, sendService) = makeSUT(
                testUUID: "main-uuid",
                sendResults: [.success(()), .success(())],
                previouslyPersistedFences: [persistentFence]
            )

            try await sut.persistAndSend(fences: [makeFence()])

            let mappedFence = try #require(sendService.capturedSendCalls.last?.fences.first)

            #expect(mappedFence.startingLocation.coordinate.latitude == expectedLat)
            #expect(mappedFence.startingLocation.coordinate.longitude == expectedLon)
            #expect(mappedFence.dateEntered == expectedTimestamp.dateFromMicroseconds)
            #expect(mappedFence.technologies.first == expectedTechnology)
            #expect(mappedFence.averagePing == expectedPing)
        }
    }

    struct GivenHasPersistentFencesOlderThenMaxResendAge {
        @Test func whenPersistedFencesAreOlderThanMaxAge_thenTheyAreDeletedWithoutSending() async throws {
            let testUUID = "current-test"
            let oldTestUUID = "old-test"
            let maxAgeSeconds: TimeInterval = 3600 // 1 hour
            let currentTime = Date()

            // Create old fences (older than maxAge)
            let oldTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds - 1).microsecondsTimestamp
            let oldFences = [
                makePersistentFence(testUUID: oldTestUUID, timestamp: oldTimestamp),
                makePersistentFence(testUUID: oldTestUUID, timestamp: oldTimestamp + 1000)
            ]

            // Create recent fences (within maxAge)
            let recentTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds + 600).microsecondsTimestamp
            let recentFences = [
                makePersistentFence(testUUID: "recent-test", timestamp: recentTimestamp)
            ]

            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .success(())],
                previouslyPersistedFences: oldFences + recentFences,
                maxResendAge: maxAgeSeconds
            )

            try await sut.persistAndSend(fences: [makeFence()])

            let remainingFences = try persistence.persistedFences()
            #expect(remainingFences.count == 0)
            #expect(sendService.capturedSendCalls.count == 2) // current + recent (old fences not sent)
            #expect(sendService.capturedSendCalls.map(\.testUUID).contains(oldTestUUID) == false)
        }

        @Test func whenPersistedFencesAreWithinMaxAge_thenTheyAreKeptAndSent() async throws {
            let testUUID = "current-test"
            let recentTestUUID = "recent-test"
            let maxAgeSeconds: TimeInterval = 3600 // 1 hour
            let currentTime = Date()

            // Create recent fences (within maxAge)
            let recentTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds + 600).microsecondsTimestamp
            let recentFences = [
                makePersistentFence(testUUID: recentTestUUID, timestamp: recentTimestamp),
                makePersistentFence(testUUID: recentTestUUID, timestamp: recentTimestamp + 1000)
            ]

            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .success(())],
                previouslyPersistedFences: recentFences,
                maxResendAge: maxAgeSeconds
            )

            try await sut.persistAndSend(fences: [makeFence()])

            let remainingFences = try persistence.persistedFences()
            #expect(remainingFences.count == 0) // All should be sent and removed
            #expect(sendService.capturedSendCalls.count == 2) // current + recent
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
            let oldFences = [makePersistentFence(testUUID: oldTestUUID, timestamp: oldTimestamp)]

            // Create recent fences (within maxAge)
            let recentTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds + 600).microsecondsTimestamp
            let recentFences = [makePersistentFence(testUUID: recentTestUUID, timestamp: recentTimestamp)]

            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .failure(TestError.sendFailed)], // recent fences fail to send
                previouslyPersistedFences: oldFences + recentFences,
                maxResendAge: maxAgeSeconds
            )

            try await sut.persistAndSend(fences: [makeFence()])

            let remainingFences = try persistence.persistedFences()
            // Only recent fences should remain (old fences deleted, recent fences kept due to send failure)
            #expect(remainingFences.count == 1)
            #expect(remainingFences.first?.testUUID == recentTestUUID)
            #expect(sendService.capturedSendCalls.count == 2) // current + attempt to send recent
            #expect(sendService.capturedSendCalls.map(\.testUUID).contains(oldTestUUID) == false)
        }
    }
}

private struct SendCall {
    let testUUID: String
    let fences: [Fence]
}

// MARK: - Test Helpers

private func makeInMemoryModelContext() -> ModelContext {
    let container = try! ModelContainer(
        for: PersistentFence.self,
        configurations: .init(for: PersistentFence.self, isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private func makeSUT(
    testUUID: String?,
    sendResults: [Result<Void, Error>] = [.success(())],
    previouslyPersistedFences: [PersistentFence] = [],
    maxResendAge: TimeInterval = Date().timeIntervalSince1970 * 1000,
    dateNow: @escaping () -> Date = Date.init
) -> (sut: SUT, persistence: PersistenceLayerSpy, sendService: SendCoverageResultsServiceFactory) {
    let database = UserDatabase(useInMemoryStore: true)
    let persistence = PersistenceLayerSpy(modelContext: database.modelContext)
    let sendServiceFactory = SendCoverageResultsServiceFactory(sendResults: sendResults)

    // Insert prefilled fences into modelContext
    for fence in previouslyPersistedFences {
        database.modelContext.insert(fence)
    }
    try! database.modelContext.save()

    let services = NetworkCoverageFactory(database: database, maxResendAge: maxResendAge).services(testUUID: testUUID, startDate: Date(timeIntervalSinceReferenceDate: 0), dateNow: dateNow, sendResultsServiceMaker: { testUUID, _ in
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

    func persist(fence: Fence) throws {
        try fencePersistenceService.save(fence)
    }

    func persistAndSend(fences: [Fence]) async throws {
        try fences.forEach {
            try persist(fence: $0)
        }
        try await sendResultsServices.send(fences: fences)
    }
}

private final class PersistenceLayerSpy {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func persistedFences() throws -> [PersistentFence] {
        try modelContext.fetch(FetchDescriptor<PersistentFence>())
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

private func makePersistentFence(testUUID: String, timestamp: UInt64) -> PersistentFence {
    PersistentFence(
        testUUID: testUUID,
        timestamp: timestamp,
        latitude: Double.random(in: -90...90),
        longitude: Double.random(in: -180...180),
        avgPingMilliseconds: Int.random(in: 10...500),
        technology: ["3G", "4G", "5G", "LTE"].randomElement(),
        radiusMeters: 20
    )
}

private enum TestError: Error {
    case sendFailed
}

private extension Date {
    var microsecondsTimestamp: UInt64 {
        UInt64(timeIntervalSince1970 * 1_000_000)
    }
}

private extension UInt64 {
    var dateFromMicroseconds: Date {
        Date(timeIntervalSince1970: Double(self) / 1_000_000)
    }
}

private final class SendCoverageResultsServiceSpyLocal: SendCoverageResultsService {
    private(set) var capturedSentFences: [[Fence]] = []
    private let sendResult: Result<Void, Error>

    init(sendResult: Result<Void, Error> = .success(())) {
        self.sendResult = sendResult
    }

    func send(fences: [Fence]) async throws {
        capturedSentFences.append(fences)
        switch sendResult {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

private final class SendCoverageResultsServiceFactory {
    private(set) var capturedSendCalls: [SendCall] = []
    private var sendResults: [Result<Void, Error>]

    init(sendResults: [Result<Void, Error>] = [.success(())]) {
        self.sendResults = sendResults
    }

    func createService(for testUUID: String) -> SendCoverageResultsServiceWrapper {
        let service = SendCoverageResultsServiceSpyLocal(sendResult: sendResults.removeFirst())

        return SendCoverageResultsServiceWrapper(
            testUUID: testUUID,
            originalService: service,
            onSend: { [weak self] fences in
                self?.capturedSendCalls.append(SendCall(testUUID: testUUID, fences: fences))
            }
        )
    }
}

private final class SendCoverageResultsServiceWrapper: SendCoverageResultsService {
    private let testUUID: String
    private let originalService: SendCoverageResultsServiceSpyLocal
    private let onSend: ([Fence]) -> Void

    init(testUUID: String, originalService: SendCoverageResultsServiceSpyLocal, onSend: @escaping ([Fence]) -> Void) {
        self.testUUID = testUUID
        self.originalService = originalService
        self.onSend = onSend
    }

    func send(fences: [Fence]) async throws {
        onSend(fences)
        try await originalService.send(fences: fences)
    }
}
