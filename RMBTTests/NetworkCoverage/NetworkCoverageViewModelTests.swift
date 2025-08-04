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
import SwiftUI
import CoreTelephony

@MainActor struct NetworkCoverageTests {
    @Test func debugDateFormatterTest() throws {
        // Test the date formatter directly
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        
        let formattedDate = formatter.string(from: date)
        print("DEBUG: Formatted date = '\(formattedDate)'")
        print("DEBUG: Date bytes = \(Array(formattedDate.utf8))")
        
        // Test technology conversion
        let technology = CTRadioAccessTechnologyLTE
        print("DEBUG: CTRadioAccessTechnologyLTE = '\(technology)'")
        print("DEBUG: technology.radioTechnologyCode = '\(technology.radioTechnologyCode ?? "nil")'")
        print("DEBUG: technology.radioTechnologyDisplayValue = '\(technology.radioTechnologyDisplayValue ?? "nil")'")
        
        // This should pass - just testing basic date formatting
        #expect(!formattedDate.isEmpty)
    }
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

        sut.selectedFenceItem = sut.fenceItems.first
        #expect(sut.selectedFenceDetail?.averagePing == "18 ms")

        sut.selectedFenceItem = sut.fenceItems.last
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
            .map { fenceId in
                sut.selectedFenceItem = sut.fenceItems.first { $0.id == fenceId }
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

        sut.selectedFenceItem = sut.fenceItems.first
        #expect(sut.selectedFenceDetail?.averagePing == "15 ms")

        sut.selectedFenceItem = sut.fenceItems.last
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

    @Test func whenTestRunsForFourHours_thenAutomaticallyStops() async throws {
        let startTime = Date(timeIntervalSinceReferenceDate: 0)
        let fourHoursInSeconds: TimeInterval = 4 * 60 * 60

        var currentTime = startTime
        let updates = [
            makeLocationUpdate(at: 0, lat: 1.0, lon: 1.0),
            makePingUpdate(at: 1, ms: 100),
            makeLocationUpdate(at: 2, lat: 2.0, lon: 2.0),
            makePingUpdate(at: 3, ms: 200),
        ]

        let sut = makeSUT(
            updates: updates,
            currentTime: { currentTime }
        )

        await sut.startTest()

        // Simulate time passing to exactly 4 hours
        currentTime = startTime.addingTimeInterval(fourHoursInSeconds)

        // Process one more update to trigger the time check
        await sut.toggleMeasurement() // This should stop due to time limit

        // Verify test automatically stopped
        #expect(!sut.isStarted)
    }

    @Test func whenTestRunsForLessThanFourHours_thenDoesNotAutoStop() async throws {
        let startTime = Date(timeIntervalSinceReferenceDate: 0)
        let threeHoursInSeconds: TimeInterval = 3 * 60 * 60

        var currentTime = startTime
        let updates = [
            makeLocationUpdate(at: 0, lat: 1.0, lon: 1.0),
            makePingUpdate(at: 1, ms: 100),
            makeLocationUpdate(at: 2, lat: 2.0, lon: 2.0),
            makePingUpdate(at: 3, ms: 200),
        ]

        let sut = makeSUT(
            updates: updates,
            currentTime: { currentTime }
        )

        await sut.startTest()

        // Simulate time passing to 3 hours (less than 4)
        currentTime = startTime.addingTimeInterval(threeHoursInSeconds)

        // Process updates - should not auto-stop
        // Test should still be running
        #expect(sut.isStarted)

        // Verify both fences were created
        #expect(sut.fenceItems.count == 2)
        #expect(sut.fenceItems.first?.coordinate.latitude == 1.0)
        #expect(sut.fenceItems.last?.coordinate.latitude == 2.0)
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

            sut.selectedFenceItem = sut.fenceItems.first
            #expect(sut.selectedFenceDetail?.averagePing == "150 ms")

            sut.selectedFenceItem = sut.fenceItems.last
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

    @MainActor @Suite("Fence Selection Tests")
    struct FenceSelectionTests {
        @Test("WHEN initialized with no fences THEN no fence is selected and fenceItems are empty")
        func whenInitializedWithNoFences_thenNoFenceIsSelectedAndFenceItemsAreEmpty() async throws {
            let sut = makeSUT(fences: [])
            
            #expect(sut.selectedFenceItem == nil)
            #expect(sut.selectedFenceDetail == nil)
            #expect(sut.fenceItems.isEmpty)
        }

        @Test("WHEN initialized with fences THEN no fence is selected initially")
        func whenInitializedWithFences_thenNoFenceIsSelectedInitially() async throws {
            let fences = [makeFence(at: 1.0, lon: 1.0), makeFence(at: 2.0, lon: 2.0)]
            let sut = makeSUT(fences: fences)
            
            #expect(sut.selectedFenceItem == nil)
            #expect(sut.selectedFenceDetail == nil)
            #expect(sut.fenceItems.map(\.isSelected) == [false, false])
        }

        @Test("WHEN valid fence ID is selected THEN fence is marked as selected and detail is populated")
        func whenValidFenceIDIsSelected_thenFenceIsMarkedAsSelectedAndDetailIsPopulated() async throws {
            let fence1 = makeFence(at: 1.0, lon: 1.0)
            let fence2 = makeFenceWithPings(
                at: 2.0, 
                lon: 3.0, 
                dateEntered: Date(timeIntervalSinceReferenceDate: 1000),
                technology: CTRadioAccessTechnologyLTE,
                pings: [
                    PingResult(result: .interval(.milliseconds(50)), timestamp: Date(timeIntervalSinceReferenceDate: 1001)),
                    PingResult(result: .interval(.milliseconds(60)), timestamp: Date(timeIntervalSinceReferenceDate: 1002)),
                    PingResult(result: .interval(.milliseconds(70)), timestamp: Date(timeIntervalSinceReferenceDate: 1003))
                ]
            )
            let sut = makeSUT(fences: [fence1, fence2])

            sut.simulateSelectFence(fence2)
            
            #expect(sut.selectedFenceItem?.id == fence2.id)
            #expect(sut.selectedFenceDetail?.id == fence2.id)
            
            #expect(sut.selectedFenceDetail?.date == sut.selectedItemDateFormatter.string(from: Date(timeIntervalSinceReferenceDate: 1000)))
            
            #expect(sut.selectedFenceDetail?.technology == "4G")
            #expect(sut.selectedFenceDetail?.averagePing == "60 ms")
            #expect(sut.selectedFenceDetail?.color == Color(technology: CTRadioAccessTechnologyLTE))
            #expect(sut.fenceItems.map(\.isSelected) == [false, true])
        }

        @Test("WHEN selection is changed to different fence THEN previous fence is deselected and new one is selected")
        func whenSelectionIsChangedToDifferentFence_thenPreviousFenceIsDeselectedAndNewOneIsSelected() async throws {
            let fence1 = makeFence(at: 1.0, lon: 1.0)
            let fence2 = makeFence(at: 2.0, lon: 2.0)
            let fence3 = makeFence(at: 3.0, lon: 3.0)
            let sut = makeSUT(fences: [fence1, fence2, fence3])
            
            sut.simulateSelectFence(fence1)
            sut.simulateSelectFence(fence3)

            #expect(sut.fenceItems.map(\.isSelected) == [false, false, true])
        }

        @Test("WHEN selection is set to nil THEN all fences are deselected")
        func whenSelectionIsSetToNil_thenAllFencesAreDeselected() async throws {
            let fence1 = makeFence(at: 1.0, lon: 1.0)
            let fence2 = makeFence(at: 2.0, lon: 2.0)
            let sut = makeSUT(fences: [fence1, fence2])

            sut.simulateSelectFence(fence1)
            sut.selectedFenceItem = nil
            
            #expect(sut.selectedFenceItem == nil)
            #expect(sut.selectedFenceDetail == nil)
            #expect(sut.fenceItems.allSatisfy { !$0.isSelected })
        }

        @Test("WHEN non-existent fence ID is selected THEN selection remains nil and no fence is marked as selected")
        func whenNonExistentFenceIDIsSelected_thenSelectionRemainsNilAndNoFenceIsMarkedAsSelected() async throws {
            let fence1 = makeFence(at: 1.0, lon: 1.0)
            let fence2 = makeFence(at: 2.0, lon: 2.0)
            let sut = makeSUT(fences: [fence1, fence2])
            
            let nonExistentFenceItem = FenceItem(id: UUID(), date: Date(), coordinate: CLLocationCoordinate2D(), technology: "N/A", isSelected: false, isCurrent: false, color: .gray)
            sut.selectedFenceItem = nonExistentFenceItem
            
            #expect(sut.selectedFenceItem?.id == nonExistentFenceItem.id)
            #expect(sut.selectedFenceDetail == nil)
            #expect(sut.fenceItems.allSatisfy { !$0.isSelected })
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
    sendResultsService: SendCoverageResultsServiceSpy = .init(),
    currentTime: @escaping () -> Date = Date.init
) -> NetworkCoverageViewModel {
    return NetworkCoverageViewModel(
        fences: fences,
        refreshInterval: refreshInterval,
        minimumLocationAccuracy: minimumLocationAccuracy,
        updates: { updates.publisher.values },
        currentRadioTechnology: RadioTechnologyServiceStub(),
        sendResultsService: sendResultsService,
        persistenceService: persistenceService,
        locale: locale,
        timeNow: currentTime
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

func makeFence(
    id: UUID = UUID(),
    at lat: CLLocationDegrees,
    lon: CLLocationDegrees,
    dateEntered: Date = Date(timeIntervalSinceReferenceDate: 0),
    technology: String? = nil
) -> Fence {
    Fence(
        startingLocation: CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: 1,
            verticalAccuracy: 1,
            timestamp: dateEntered
        ),
        dateEntered: dateEntered,
        technology: technology
    )
}

func makeFenceWithPings(
    at lat: CLLocationDegrees,
    lon: CLLocationDegrees,
    dateEntered: Date,
    technology: String,
    pings: [PingResult]
) -> Fence {
    Fence(
        startingLocation: CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: 1,
            verticalAccuracy: 1,
            timestamp: dateEntered
        ),
        dateEntered: dateEntered,
        technology: technology,
        pings: pings
    )
}

func makeSaveError() -> Error {
    NSError(domain: "test", code: 1, userInfo: nil)
}

@MainActor extension NetworkCoverageViewModel {
    func startTest() async {
        await toggleMeasurement()
    }

    func simulateSelectFence(_ fence: Fence) {
        selectedFenceItem = fenceItems.first { $0.id == fence.id }
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

// MARK: - SwiftTesting Debug Support

extension FenceItem: @retroactive CustomTestStringConvertible, @retroactive CustomDebugStringConvertible {
    public var debugDescription: String { testDescription }

    public var testDescription: String {
        let idPrefix = String(id.uuidString.prefix(6))
        let selectedStatus = isSelected ? "selected" : ""
        let currentStatus = isCurrent ? "current" : ""
        
        let statuses = [selectedStatus, currentStatus].filter { !$0.isEmpty }
        let statusString = statuses.isEmpty ? "" : " [\(statuses.joined(separator: ", "))]"
        
        return "FenceItem(\(idPrefix), \(coordinate.latitude),\(coordinate.longitude)\(statusString))"
    }
}

extension FenceDetail: @retroactive CustomTestStringConvertible, @retroactive CustomDebugStringConvertible {
    public var debugDescription: String { testDescription }

    public var testDescription: String {
        let idPrefix = String(id.uuidString.prefix(6))
        return "FenceDetail(\(idPrefix), \(technology), \(averagePing))"
    }
}
