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
        @Test func whenPersistedLocationAreas_thenTheyArePresentInPersistenceLayer() async throws {
            let (sut, persistence, _) = makeSUT(testUUID: "dummy")

            try sut.persist(fence: makeLocationArea(lat: 1, lon: 2, date: Date(timeIntervalSinceReferenceDate: 1), technology: "LTE"))
            try sut.persist(fence: makeLocationArea(lat: 3, lon: 4, date: Date(timeIntervalSinceReferenceDate: 2), technology: "3G"))

            let persistedAreas = try #require(try persistence.persistedAreas())
            try #require(persistedAreas.count == 2)

            #expect(persistedAreas[0].testUUID == "dummy")
            #expect(persistedAreas[0].latitude == 1)
            #expect(persistedAreas[0].longitude == 2)
            #expect(persistedAreas[0].timestamp == Date(timeIntervalSinceReferenceDate: 1).microsecondsTimestamp)
            #expect(persistedAreas[0].technology == "LTE")

            #expect(persistedAreas[1].testUUID == "dummy")
            #expect(persistedAreas[1].latitude == 3)
            #expect(persistedAreas[1].longitude == 4)
            #expect(persistedAreas[1].timestamp == Date(timeIntervalSinceReferenceDate: 2).microsecondsTimestamp)
            #expect(persistedAreas[1].technology == "3G")
        }

        @Test func whenSendingLocationAreasSucceds_thenTheyAreRemovedFromPersistenceLayer() async throws {
            let (sut, persistence, sendService) = makeSUT(testUUID: "dummy", sendResults: [.success(())])
            let areas = [
                makeLocationArea(lat: 1, lon: 2, technology: "LTE"),
                makeLocationArea(lat: 3, lon: 4, technology: "3G")
            ]
            try await sut.persistAndSend(fences: areas)

            let persistedAreas = try persistence.persistedAreas()
            #expect(persistedAreas.count == 0)
            #expect(sendService.capturedSendCalls.count == 1)
        }

        @Test func whenSendingLocationAreaFails_thenTheyAreKeptInPersistenceLayer() async throws {
            let (sut, persistence, sendService) = makeSUT(testUUID: "dummy", sendResults: [.failure(TestError.sendFailed)])
            let areas = [
                makeLocationArea(lat: 1, lon: 2, date: Date(timeIntervalSinceReferenceDate: 1), technology: "LTE"),
                makeLocationArea(lat: 3, lon: 4, date: Date(timeIntervalSinceReferenceDate: 2), technology: "3G")
            ]
            await #expect(throws: TestError.sendFailed) {
                try await sut.persistAndSend(fences: areas)
            }

            let persistedAreas = try persistence.persistedAreas()
            #expect(sendService.capturedSendCalls.count == 1)
            #expect(persistedAreas.count == 2)
        }
    }

    struct GivenHasPreviouslyPersitedData {
        @Test func whenSendingFencesSucceeds_thenAttemptsToSendAndRemovesAlsoPreviouslyPersistedFences() async throws {
            let testUUID = "test-uuid"
            let prevTestUUID = "prev-test-uuid"
            let prevPersistedFences = [
                makePersistentArea(testUUID: prevTestUUID, timestamp: 10),
                makePersistentArea(testUUID: prevTestUUID, timestamp: 11)
            ]
            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .success(())],
                previouslyPersistedFences: prevPersistedFences
            )

            try await sut.persistAndSend(fences: [makeLocationArea(), makeLocationArea(), makeLocationArea()])

            let remainingAreas = try persistence.persistedAreas()
            #expect(remainingAreas.count == 0)
            #expect(sendService.capturedSendCalls.count == 2)
            #expect(sendService.capturedSendCalls.map(\.testUUID) == [testUUID, prevTestUUID])
            #expect(sendService.capturedSendCalls.map(\.areas.count) == [3, prevPersistedFences.count])
        }

        @Test func whenAttemptToSendPreviouslyPersistedFencesFails_thenKeepsThoseFencesPersisted() async throws {
            let testUUID = "test-uuid"
            let prevTestUUID = "prev-test-uuid"
            let prevPrevTestUUID = "prev-prev-test-uuid"
            let prevPersistedFences = [
                makePersistentArea(testUUID: prevTestUUID, timestamp: 100),
                makePersistentArea(testUUID: prevTestUUID, timestamp: 110),
                makePersistentArea(testUUID: prevPrevTestUUID, timestamp: 10),
                makePersistentArea(testUUID: prevPrevTestUUID, timestamp: 12),
                makePersistentArea(testUUID: prevPrevTestUUID, timestamp: 14),
                makePersistentArea(testUUID: prevPrevTestUUID, timestamp: 16)
            ]
            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .failure(TestError.sendFailed), .success(())],
                previouslyPersistedFences: prevPersistedFences
            )

            try await sut.persistAndSend(fences: [makeLocationArea(), makeLocationArea(), makeLocationArea()])

            let remainingAreas = try persistence.persistedAreas()
            #expect(remainingAreas.count == 2)
            #expect(remainingAreas.allSatisfy { $0.testUUID == prevTestUUID })

            #expect(sendService.capturedSendCalls.count == 3)
            #expect(sendService.capturedSendCalls.map(\.testUUID) == [testUUID, prevTestUUID, prevPrevTestUUID])
            #expect(sendService.capturedSendCalls.map(\.areas.count) == [3, 2, 4])
        }

        @Test func whenSendingPreviouslyPersistedFences_thenMappsThemProperlyToDomainObjects() async throws {
            let testUUID = "persisted-uuid"
            let expectedLat = 50.123456
            let expectedLon = 14.654321
            let expectedPing = 120
            let expectedTimestamp: UInt64 = 1640995200000000 // 2022-01-01 00:00:00 in microseconds
            let expectedTechnology = "5G"

            let persistentArea = PersistentLocationArea(
                testUUID: testUUID,
                timestamp: expectedTimestamp,
                latitude: expectedLat,
                longitude: expectedLon,
                avgPingMilliseconds: expectedPing,
                technology: expectedTechnology
            )

            let (sut, _, sendService) = makeSUT(
                testUUID: "main-uuid",
                sendResults: [.success(()), .success(())],
                previouslyPersistedFences: [persistentArea]
            )

            try await sut.persistAndSend(fences: [makeLocationArea()])

            let mappedFence = try #require(sendService.capturedSendCalls.last?.areas.first)

            #expect(mappedFence.startingLocation.coordinate.latitude == expectedLat)
            #expect(mappedFence.startingLocation.coordinate.longitude == expectedLon)
            #expect(mappedFence.dateEntered == expectedTimestamp.dateFromMicroseconds)
            #expect(mappedFence.technologies.first == expectedTechnology)
            #expect(mappedFence.averagePing == expectedPing)
        }
    }

    struct GivenHasPersistentAreasOderThenMaxResendAge {
        @Test func whenPersistentAreasAreOlderThanMaxAge_thenTheyAreDeletedWithoutSending() async throws {
            let testUUID = "current-test"
            let oldTestUUID = "old-test"
            let maxAgeSeconds: TimeInterval = 3600 // 1 hour
            let currentTime = Date()

            // Create old areas (older than maxAge)
            let oldTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds - 1).microsecondsTimestamp
            let oldAreas = [
                makePersistentArea(testUUID: oldTestUUID, timestamp: oldTimestamp),
                makePersistentArea(testUUID: oldTestUUID, timestamp: oldTimestamp + 1000)
            ]

            // Create recent areas (within maxAge)
            let recentTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds + 600).microsecondsTimestamp
            let recentAreas = [
                makePersistentArea(testUUID: "recent-test", timestamp: recentTimestamp)
            ]

            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .success(())],
                previouslyPersistedFences: oldAreas + recentAreas,
                maxResendAge: maxAgeSeconds
            )

            try await sut.persistAndSend(fences: [makeLocationArea()])

            let remainingAreas = try persistence.persistedAreas()
            // Only recent areas should remain, old areas should be deleted
            #expect(remainingAreas.count == 0) // recent area should be sent and removed too
            #expect(sendService.capturedSendCalls.count == 2) // current + recent (old areas not sent)
            #expect(sendService.capturedSendCalls.map(\.testUUID).contains(oldTestUUID) == false)
        }

        @Test func whenPersistentAreasAreWithinMaxAge_thenTheyAreKeptAndSent() async throws {
            let testUUID = "current-test"
            let recentTestUUID = "recent-test"
            let maxAgeSeconds: TimeInterval = 3600 // 1 hour
            let currentTime = Date()

            // Create recent areas (within maxAge)
            let recentTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds + 600).microsecondsTimestamp
            let recentAreas = [
                makePersistentArea(testUUID: recentTestUUID, timestamp: recentTimestamp),
                makePersistentArea(testUUID: recentTestUUID, timestamp: recentTimestamp + 1000)
            ]

            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .success(())],
                previouslyPersistedFences: recentAreas,
                maxResendAge: maxAgeSeconds
            )

            try await sut.persistAndSend(fences: [makeLocationArea()])

            let remainingAreas = try persistence.persistedAreas()
            #expect(remainingAreas.count == 0) // All should be sent and removed
            #expect(sendService.capturedSendCalls.count == 2) // current + recent
            #expect(sendService.capturedSendCalls.map(\.testUUID) == [testUUID, recentTestUUID])
            #expect(sendService.capturedSendCalls.map(\.areas.count) == [1, 2])
        }

        @Test func whenSendingRecentAreasFailsButOldAreasExist_thenOnlyOldAreasAreDeleted() async throws {
            let testUUID = "current-test"
            let recentTestUUID = "recent-test"
            let oldTestUUID = "old-test"
            let maxAgeSeconds: TimeInterval = 3600 // 1 hour
            let currentTime = Date()

            // Create old areas (older than maxAge)
            let oldTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds - 1).microsecondsTimestamp
            let oldAreas = [
                makePersistentArea(testUUID: oldTestUUID, timestamp: oldTimestamp)
            ]

            // Create recent areas (within maxAge)
            let recentTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds + 600).microsecondsTimestamp
            let recentAreas = [
                makePersistentArea(testUUID: recentTestUUID, timestamp: recentTimestamp)
            ]

            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .failure(TestError.sendFailed)], // recent areas fail to send
                previouslyPersistedFences: oldAreas + recentAreas,
                maxResendAge: maxAgeSeconds
            )

            try await sut.persistAndSend(fences: [makeLocationArea()])

            let remainingAreas = try persistence.persistedAreas()
            // Only recent areas should remain (old areas deleted, recent areas kept due to send failure)
            #expect(remainingAreas.count == 1)
            #expect(remainingAreas.first?.testUUID == recentTestUUID)
            #expect(sendService.capturedSendCalls.count == 2) // current + attempt to send recent
            #expect(sendService.capturedSendCalls.map(\.testUUID).contains(oldTestUUID) == false)
        }
    }
}

private struct SendCall {
    let testUUID: String
    let areas: [LocationArea]
}

// MARK: - Test Helpers

private func makeInMemoryModelContext() -> ModelContext {
    let container = try! ModelContainer(
        for: PersistentLocationArea.self,
        configurations: .init(for: PersistentLocationArea.self, isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private func makeSUT(
    testUUID: String?,
    sendResults: [Result<Void, Error>] = [.success(())],
    previouslyPersistedFences: [PersistentLocationArea] = [],
    maxResendAge: TimeInterval = Date().timeIntervalSince1970 * 1000,
    dateNow: @escaping () -> Date = Date.init
) -> (sut: SUT, persistence: PersistenceLayerSpy, sendService: SendCoverageResultsServiceFactory) {
    let database = UserDatabase(useInMemoryStore: true)
    let persistence = PersistenceLayerSpy(modelContext: database.modelContext)
    let sendServiceFactory = SendCoverageResultsServiceFactory(sendResults: sendResults)

    // Insert prefilled areas into modelContext
    for area in previouslyPersistedFences {
        database.modelContext.insert(area)
    }
    try! database.modelContext.save()

    let services = NetworkCoverageFactory(database: database, maxResendAge: maxResendAge).services(testUUID: testUUID, dateNow: dateNow, sendResultsServiceMaker: { testUUID in
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

    func persist(fence: LocationArea) throws {
        try fencePersistenceService.save(fence)
    }

    func persistAndSend(fences: [LocationArea]) async throws {
        try fences.forEach {
            try persist(fence: $0)
        }
        try await sendResultsServices.send(areas: fences)
    }
}

private final class PersistenceLayerSpy {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func persistedAreas() throws -> [PersistentLocationArea] {
        try modelContext.fetch(FetchDescriptor<PersistentLocationArea>())
    }
}

private func makeLocationArea(
    lat: CLLocationDegrees = Double.random(in: -90...90),
    lon: CLLocationDegrees = Double.random(in: -180...180),
    date: Date = Date(timeIntervalSinceReferenceDate: TimeInterval.random(in: 0...10000)),
    technology: String? = ["3G", "4G", "5G", "LTE"].randomElement(),
    averagePing: Int? = nil
) -> LocationArea {
    var area = LocationArea(
        startingLocation: CLLocation(latitude: lat, longitude: lon),
        dateEntered: date,
        technology: technology
    )

    if let ping = averagePing {
        area.append(ping: PingResult(result: .interval(.milliseconds(ping)), timestamp: date))
    }

    return area
}

private func makePersistentArea(testUUID: String, timestamp: UInt64) -> PersistentLocationArea {
    PersistentLocationArea(
        testUUID: testUUID,
        timestamp: timestamp,
        latitude: Double.random(in: -90...90),
        longitude: Double.random(in: -180...180),
        avgPingMilliseconds: Int.random(in: 10...500),
        technology: ["3G", "4G", "5G", "LTE"].randomElement()
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
    private(set) var capturedSentAreas: [[LocationArea]] = []
    private let sendResult: Result<Void, Error>

    init(sendResult: Result<Void, Error> = .success(())) {
        self.sendResult = sendResult
    }

    func send(areas: [LocationArea]) async throws {
        capturedSentAreas.append(areas)
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
            onSend: { [weak self] areas in
                self?.capturedSendCalls.append(SendCall(testUUID: testUUID, areas: areas))
            }
        )
    }
}

private final class SendCoverageResultsServiceWrapper: SendCoverageResultsService {
    private let testUUID: String
    private let originalService: SendCoverageResultsServiceSpyLocal
    private let onSend: ([LocationArea]) -> Void

    init(testUUID: String, originalService: SendCoverageResultsServiceSpyLocal, onSend: @escaping ([LocationArea]) -> Void) {
        self.testUUID = testUUID
        self.originalService = originalService
        self.onSend = onSend
    }

    func send(areas: [LocationArea]) async throws {
        onSend(areas)
        try await originalService.send(areas: areas)
    }
}
