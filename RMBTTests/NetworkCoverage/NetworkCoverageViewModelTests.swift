//
//  NetworkCoverageViewModelTests.swift
//  RMBTTest
//
//  Created by Jiri Urbasek on 13.01.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Testing
@testable import RMBT
import Combine
import CoreLocation

// Looks like a bug inside SwiftTesting/Xcode - when running tests paralerly it crashes at objc_release_x8 deep inside
// the stanradrd library. So running tests serially fixes it partially.
@Suite(.serialized)
@MainActor struct NetworkCoverageTests {
    @Test func whenInitializedWithNoPrefilledLocationAreas_thenAreasAreEmpty() async throws {
        let sut = makeSUT(areas: [])
        #expect(sut.fences.isEmpty)
    }

    @Test func whenReceivingFirstLocationUpdate_thenCreatesFirstArea() async throws {
        let sut = makeSUT(updates: [makeLocationUpdate(at: 5, lat: 1.0, lon: 2.0)])
        await sut.startTest()

        #expect(sut.fences.count == 1)
        #expect(sut.fences.first?.coordinate.latitude == 1.0)
        #expect(sut.fences.last?.coordinate.longitude == 2.0)
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

        #expect(sut.fences.count == 2)

        sut.selectedFenceID = sut.fences.first?.id
        #expect(sut.selectedFenceDetail?.averagePing == "18 ms")

        sut.selectedFenceID = sut.fences.last?.id
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

        #expect(sut.fences
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

        #expect(sut.fences.count == 2)

        sut.selectedFenceID = sut.fences.first?.id
        #expect(sut.selectedFenceDetail?.averagePing == "15 ms")

        sut.selectedFenceID = sut.fences.last?.id
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
}

extension NetworkCoverageTests {
    struct NetworkCoverageScene {
        let viewModel: NetworkCoverageViewModel
        let presenter: NetworkCoverageViewPresenter
    }

    func makeSUT(
        areas: [LocationArea] = [],
        refreshInterval: TimeInterval = 1,
        updates: [NetworkCoverageViewModel.Update] = [],
        locale: Locale = Locale(identifier: "en_US")
    ) -> NetworkCoverageViewModel {
        .init(
            areas: areas,
            refreshInterval: refreshInterval,
            updates: { updates.publisher.values },
            currentRadioTechnology: RadioTechnologyServiceStub(),
            sendResultsService: SendCoverageResultsServiceSpy(),
            locale: locale
        )
    }
}

func makeLocationUpdate(at timestampOffset: TimeInterval, lat: CLLocationDegrees, lon: CLLocationDegrees) -> NetworkCoverageViewModel.Update {
    .location(LocationUpdate(location: .init(latitude: lat, longitude: lon), timestamp: Date(timeIntervalSinceReferenceDate: timestampOffset)))
}

func makePingUpdate(at timestampOffset: TimeInterval, ms: some BinaryInteger) -> NetworkCoverageViewModel.Update {
    .ping(.init(result: .interval(.milliseconds(ms)), timestamp: Date(timeIntervalSinceReferenceDate: timestampOffset)))
}

@MainActor extension NetworkCoverageViewModel {
    func startTest() async {
        await toggleMeasurement()
    }
}

final class SendCoverageResultsServiceSpy: SendCoverageResultsService {
    private(set) var capturedSentAreas: [[LocationArea]] = []

    func send(areas: [LocationArea]) async throws {
        capturedSentAreas.append(areas)
    }
}

extension AsyncThrowingPublisher: @retroactive AsynchronousSequence {}

final class RadioTechnologyServiceStub: CurrentRadioTechnologyService {
    func technologyCode() -> String? {
        nil
    }
}
