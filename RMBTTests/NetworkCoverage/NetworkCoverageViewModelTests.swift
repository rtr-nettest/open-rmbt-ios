//
//  NetworkCoverageViewModelTests.swift
//  RMBTTest
//
//  Created by Jiri Urbasek on 13.01.2025.
//  Copyright 2025 appscape gmbh. All rights reserved.
//

import Testing
@testable import RMBT
import Combine
import CoreLocation
import SwiftData

// Looks like a bug inside SwiftTesting/Xcode - when running tests paralerly it crashes at objc_release_x8 deep inside
// the stanradrd library. So running tests serially fixes it partially.
@Suite(.serialized)
@MainActor struct NetworkCoverageTests {
    @Test func whenInitializedWithNoPrefilledFences_thenFenceItemsAreEmpty() async throws {
        let sut = makeSUT(fences: [])
        #expect(sut.fenceItems.isEmpty)
    }

    @Test func whenReceivingFirstLocationUpdate_thenCreatesFirstFence() async throws {
        let sut = makeSUT(updates: [makeLocationUpdate(at: 5, lat: 1.0, lon: 2.0)])
        await sut.startTest()

        #expect(sut.fenceItems.count == 1)
        #expect(sut.fenceItems.first?.coordinate.latitude == 1.0)
        #expect(sut.fenceItems.last?.coordinate.longitude == 2.0)
    }

    @Test func whenReceivingMultiplePingsForOneLocation_thenCombinesPingTotalValue() async throws {
        let sut = makeSUT(updates: [
            makeLocationUpdate  (at: 1, lat: 1.0, lon: 1.0),
            makePingUpdate      (at: 2, ms: 10),
            makePingUpdate      (at: 3, ms: 20),
            makePingUpdate      (at: 4, ms: 26),
            makeLocationUpdate  (at: 5, lat: 2.0, lon: 1.0),
        ])
        await sut.startTest()

        #expect(sut.fenceItems.count == 2)

        sut.selectedFenceID = sut.fenceItems.first?.id
        #expect(sut.selectedFenceDetail?.averagePing == "18 ms")

        sut.selectedFenceID = sut.fenceItems.last?.id
        #expect(sut.selectedFenceDetail?.averagePing == "")
    }

    @Test func whenReceivedPingsWithTimeBeforeFenceChanged_thenTheyAreAssignedToPreviousFence() async throws {
        let sut = makeSUT(updates: [
            makeLocationUpdate  (at: 0, lat: 1, lon: 1),
            makePingUpdate      (at: 1, ms: 10),
            makeLocationUpdate  (at: 5, lat: 2, lon: 2),
            makePingUpdate      (at: 2, ms: 2000),
            makePingUpdate      (at: 3, ms: 3000),
            makeLocationUpdate  (at: 10, lat: 3, lon: 3),
            makePingUpdate      (at: 11, ms: 100),
            makePingUpdate      (at: 18, ms: 200),
            makeLocationUpdate  (at: 20, lat: 4, lon: 4),
            makeLocationUpdate  (at: 30, lat: 5, lon: 5),
            makePingUpdate      (at: 31, ms: 100),
            makePingUpdate      (at: 37, ms: 200),
            makeLocationUpdate  (at: 40, lat: 6, lon: 6),
            makePingUpdate      (at: 41, ms: 400),
            makePingUpdate      (at: 42, ms: 200),
            makePingUpdate      (at: 22, ms: 2000),
            makePingUpdate      (at: 24, ms: 4000),
            makePingUpdate      (at: 34, ms: 3000)

        ])
        await sut.startTest()

        #expect(sut.fenceItems
            .map(\.id)
            .map {
                sut.selectedFenceID = $0
                return sut.selectedFenceDetail?.averagePing ?? "(no detail selected)"
            } == [
                "1670 ms",  // t = 0 - 5
                "",         // t = 5 - 10
                "150 ms",   // t = 10 - 20
                "3000 ms",  // t = 20 - 30
                "1100 ms",  // t = 30 = 40
                "300 ms"    // t = 40+
            ]
        )
    }

    @Test func whenReceivingPingsForDifferentLocations_thenAssignesPingsToProperLocations() async throws {
        let sut = makeSUT(updates: [
            makeLocationUpdate  (at: 1, lat: 1.0, lon: 1.0),
            makePingUpdate      (at: 2, ms: 10),
            makePingUpdate      (at: 3, ms: 20),
            makeLocationUpdate  (at: 4, lat: 2.0, lon: 1.0),
            makePingUpdate      (at: 5, ms: 26)
        ])
        await sut.startTest()

        #expect(sut.fenceItems.count == 2)

        sut.selectedFenceID = sut.fenceItems.first?.id
        #expect(sut.selectedFenceDetail?.averagePing == "15 ms")

        sut.selectedFenceID = sut.fenceItems.last?.id
        #expect(sut.selectedFenceDetail?.averagePing == "26 ms")
    }

    @Test func whenReceivedNoPings_thenLatestPingIsNotAvailable() async throws {
        let sut = makeSUT(
            updates: [
                makeLocationUpdate  (at: 1, lat: 1.0, lon: 1.0),
                makeLocationUpdate  (at: 2, lat: 1.0, lon: 1.0)
            ]
        )
        await sut.startTest()

        #expect(sut.latestPing == "N/A")
    }

    @Test(arguments: [
        [ // same location
            makeLocationUpdate  (at: 1, lat: 1.0, lon: 1.0),
            makePingUpdate      (at: 2, ms: 10),
            makePingUpdate      (at: 3, ms: 20),
            makePingUpdate      (at: 4, ms: 30)
        ],
        [ // different locations
            makeLocationUpdate  (at: 1, lat: 1.0, lon: 1.0),
            makePingUpdate      (at: 2, ms: 10),
            makeLocationUpdate  (at: 3, lat: 2.0, lon: 2.0),
            makePingUpdate      (at: 4, ms: 20),
            makeLocationUpdate  (at: 5, lat: 3.0, lon: 3.0),
            makePingUpdate      (at: 6, ms: 30)
        ]
    ])
    func whenReceivedPingsBeforeCompletingRefreshInterval_thenLatestPingIsNotDisplayed(updates: [NetworkCoverageViewModel.Update]) async throws {
        let sut = makeSUT(refreshInterval: 10, updates: updates)
        await sut.startTest()
        #expect(sut.latestPing == "-")
    }
    @Test(arguments: [
        ([ // first interval, pings received withing the same fence
            // refresh interval 0-9
            makePingUpdate      (at: 0, ms: 10),
            makeLocationUpdate  (at: 1, lat: 1.0, lon: 1.0),
            makePingUpdate      (at: 3, ms: 12),
            makeLocationUpdate  (at: 4, lat: 1.00000001, lon: 1.00000001),
            makePingUpdate      (at: 5, ms: 17),
            // refresh interval 10-19
            makeLocationUpdate  (at: 10, lat: 2, lon: 2),
            makePingUpdate      (at: 11, ms: 20),
            makePingUpdate      (at: 12, ms: 40),
            makeLocationUpdate  (at: 13, lat: 2.00000001, lon: 2.000000001)
         ], "13 ms"),
        ([ // first interval, pings received withing different fences
            // refresh interval 0-9
            makePingUpdate      (at: 0, ms: 10),
            makeLocationUpdate  (at: 1, lat: 1.0, lon: 1.0),
            makePingUpdate      (at: 3, ms: 12),
            makeLocationUpdate  (at: 4, lat: 2.0, lon: 2.0),
            makePingUpdate      (at: 5, ms: 17),
            makeLocationUpdate  (at: 6, lat: 3.0, lon: 3.0),
            makePingUpdate      (at: 7, ms: 13),
            // refresh interval 10-19
            makeLocationUpdate  (at: 10, lat: 2, lon: 2),
            makePingUpdate      (at: 11, ms: 20),
            makePingUpdate      (at: 12, ms: 40),
            makeLocationUpdate  (at: 13, lat: 2.00000001, lon: 2.000000001)
         ], "13 ms"),
        ([ // third interval, pings received withing same fence
            // refresh interval 0-9
            makePingUpdate      (at: 0, ms: 5),
            makeLocationUpdate  (at: 1, lat: 1.0, lon: 1.0),
            makePingUpdate      (at: 2, ms: 10),
            makePingUpdate      (at: 3, ms: 20),
            // refresh interval 10-19
            makeLocationUpdate  (at: 10, lat: 2, lon: 2),
            makePingUpdate      (at: 11, ms: 20),
            makePingUpdate      (at: 12, ms: 40),
            makeLocationUpdate  (at: 13, lat: 2.00000001, lon: 2.000000001),
            // refresh interval 20-29
            makePingUpdate      (at: 20, ms: 110),
            makeLocationUpdate  (at: 21, lat: 2.00000002, lon: 2.000000002), // same fence as previous refresh interval
            makePingUpdate      (at: 22, ms: 120),
            makePingUpdate      (at: 23, ms: 130),
            makePingUpdate      (at: 24, ms: 200),
            // refresh interval 30-39
            makePingUpdate      (at: 31, ms: 10),
         ], "140 ms"),
        ([ // third interval, pings received withing different fences
            // refresh interval 0-9
            makePingUpdate      (at: 0, ms: 5),
            makeLocationUpdate  (at: 1, lat: 1.0, lon: 1.0),
            makePingUpdate      (at: 2, ms: 10),
            makePingUpdate      (at: 3, ms: 20),
            makeLocationUpdate  (at: 4, lat: 2.0, lon: 2.0),
            // refresh interval 10-19
            makeLocationUpdate  (at: 10, lat: 2, lon: 2),
            makePingUpdate      (at: 11, ms: 20),
            makePingUpdate      (at: 12, ms: 40),
            makeLocationUpdate  (at: 13, lat: 2.00000001, lon: 2.000000001),
            makeLocationUpdate  (at: 15, lat: 3.0, lon: 3.0),
            // refresh interval 20-29
            makePingUpdate      (at: 20, ms: 110),
            makeLocationUpdate  (at: 21, lat: 3.00000001, lon: 3.000001),
            makePingUpdate      (at: 22, ms: 120),
            makePingUpdate      (at: 23, ms: 130),
            makeLocationUpdate  (at: 24, lat: 4.0, lon: 4.0),
            makePingUpdate      (at: 25, ms: 200),
            // refresh interval 30-39
            makePingUpdate      (at: 31, ms: 10),
         ], "140 ms")
    ])
    func whenReceivedPingsAfterCompletingRefreshInterval_thenLatestPingIsAverageOfAllPingsWithinLastCompletedRefreshInterva(arguments: (updates: [NetworkCoverageViewModel.Update], expectedLatestPing: String)) async {
        let sut = makeSUT(refreshInterval: 10, updates: arguments.updates)
        await sut.startTest()
        #expect(sut.latestPing == arguments.expectedLatestPing)
    }

    @MainActor @Suite("WHEN Received Location Updates With Bad Accuracy")
    struct WhenReceivedLocationUpdatesWithBadAccuracy {
        @Test func goodLocationUpdatesAreInsideSameFence_thenNoNewFenceIsCreated() async throws {
            let minAccuracy = CLLocationDistance(100)
            let sut = makeSUT(minimumLocationAccuracy: minAccuracy, updates: [
                makeLocationUpdate  (at: 0, lat: 1.0000000001, lon: 1.0000000002, accuracy: minAccuracy / 2),
                makePingUpdate      (at: 1, ms: 100),
                makeLocationUpdate  (at: 2, lat: 2, lon: 2, accuracy: minAccuracy * 2),
                makePingUpdate      (at: 3, ms: 20),
                makePingUpdate      (at: 4, ms: 30),
                makeLocationUpdate  (at: 5, lat: 1.0, lon: 1.0000000001, accuracy: minAccuracy / 3),
                makePingUpdate      (at: 6, ms: 200),
                makePingUpdate      (at: 7, ms: 150),
                makeLocationUpdate  (at: 8, lat: 2, lon: 3, accuracy: minAccuracy + 1),
                makePingUpdate      (at: 9, ms: 300),
                makeLocationUpdate  (at: 10, lat: 1.00000000002, lon: 1.0000000003, accuracy: minAccuracy - 1),
                makePingUpdate      (at: 11, ms: 150),
            ])
            await sut.startTest()

            #expect(sut.fenceItems.count == 1)
            #expect(sut.fenceItems.first?.date == Date(timeIntervalSinceReferenceDate: 0))
            #expect(sut.fenceItems.first?.coordinate.latitude == 1.0000000001)
            #expect(sut.fenceItems.first?.coordinate.longitude == 1.0000000002)
        }

        @Test func goodLocationUpdatesAreInsideDifferentFences_theNewFencesAreCreated() async throws {
            let minAccuracy = CLLocationDistance(100)
            let sut = makeSUT(minimumLocationAccuracy: minAccuracy, updates: [
                makeLocationUpdate  (at: 0, lat: 1, lon: 1, accuracy: minAccuracy / 2),
                makePingUpdate      (at: 1, ms: 100),
                makeLocationUpdate  (at: 2, lat: 2, lon: 2, accuracy: minAccuracy * 2),
                makePingUpdate      (at: 3, ms: 20),
                makePingUpdate      (at: 4, ms: 30),
                makeLocationUpdate  (at: 5, lat: 2.000000001, lon: 2.000000002, accuracy: minAccuracy / 3),
                makePingUpdate      (at: 6, ms: 200),
                makePingUpdate      (at: 7, ms: 150),
                makeLocationUpdate  (at: 8, lat: 2, lon: 2.0000000002, accuracy: minAccuracy + 1),
                makePingUpdate      (at: 9, ms: 300),
                makeLocationUpdate  (at: 10, lat: 2.0, lon: 2.0000000003, accuracy: minAccuracy - 1),
                makePingUpdate      (at: 11, ms: 150),
                makeLocationUpdate  (at: 12, lat: 3, lon: 2.0000000003, accuracy: minAccuracy / 4)
            ])
            await sut.startTest()

            #expect(sut.fenceItems.count == 3)
            #expect(sut.fenceItems.map(\.date).map(\.timeIntervalSinceReferenceDate) == [0, 5, 12])
            #expect(sut.fenceItems.map(\.coordinate) == [
                .init(latitude: 1, longitude: 1),
                .init(latitude: 2.000000001, longitude: 2.000000002),
                .init(latitude: 3, longitude: 2.0000000003)
            ])
        }

        @Test func pingsReceivedDuringTimeOfBadLocationAreIgnored() async throws {
            let minAccuracy = CLLocationDistance(100)
            let sut = makeSUT(minimumLocationAccuracy: minAccuracy, updates: [
                makeLocationUpdate  (at: 0, lat: 1, lon: 1, accuracy: minAccuracy / 2),
                makePingUpdate      (at: 1, ms: 100),
                makeLocationUpdate  (at: 2, lat: 2, lon: 2, accuracy: minAccuracy * 2),
                makePingUpdate      (at: 3, ms: 20),
                makePingUpdate      (at: 4, ms: 30),
                makeLocationUpdate  (at: 5, lat: 1, lon: 1.0000000001, accuracy: minAccuracy / 3),
                makePingUpdate      (at: 6, ms: 200),
                makePingUpdate      (at: 7, ms: 150),
                makeLocationUpdate  (at: 8, lat: 2, lon: 3, accuracy: minAccuracy + 1),
                makePingUpdate      (at: 9, ms: 300),
                makeLocationUpdate  (at: 10, lat: 2, lon: 2.0000000003, accuracy: minAccuracy - 1),
                makePingUpdate      (at: 11, ms: 400),
                makeLocationUpdate  (at: 12, lat: 2.000000001, lon: 2.0000000002, accuracy: minAccuracy * 2),
                makePingUpdate      (at: 13, ms: 600),
                makeLocationUpdate  (at: 14, lat: 2.000000002, lon: 2.0000000003, accuracy: minAccuracy - 2),
                makePingUpdate      (at: 15, ms: 200),
            ])
            await sut.startTest()

            #expect(sut.fenceItems.count == 2)

            sut.selectedFenceID = sut.fenceItems.first?.id
            #expect(sut.selectedFenceDetail?.averagePing == "150 ms")

            sut.selectedFenceID = sut.fenceItems.last?.id
            #expect(sut.selectedFenceDetail?.averagePing == "300 ms")
        }
    }

    @MainActor @Suite("Persistence")
    struct Persistence {
        @Test func whenReceivingLocationUpdatesAndPings_thenPersistedFencesIntoPersistenceLayer() async throws {
            let persistenceService = FencePersistenceServiceSpy()
            let sut = makeSUT(
                updates: [
                    makeLocationUpdate  (at: 0, lat: 1.0, lon: 1.0),
                    makePingUpdate      (at: 1, ms: 100),
                    makePingUpdate      (at: 2, ms: 200),
                    makeLocationUpdate  (at: 3, lat: 2.0, lon: 2.0),
                    makePingUpdate      (at: 4, ms: 300),
                    makeLocationUpdate  (at: 5, lat: 2.000001, lon: 2.0000001),
                    makePingUpdate      (at: 6, ms: 500),
                    makeLocationUpdate  (at: 7, lat: 3.0, lon: 3.0),
                ],
                persistenceService: persistenceService
            )
            await sut.startTest()

            let savedFences = persistenceService.capturedSavedFences

            try #require(savedFences.count == 2)

            #expect(savedFences.first?.dateEntered ==  Date(timeIntervalSinceReferenceDate: 0))
            #expect(savedFences.first?.startingLocation.coordinate.latitude == 1.0)
            #expect(savedFences.first?.startingLocation.coordinate.longitude == 1.0)
            #expect(savedFences.first?.averagePing == 150)
            #expect(savedFences.first?.significantTechnology == nil)

            #expect(savedFences.last?.dateEntered ==  Date(timeIntervalSinceReferenceDate: 3))
            #expect(savedFences.last?.startingLocation.coordinate.latitude == 2.0)
            #expect(savedFences.last?.startingLocation.coordinate.longitude == 2.0)
            #expect(savedFences.last?.averagePing == 400)
            #expect(savedFences.last?.significantTechnology == nil)
        }
    }
}

@MainActor func makeSUT(
    fences: [Fence] = [],
    refreshInterval: TimeInterval = 1,
    minimumLocationAccuracy: CLLocationDistance = 100,
    updates: [NetworkCoverageViewModel.Update] = [],
    locale: Locale = Locale(identifier: "en_US"),
    persistenceService: FencePersistenceServiceSpy = .init(),
    sendResultsService: SendCoverageResultsServiceSpy = .init()
) -> NetworkCoverageViewModel {
    .init(
        fences: fences,
        refreshInterval: refreshInterval,
        minimumLocationAccuracy: minimumLocationAccuracy,
        updates: { updates.publisher.values },
        currentRadioTechnology: RadioTechnologyServiceStub(),
        sendResultsService: sendResultsService,
        persistenceService: persistenceService,
        locale: locale
    )
}

func makeLocationUpdate(at timestampOffset: TimeInterval, lat: CLLocationDegrees, lon: CLLocationDegrees, accuracy: CLLocationAccuracy = 1) -> NetworkCoverageViewModel.Update {
    let timestamp = Date(timeIntervalSinceReferenceDate: timestampOffset)
    return .location(
        LocationUpdate(
            location: .init(
                coordinate: .init(latitude: lat, longitude: lon),
                altitude: 0,
                horizontalAccuracy: accuracy,
                verticalAccuracy: 1,
                timestamp: timestamp
            ) ,
            timestamp: timestamp
        )
    )
}

func makePingUpdate(at timestampOffset: TimeInterval, ms: some BinaryInteger) -> NetworkCoverageViewModel.Update {
    .ping(.init(result: .interval(.milliseconds(ms)), timestamp: Date(timeIntervalSinceReferenceDate: timestampOffset)))
}

func makeSaveError() -> Error {
    NSError(domain: "test", code: 1, userInfo: nil)
}

@MainActor extension NetworkCoverageViewModel {
    func startTest() async {
        await toggleMeasurement()
    }
}

final class SendCoverageResultsServiceSpy: SendCoverageResultsService {
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

extension AsyncThrowingPublisher: @retroactive AsynchronousSequence {}

final class RadioTechnologyServiceStub: CurrentRadioTechnologyService {
    func technologyCode() -> String? {
        nil
    }
}

final class FencePersistenceServiceSpy: FencePersistenceService {
    private(set) var capturedSavedFences: [Fence] = []

    init() {}

    func save(_ fence: Fence) throws {
        capturedSavedFences.append(fence)
    }
}
