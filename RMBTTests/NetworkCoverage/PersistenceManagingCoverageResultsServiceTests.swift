//
//  PersistenceManagingCoverageResultsServiceTests.swift
//  RMBTTest
//
//  Created by Jiri Urbasek on 30.05.2025.
//  Copyright 2025 appscape gmbh. All rights reserved.
//

import Testing
@testable import RMBT
import SwiftData
import CoreLocation

@MainActor struct PersistenceManagingCoverageResultsServiceTests {
    @Test func whenSendSucceeds_thenDeletesPersistedAreasWithMatchingTestUUID() async throws {
        let testUUID = "test-uuid-123"
        let (sut, persistenceService, sendService) = makeSUT(
            testUUID: testUUID,
            prefilledAreas: [
                makePersistentArea(testUUID: testUUID, timestamp: 1000000),
                makePersistentArea(testUUID: testUUID, timestamp: 2000000),
                makePersistentArea(testUUID: "different-uuid", timestamp: 3000000)
            ]
        )

        try await sut.send(areas: [makeLocationArea()])

        // Verify that areas with matching testUUID are deleted
        let remainingAreas = try persistenceService.persistedAreas()
        #expect(remainingAreas.count == 1)
        #expect(remainingAreas.first?.testUUID == "different-uuid")

        // Verify that send was called
        #expect(sendService.capturedSentAreas.count == 1)
        #expect(sendService.capturedSentAreas.first?.count == 1)
    }

    @Test func whenSendFails_thenDoesNotDeletePersistedAreas() async throws {
        let testUUID = "test-uuid-456"
        let (sut, persistenceService, sendService) = makeSUT(
            testUUID: testUUID,
            sendResult: .failure(TestError.sendFailed),
            prefilledAreas: [
                makePersistentArea(testUUID: testUUID, timestamp: 1000000)
            ]
        )

        // Verify that error is propagated
        await #expect(throws: TestError.self) {
            try await sut.send(areas: [makeLocationArea()])
        }

        // Verify that areas are not deleted when send fails
        let remainingAreas = try persistenceService.persistedAreas()
        #expect(remainingAreas.count == 1)
        #expect(remainingAreas.first?.testUUID == testUUID)

        // Verify that send was attempted
        #expect(sendService.capturedSentAreas.count == 1)
    }

    @Test func whenTestUUIDIsNil_thenSendsButDoesNotDeleteAnyPersistedAreas() async throws {
        let (sut, persistenceService, sendService) = makeSUT(
            testUUID: nil,
            prefilledAreas: [
                makePersistentArea(testUUID: "some-uuid", timestamp: 1000000)
            ]
        )

        try await sut.send(areas: [makeLocationArea()])

        // Verify that no areas are deleted when testUUID is nil
        let remainingAreas = try persistenceService.persistedAreas()
        #expect(remainingAreas.count == 1)
        #expect(remainingAreas.first?.testUUID == "some-uuid")

        // Verify that send was called
        #expect(sendService.capturedSentAreas.count == 1)
    }

    @Test func whenMultipleAreasExistWithSameTestUUID_thenDeletesAllMatchingAreas() async throws {
        let testUUID = "test-uuid-789"
        let prefilledAreas = (0..<5).map { i in
            makePersistentArea(testUUID: testUUID, timestamp: UInt64(i * 1000000))
        } + [makePersistentArea(testUUID: "different-uuid", timestamp: 9999999)]

        let (sut, persistenceService, sendService) = makeSUT(
            testUUID: testUUID,
            prefilledAreas: prefilledAreas
        )

        try await sut.send(areas: [makeLocationArea()])

        // Verify that only areas with different testUUID remain
        let remainingAreas = try persistenceService.persistedAreas()
        #expect(remainingAreas.count == 1)
        #expect(remainingAreas.first?.testUUID == "different-uuid")

        // Verify that send was called
        #expect(sendService.capturedSentAreas.count == 1)
    }

    @Test func whenNoPersistedAreasExist_thenSendsSuccessfullyWithoutError() async throws {
        let testUUID = "test-uuid-empty"
        let (sut, persistenceService, sendService) = makeSUT(testUUID: testUUID)

        try await sut.send(areas: [makeLocationArea()])

        // Verify that no areas exist (as expected)
        let remainingAreas = try persistenceService.persistedAreas()
        #expect(remainingAreas.isEmpty)

        // Verify that send was called
        #expect(sendService.capturedSentAreas.count == 1)
    }
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
    sendResult: Result<Void, Error> = .success(()),
    prefilledAreas: [PersistentLocationArea] = []
) -> (PersistenceManagingCoverageResultsService, PersistenceLayerSpy, SendCoverageResultsServiceSpy) {
    let modelContext = makeInMemoryModelContext()
    let persistence = PersistenceLayerSpy(modelContext: modelContext)
    let sendService = SendCoverageResultsServiceSpy(sendResult: sendResult)

    // Insert prefilled areas into modelContext
    for area in prefilledAreas {
        modelContext.insert(area)
    }
    try! modelContext.save()

    let sut = PersistenceManagingCoverageResultsService(
        modelContext: modelContext,
        testUUID: testUUID,
        sendResultsService: sendService
    )
    return (sut, persistence, sendService)
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

private func makeLocationArea() -> LocationArea {
    LocationArea(
        startingLocation: CLLocation(latitude: 1.0, longitude: 2.0),
        dateEntered: Date(),
        technology: "4G"
    )
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

