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
import MapKit
import SwiftData
import SwiftUI
import CoreTelephony
import Clocks

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

    @MainActor @Suite("Map Rendering")
    struct MapRenderingTests {
        private let equatorWideRegion = MKCoordinateRegion(center: .init(latitude: 0.0015, longitude: 0.0), span: .init(latitudeDelta: 0.05, longitudeDelta: 0.05))
        private let equatorTightRegion = MKCoordinateRegion(center: .init(latitude: 0.0015, longitude: 0.0), span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01))
        private let midRangeRegion = MKCoordinateRegion(center: .init(latitude: 0.005, longitude: 0.0), span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02))
        private let broadRegion = MKCoordinateRegion(center: .init(latitude: 0.05, longitude: 0.0), span: .init(latitudeDelta: 0.5, longitudeDelta: 0.5))
        private let farRegion = MKCoordinateRegion(center: .init(latitude: 0.25, longitude: 0.0), span: .init(latitudeDelta: 1.0, longitudeDelta: 1.0))
        private let nearRegion = MKCoordinateRegion(center: .init(latitude: 0.02, longitude: 0.0), span: .init(latitudeDelta: 0.2, longitudeDelta: 0.2))
        private let zeroSpanRegion = MKCoordinateRegion(center: .init(latitude: 0, longitude: 0), span: .init(latitudeDelta: 0, longitudeDelta: 0))

        private let viennaCoordinate = CLLocationCoordinate2D(latitude: 48.2082, longitude: 16.3738)
        private let bratislavaCoordinate = CLLocationCoordinate2D(latitude: 48.1486, longitude: 17.1077)

        @Test func whenZoomedOutBeyondThreshold_thenSwitchesToPolylineMode() async throws {
            let fences = [
                makeFence(lat: 0.0000, lon: 0.0, technology: "4G"),
                makeFence(lat: 0.0001, lon: 0.0, technology: "4G"),
                makeFence(lat: 0.0002, lon: 0.0, technology: "5G"),
                makeFence(lat: 0.0003, lon: 0.0, technology: "5G")
            ]

            let configuration = FencesRenderingConfiguration(
                maxCircleCountBeforePolyline: 4,
                minimumSpanForPolylineMode: 0.02,
                visibleRegionPaddingFactor: 1.0,
                cullsToVisibleRegion: false
            )

            let sut = makeSUT(fences: fences, renderingConfiguration: configuration)

            #expect(sut.mapRenderMode == .circles)
            #expect(sut.fencePolylineSegments.isEmpty)

            sut.updateVisibleRegion(equatorWideRegion)

            #expect(sut.mapRenderMode == .polylines)
            #expect(sut.fencePolylineSegments.count == 2)
            #expect(sut.fencePolylineSegments.map(\.technology) == ["4G", "5G"])
            expectFenceItems(sut.visibleFenceItems, match: fences)

            sut.updateVisibleRegion(equatorTightRegion)

            #expect(sut.mapRenderMode == .circles)
            #expect(sut.fencePolylineSegments.isEmpty)
            expectFenceItems(sut.visibleFenceItems, match: fences)
        }

        @Test func whenCullingEnabled_thenVisibleFenceItemsAreFilteredToRegion() async throws {
            let fences = [
                makeFence(lat: 0.0, lon: 0.0),
                makeFence(lat: 0.01, lon: 0.0),
                makeFence(lat: 0.20, lon: 0.0)
            ]

            let configuration = FencesRenderingConfiguration(
                maxCircleCountBeforePolyline: Int.max,
                minimumSpanForPolylineMode: 1.0,
                visibleRegionPaddingFactor: 1.0,
                cullsToVisibleRegion: true
            )

            let sut = makeSUT(fences: fences, renderingConfiguration: configuration)

            expectFenceItems(sut.visibleFenceItems, match: fences)

            sut.updateVisibleRegion(midRangeRegion)

            expectFenceItems(sut.visibleFenceItems, match: Array(fences.prefix(2)))

            sut.updateVisibleRegion(broadRegion)

            expectFenceItems(sut.visibleFenceItems, match: fences)
        }

        @Test func whenCullingEnabled_thenPolylineSegmentsOutsideRegionAreHidden() async throws {
            let fences = [
                makeFence(lat: 0.0, lon: 0.0, technology: "4G"),
                makeFence(lat: 0.0001, lon: 0.0, technology: "4G"),
                makeFence(lat: 0.5, lon: 0.0, technology: "5G"),
                makeFence(lat: 0.5001, lon: 0.0, technology: "5G")
            ]

            let configuration = FencesRenderingConfiguration(
                maxCircleCountBeforePolyline: 4,
                minimumSpanForPolylineMode: 0.2,
                visibleRegionPaddingFactor: 1.0,
                cullsToVisibleRegion: true
            )

            let sut = makeSUT(fences: fences, renderingConfiguration: configuration)

            sut.updateVisibleRegion(farRegion)

            #expect(sut.mapRenderMode == .polylines)
            #expect(sut.fencePolylineSegments.count == 2)

            sut.updateVisibleRegion(nearRegion)

            #expect(sut.mapRenderMode == .polylines)
            #expect(sut.fencePolylineSegments.count == 1)
            #expect(sut.fencePolylineSegments.first?.technology == "4G")
        }

        @Test func whenPolylineModeStable_thenSegmentIdentifiersRemainStableAcrossUpdates() async throws {
            let fences = [
                makeFence(lat: 0.0000, lon: 0.0, technology: "4G"),
                makeFence(lat: 0.0001, lon: 0.0, technology: "4G"),
                makeFence(lat: 0.0002, lon: 0.0, technology: "5G"),
                makeFence(lat: 0.0003, lon: 0.0, technology: "5G")
            ]

            let configuration = FencesRenderingConfiguration(
                maxCircleCountBeforePolyline: 4,
                minimumSpanForPolylineMode: 0.02,
                visibleRegionPaddingFactor: 1.0,
                cullsToVisibleRegion: false
            )

            let sut = makeSUT(fences: fences, renderingConfiguration: configuration)
            let region = equatorWideRegion

            sut.updateVisibleRegion(region)
            let firstIdentifiers = sut.fencePolylineSegments.map(\.id)

            sut.updateVisibleRegion(region)

            #expect(sut.fencePolylineSegments.map(\.id) == firstIdentifiers)
        }

        @Test func whenSameTechnologyDistanceExceedsGapThreshold_thenBreaksPolylineSegment() async throws {
            let radius: CLLocationDistance = 10
            let fences = [
                makeFence(lat: 0.0000, lon: 0.0, technology: "4G", radiusMeters: radius),
                makeFence(lat: 0.00009, lon: 0.0, technology: "4G", radiusMeters: radius),
                makeFence(lat: 0.00050, lon: 0.0, technology: "4G", radiusMeters: radius),
                makeFence(lat: 0.00059, lon: 0.0, technology: "4G", radiusMeters: radius)
            ]

            let configuration = FencesRenderingConfiguration(
                maxCircleCountBeforePolyline: 3,
                minimumSpanForPolylineMode: 0.0001,
                visibleRegionPaddingFactor: 1.0,
                cullsToVisibleRegion: false
            )

            let sut = makeSUT(fences: fences, renderingConfiguration: configuration)

            sut.updateVisibleRegion(equatorWideRegion)

            #expect(sut.mapRenderMode == .polylines)
            #expect(sut.fencePolylineSegments.count == 2)
            #expect(sut.fencePolylineSegments.allSatisfy { $0.technology == "4G" })

            let firstSegment = try #require(sut.fencePolylineSegments.first)
            let secondSegment = try #require(sut.fencePolylineSegments.last)

            #expect(firstSegment.coordinates.count == 2)
            #expect(secondSegment.coordinates.count == 2)
            #expect(firstSegment.coordinates.last == fences[1].startingLocation.coordinate)
            #expect(secondSegment.coordinates.first == fences[2].startingLocation.coordinate)
        }

        @Test func whenTechnologyChangesWithoutGap_thenSegmentsShareBoundaryCoordinate() async throws {
            let radius: CLLocationDistance = 10
            let fences = [
                makeFence(lat: 0.0000, lon: 0.0, technology: "4G", radiusMeters: radius),
                makeFence(lat: 0.00009, lon: 0.0, technology: "4G", radiusMeters: radius),
                makeFence(lat: 0.00018, lon: 0.0, technology: "5G", radiusMeters: radius)
            ]

            let configuration = FencesRenderingConfiguration(
                maxCircleCountBeforePolyline: 3,
                minimumSpanForPolylineMode: 0.0001,
                visibleRegionPaddingFactor: 1.0,
                cullsToVisibleRegion: false
            )

            let sut = makeSUT(fences: fences, renderingConfiguration: configuration)

            sut.updateVisibleRegion(equatorWideRegion)

            #expect(sut.mapRenderMode == .polylines)
            #expect(sut.fencePolylineSegments.count == 2)

            let firstSegment = try #require(sut.fencePolylineSegments.first)
            let secondSegment = try #require(sut.fencePolylineSegments.last)

            #expect(firstSegment.technology == "4G")
            #expect(secondSegment.technology == "5G")

            let boundaryCoordinate = try #require(firstSegment.coordinates.last)

            #expect(boundaryCoordinate == fences[1].startingLocation.coordinate)
            #expect(secondSegment.coordinates.first == boundaryCoordinate)
            #expect(secondSegment.coordinates.count == 2)
            #expect(secondSegment.coordinates.last == fences[2].startingLocation.coordinate)
            #expect(secondSegment.id.contains(fences[2].id.uuidString))
            #expect(!secondSegment.id.contains(fences[1].id.uuidString))
        }

        @Test func whenFenceRadiusIsZero_thenPolylineSegmentsStillRender() async throws {
            let fences = [
                makeFence(lat: 0.0000, lon: 0.0, technology: "4G", radiusMeters: 0),
                makeFence(lat: 0.00005, lon: 0.0, technology: "4G", radiusMeters: 0),
                makeFence(lat: 0.00010, lon: 0.0, technology: "5G", radiusMeters: 0),
                makeFence(lat: 0.00015, lon: 0.0, technology: "5G", radiusMeters: 0)
            ]

            let configuration = FencesRenderingConfiguration(
                maxCircleCountBeforePolyline: 3,
                minimumSpanForPolylineMode: 0.0001,
                visibleRegionPaddingFactor: 1.0,
                cullsToVisibleRegion: false
            )

            let sut = makeSUT(fences: fences, renderingConfiguration: configuration)

            sut.updateVisibleRegion(equatorWideRegion)

            #expect(sut.mapRenderMode == .polylines)
            #expect(sut.fencePolylineSegments.count == 2)
            #expect(sut.fencePolylineSegments.map(\.technology) == ["4G", "5G"])
        }

        @Test func whenInitialized_thenVisibleFenceItemsMatchFences() async throws {
            let fences = [
                makeFence(lat: viennaCoordinate.latitude, lon: viennaCoordinate.longitude),
                makeFence(lat: bratislavaCoordinate.latitude, lon: bratislavaCoordinate.longitude)
            ]

            let sut = makeSUT(fences: fences)

            expectFenceItems(sut.fenceItems, match: fences)
            expectFenceItems(sut.visibleFenceItems, match: fences)
            #expect(sut.mapRenderMode == .circles)
        }

        @Test func whenRegionWithZeroSpanReported_thenVisibleFencesStayVisible() async throws {
            let fences = [
                makeFence(lat: viennaCoordinate.latitude, lon: viennaCoordinate.longitude),
                makeFence(lat: bratislavaCoordinate.latitude, lon: bratislavaCoordinate.longitude)
            ]

            let sut = makeSUT(fences: fences)

            sut.updateVisibleRegion(zeroSpanRegion)

            expectFenceItems(sut.visibleFenceItems, match: fences)
            #expect(sut.mapRenderMode == .circles)
        }
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
            currentTime: { currentTime },
            maxTestDuration: { fourHoursInSeconds }
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
            currentTime: { currentTime },
            maxTestDuration: { 4 * 60 * 60 }
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
        @Test func whenStartedNewMeasurement_thenMarksSessionStartedWithoutTestUUID() async throws {
            let persistenceService = FencePersistenceServiceSpy()
            var dateNow = makeDate(offset: 0)
            let sut = makeSUT(
                updates: [makeLocationUpdate(at: 0, lat: 1.0, lon: 1.0)],
                persistenceService: persistenceService,
                currentTime: { dateNow }
            )

            dateNow = makeDate(offset: 10)
            await sut.startTest()

            let capturedMessages = await persistenceService.capturedMessages
            #expect(capturedMessages == [.sessionStarted(date: dateNow)])
        }

        @Test func whenReceivedSessionInitialization_thenAssignesTestUUIDAsSessionID() async throws {
            let persistenceService = FencePersistenceServiceSpy()
            let dateNow = makeDate(offset: 0)
            let sessionInitilalizedOffset: TimeInterval = 20
            let sessionID = "session-1"
            let sut = makeSUT(
                updates: [
                    makeLocationUpdate          (at: 1, lat: 1.0, lon: 1.0),
                    makeLocationUpdate          (at: 2, lat: 1.0, lon: 1.0000001),
                    makeLocationUpdate          (at: 3, lat: 2.0, lon: 1.0), // new fence starts -> previous gets saved
                    makeLocationUpdate          (at: 4, lat: 2.0, lon: 1.0000001),
                    makeLocationUpdate          (at: 5, lat: 3.0, lon: 1.0), // new fence starts -> previous gets saved
                    makeSessionInitializedUpdate(at: 6, sessionID: sessionID),
                    makeLocationUpdate          (at: 7, lat: 3.0, lon: 1.000001),
                    makeLocationUpdate          (at: 8, lat: 4.0, lon: 1.0),  // new fence starts -> previous gets saved
                ],
                persistenceService: persistenceService,
                currentTime: { dateNow }
            )

            await sut.startTest()

            let capturedMessages = await persistenceService.capturedMessages
            let fences = sut.fences
            try #require(fences.count == 4)

            #expect(capturedMessages == [
                .sessionStarted(date: dateNow),
                .save(fence: fences[0]),
                .save(fence: fences[1]),
                .assign(testUUID: sessionID, anchorDate: makeDate(offset: 6)),
                .save(fence: fences[2]),
            ])
        }

        @Test func whenRecordedFencesBeforeSessionInitialized_thenFencesAreStillSaved() async throws {
            let persistenceService = FencePersistenceServiceSpy()
            var dateNow = makeDate(offset: 0)
            let sessionInitilalizedOffset: TimeInterval = 20
            let sessionID = "session-1"
            let sut = makeSUT(
                updates: [
                    makeSessionInitializedUpdate(at: sessionInitilalizedOffset, sessionID: sessionID)
                ],
                persistenceService: persistenceService,
                currentTime: { dateNow }
            )

            dateNow = makeDate(offset: 10)
            await sut.startTest()

            let capturedMessages = await persistenceService.capturedMessages
            #expect(capturedMessages == [
                .sessionStarted(date: dateNow),
                .assign(testUUID: sessionID, anchorDate: makeDate(offset: sessionInitilalizedOffset))
            ])
        }
        @Test func whenStoppedMeasurement_thenMarksSessionFinalized() async throws {
            let sessionID = "session-finalize"
            let persistenceService = FencePersistenceServiceSpy()
            var dateNow = makeDate(offset: 0)
            let sut = makeSUT(
                updates: [
                    makeSessionInitializedUpdate(at: 1, sessionID: sessionID),
                    makeLocationUpdate          (at: 2, lat: 1.0, lon: 1.0),
                    makeLocationUpdate          (at: 3, lat: 1.0, lon: 1.000001)
                ],
                persistenceService: persistenceService,
                currentTime: { dateNow }
            )

            await sut.startTest()
            dateNow = makeDate(offset: 5)
            await sut.stopTest()

            let capturedMessages = await persistenceService.capturedMessages
            let savedFece = try #require(sut.fences.first)

            #expect(capturedMessages == [
                .sessionStarted(date: makeDate(offset: 0)),
                .assign(testUUID: sessionID, anchorDate: makeDate(offset: 1)),
                .save(fence: savedFece),
                .sessionFinalized(date: makeDate(offset: 5)),
                .deleteFinalizedNilUUIDSessions
            ])
        }

        @Test func whenSubsequentSessionInitialized_thenCreatesNewSession() async throws {
            let persistenceService = FencePersistenceServiceSpy()
            let uuid1 = "uuid-1"
            let uuid2 = "uuid-2"
            let dateNow = makeDate(offset: 0)
            let sut = makeSUT(
                updates: [
                    makeSessionInitializedUpdate(at: 1, sessionID: uuid1),
                    makeLocationUpdate          (at: 2, lat: 1, lon: 1),
                    makeSessionInitializedUpdate(at: 3, sessionID: uuid2)
                ],
                persistenceService: persistenceService,
                currentTime: { dateNow }
            )

            await sut.startTest()

            let capturedMessages = await persistenceService.capturedMessages
            #expect(capturedMessages == [
                .sessionStarted(date: dateNow),
                .assign(testUUID: uuid1, anchorDate: makeDate(offset: 1)),
                .assign(testUUID: uuid2, anchorDate: makeDate(offset: 3)),
            ])
        }

        @Test func whenStopMeasurement_thenSendsAllFencesOnce() async throws {
            let expectedTestUUID = "session-send"
            let persistenceService = FencePersistenceServiceSpy()
            let sendService = SendCoverageResultsServiceSpy()
            let sut = makeSUT(
                updates: [
                    makeLocationUpdate(at: 0, lat: 48.2082, lon: 16.3738),
                    makePingUpdate(at: 1, ms: 30),
                    makeLocationUpdate(at: 2, lat: 48.2084, lon: 16.3740)
                ],
                persistenceService: persistenceService,
                sendResultsService: sendService
            )

            await sut.startTest()
            let expectedFenceCount = sut.fenceItems.count

            await sut.stopTest()

            #expect(sendService.capturedSentFences == [sut.fences])
            #expect(sendService.capturedSentFences.first?.count == expectedFenceCount)
        }

        @Test func whenStop_andCurrentSessionHasNoUUID_thenPersistenceServiceDeletesFinalizedNilUUIDSessions() async throws {
            let persistenceService = FencePersistenceServiceSpy()
            var dateNow = Date(timeIntervalSinceReferenceDate: 0)
            let sut = makeSUT(
                updates: [makeLocationUpdate(at: 0, lat: 48.2082, lon: 16.3738)],
                persistenceService: persistenceService,
                currentTime: { dateNow }
            )

            dateNow = Date(timeIntervalSinceReferenceDate: 5)
            await sut.startTest()
            await Task.yield()
            dateNow = Date(timeIntervalSinceReferenceDate: 10)
            await sut.stopTest()

            let capturedMessages = await persistenceService.capturedMessages
            #expect(capturedMessages.contains(.deleteFinalizedNilUUIDSessions))
        }

        @Test func whenReceivingLocationUpdatesAndPings_thenPersistsFencesIntoPersistenceLayer() async throws {
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

            let savedFences = await persistenceService.capturedSavedFences

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
            let fences = [makeFence(lat: 1.0, lon: 1.0), makeFence(lat: 2.0, lon: 2.0)]
            let sut = makeSUT(fences: fences)

            #expect(sut.selectedFenceItem == nil)
            #expect(sut.selectedFenceDetail == nil)
            #expect(sut.fenceItems.map(\.isSelected) == [false, false])
        }

        @Test("WHEN valid fence ID is selected THEN fence is marked as selected and detail is populated")
        func whenValidFenceIDIsSelected_thenFenceIsMarkedAsSelectedAndDetailIsPopulated() async throws {
            let fence1 = makeFence(lat: 1.0, lon: 1.0)
            let fence2 = makeFence(
                lat: 2.0,
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
            #expect(sut.selectedFenceDetail?.color == Color(red: 0.694, green: 0.165, blue: 0.565)) // #b12a90
            #expect(sut.fenceItems.map(\.isSelected) == [false, true])
        }

        @Test("WHEN selection is changed to different fence THEN previous fence is deselected and new one is selected")
        func whenSelectionIsChangedToDifferentFence_thenPreviousFenceIsDeselectedAndNewOneIsSelected() async throws {
            let fence1 = makeFence(lat: 1.0, lon: 1.0)
            let fence2 = makeFence(lat: 2.0, lon: 2.0)
            let fence3 = makeFence(lat: 3.0, lon: 3.0)
            let sut = makeSUT(fences: [fence1, fence2, fence3])

            sut.simulateSelectFence(fence1)
            sut.simulateSelectFence(fence3)

            #expect(sut.fenceItems.map(\.isSelected) == [false, false, true])
        }

        @Test("WHEN selection is set to nil THEN all fences are deselected")
        func whenSelectionIsSetToNil_thenAllFencesAreDeselected() async throws {
            let fence1 = makeFence(lat: 1.0, lon: 1.0)
            let fence2 = makeFence(lat: 2.0, lon: 2.0)
            let sut = makeSUT(fences: [fence1, fence2])

            sut.simulateSelectFence(fence1)
            sut.selectedFenceItem = nil

            #expect(sut.selectedFenceItem == nil)
            #expect(sut.selectedFenceDetail == nil)
            #expect(sut.fenceItems.allSatisfy { !$0.isSelected })
        }

        @Test("WHEN non-existent fence ID is selected THEN selection remains nil and no fence is marked as selected")
        func whenNonExistentFenceIDIsSelected_thenSelectionRemainsNilAndNoFenceIsMarkedAsSelected() async throws {
            let fence1 = makeFence(lat: 1.0, lon: 1.0)
            let fence2 = makeFence(lat: 2.0, lon: 2.0)
            let sut = makeSUT(fences: [fence1, fence2])

            let nonExistentFenceItem = FenceItem(
                id: UUID(),
                date: Date(),
                coordinate: CLLocationCoordinate2D(),
                radiusMeters: 0,
                technology: "N/A",
                isSelected: false,
                isCurrent: false,
                color: .gray
            )
            sut.selectedFenceItem = nonExistentFenceItem

            #expect(sut.selectedFenceItem?.id == nonExistentFenceItem.id)
            #expect(sut.selectedFenceDetail == nil)
            #expect(sut.fenceItems.allSatisfy { !$0.isSelected })
        }
    }

    @MainActor @Suite("Inaccurate Location Warningy")
    struct InaccurateLocationWarningTests {
        @Test func whenTestNotStarted_thenGpsInaccurateLocationWarningIsHidden() async throws {
            let sut = makeSUT(updates: [])
            #expect(sut.warningPopups.isEmpty)
        }

        @Test func whenJustStartedAndDelayNotElapsed_thenInaccurateLocationWarningIsHidden() async throws {
            let clock = TestClock()
            let sut = makeSUT(updates: [], overlayDelay: 3.0, clock: clock)

            await sut.startTest()
            await clock.advance(by: .seconds(2.9))

            #expect(sut.warningPopups == [])
        }

        @Test func whenDelayElapsedAndNoLocationYet_thenInaccurateLocationWarningIsHidden() async throws {
            let clock = TestClock()
            let sut = makeSUT(updates: [], overlayDelay: 3.0, clock: clock)

            await sut.startTest()
            await clock.advance(by: .seconds(3.1))

            #expect(sut.warningPopups == [])
        }

        @Test func whenDelayElapsedAndLocationAccuracyIsBad_thenInaccurateLocationWarningIsShown() async throws {
            let minAccuracy: CLLocationDistance = 10
            let clock = TestClock()
            let sut = makeSUT(
                minimumLocationAccuracy: minAccuracy,
                updates: [
                    makeLocationUpdate(at: 0, lat: 1.0, lon: 1.0, accuracy: minAccuracy * 2)
                ],
                overlayDelay: 3.0,
                clock: clock
            )

            await sut.startTest()
            await clock.advance(by: .seconds(3.1))

            #expect(sut.warningPopups == [makeInaccurateLocationWarningPopup()])
        }

        @Test func whenDelayElapsedAndLocationAccuracyIsGood_thenInaccurateLocationWarningIsHidden() async throws {
            let minAccuracy: CLLocationDistance = 10
            let clock = TestClock()
            let sut = makeSUT(
                minimumLocationAccuracy: minAccuracy,
                updates: [
                    makeLocationUpdate(at: 0, lat: 1.0, lon: 1.0, accuracy: minAccuracy / 2)
                ],
                overlayDelay: 3.0,
                clock: clock
            )

            await sut.startTest()
            await clock.advance(by: .seconds(3.1))

            #expect(sut.warningPopups == [])
        }

        @Test func whenOverlayWouldBeShown_thenStoppingMeasurementHidesIt() async throws {
            let minAccuracy: CLLocationDistance = 10
            let clock = TestClock()
            let sut = makeSUT(
                minimumLocationAccuracy: minAccuracy,
                updates: [
                    makeLocationUpdate(at: 0, lat: 1.0, lon: 1.0, accuracy: minAccuracy * 2)
                ],
                overlayDelay: 3.0,
                clock: clock
            )

            await sut.startTest()
            await clock.advance(by: .seconds(3.1))

            #expect(sut.warningPopups == [makeInaccurateLocationWarningPopup()])

            await sut.stopTest()
            #expect(sut.warningPopups.isEmpty)
        }

        @Test func whenReceivedBadAfterGoodLocation_thenInaccurateLocationWarningIsShown() async throws {
            let minAccuracy: CLLocationDistance = 10
            let clock = TestClock()
            let sut = makeSUT(
                minimumLocationAccuracy: minAccuracy,
                updates: [
                    makeLocationUpdate(at: 0, lat: 1, lon: 1, accuracy: minAccuracy / 2),
                    makeLocationUpdate(at: 1, lat: 1.00001, lon: 1.00001, accuracy: minAccuracy / 3),
                    makeLocationUpdate(at: 2, lat: 1.00002, lon: 1.00002, accuracy: minAccuracy * 2)
                ],
                overlayDelay: 3.0,
                clock: clock
            )

            await sut.startTest()
            await clock.advance(by: .seconds(3.1))

            #expect(sut.warningPopups == [makeInaccurateLocationWarningPopup()])
        }

        @Test func whenGoodBadGood_thenInaccurateLocationWarningIsHidden() async throws {
            let minAccuracy: CLLocationDistance = 10
            let clock = TestClock()
            let sut = makeSUT(
                minimumLocationAccuracy: minAccuracy,
                updates: [
                    makeLocationUpdate(at: 0, lat: 1, lon: 1, accuracy: minAccuracy / 2),
                    makeLocationUpdate(at: 1, lat: 1.00001, lon: 1.00001, accuracy: minAccuracy * 2),
                    makeLocationUpdate(at: 2, lat: 1.00002, lon: 1.00002, accuracy: minAccuracy / 3)
                ],
                overlayDelay: 3.0,
                clock: clock
            )

            await sut.startTest()
            await clock.advance(by: .seconds(3.1))

            #expect(sut.warningPopups.isEmpty)
        }

        @Test func whenInsufficientAccuracyAutoStopIntervalPassedWithoutSufficientAccuracy_thenAutoStopsAndReportsReason() async throws {
            let minAccuracy: CLLocationDistance = 10
            let clock = TestClock()
            let timeout: TimeInterval = 30 * 60
            let sut = makeSUT(
                minimumLocationAccuracy: minAccuracy,
                updates: [
                    // Only inaccurate locations during the whole period
                    makeLocationUpdate(at: 0, lat: 1, lon: 1, accuracy: minAccuracy * 2),
                    makeLocationUpdate(at: 60, lat: 1, lon: 1, accuracy: minAccuracy * 3),
                    makeLocationUpdate(at: timeout - 10, lat: 1, lon: 1, accuracy: minAccuracy * 2),
                    makeLocationUpdate(at: timeout + 10, lat: 1, lon: 1, accuracy: minAccuracy / 2)
                ],
                currentTime: { Date(timeIntervalSinceReferenceDate: 0) },
                clock: clock,
                insufficientAccuracyAutoStopInterval: timeout
            )

            await sut.startTest()
            await clock.advance(by: .seconds(timeout))
            await clock.run()

            #expect(!sut.isStarted)
            #expect(sut.stopTestReasons == [.insufficientLocationAccuracy(duration: timeout)])
        }

        @Test func whenAccurateLocationArrivesBeforeTimeout_thenDoesNotAutoStop() async throws {
            let minAccuracy: CLLocationDistance = 10
            let clock = TestClock()
            let timeout: TimeInterval = 30 * 60
            let sut = makeSUT(
                minimumLocationAccuracy: minAccuracy,
                updates: [
                    makeLocationUpdate(at: 0, lat: 1, lon: 1, accuracy: minAccuracy * 2),
                    makeLocationUpdate(at: timeout - 10, lat: 1.00001, lon: 1.00001, accuracy: minAccuracy / 2)
                ],
                clock: clock,
                insufficientAccuracyAutoStopInterval: timeout
            )

            await sut.startTest()
            await clock.advance(by: .seconds(timeout))
            await clock.run()

            #expect(sut.isStarted)
            #expect(sut.stopTestReasons == [])
        }

        @Test func whenInaccurateLocationArrivesAfterAccurateOneBeforeTimeout_thenDoesNotAutoStop() async throws {
            let minAccuracy: CLLocationDistance = 10
            let clock = TestClock()
            let timeout: TimeInterval = 30 * 60
            let sut = makeSUT(
                minimumLocationAccuracy: minAccuracy,
                updates: [
                    makeLocationUpdate(at: 0, lat: 1, lon: 1, accuracy: minAccuracy * 2),
                    makeLocationUpdate(at: 60, lat: 1.00001, lon: 1.00001, accuracy: minAccuracy / 2),
                    makeLocationUpdate(at: timeout - 10, lat: 1.00001, lon: 1.00001, accuracy: minAccuracy * 2)
                ],
                overlayDelay: 0.0,
                clock: clock,
                insufficientAccuracyAutoStopInterval: timeout
            )

            await sut.startTest()
            await clock.advance(by: .seconds(timeout))

            #expect(sut.isStarted)
            #expect(sut.stopTestReasons == [])
        }
    }

    @MainActor @Suite("Wi‑Fi Connection Warning")
    struct WiFiConnectionWarningTests {
        @Test func whenOnCellular_thenMeasurementProcessesUpdatesAndNoWiFiWarning() async throws {
            let sut = makeSUT(updates: [
                makeNetworkTypeUpdate   (at: 0, type: .cellular),
                makeLocationUpdate      (at: 1, lat: 1.0, lon: 1.0),
                makePingUpdate          (at: 2, ms: 50)
            ])

            await sut.startTest()

            #expect(sut.fenceItems.count == 1)
            #expect(!sut.warningPopups.contains(makeWiFiWarningPopup()))
        }

        @Test func whenSwitchedToWiFi_thenShowWarningAndIgnoreIncomingUpdates() async throws {
            let sut = makeSUT(updates: [
                makeLocationUpdate      (at: 0, lat: 1.0, lon: 1.0),
                makePingUpdate          (at: 1, ms: 50),
                makeNetworkTypeUpdate   (at: 2, type: .wifi),
                // These should be ignored while on Wi‑Fi
                makeLocationUpdate      (at: 3, lat: 3.0, lon: 3.0),
                makePingUpdate          (at: 4, ms: 999)
            ])

            await sut.startTest()

            #expect(sut.warningPopups == [makeWiFiWarningPopup()])
            #expect(sut.fenceItems.count == 1)
            // Latest ping should remain unchanged (no completed refresh interval)
            #expect(sut.latestPing == "-")
            // Locations should be appended while on Wi‑Fi
            #expect(sut.locations.count == 2)
        }

        @Test func whenBackToCellular_thenHideWarningAndResumeProcessing() async throws {
            let sut = makeSUT(updates: [
                makeLocationUpdate      (at: 0, lat: 1.0, lon: 1.0),
                makeNetworkTypeUpdate   (at: 1, type: .wifi),
                // Ignored on Wi‑Fi
                makeLocationUpdate      (at: 2, lat: 3.0, lon: 3.0),
                makePingUpdate          (at: 3, ms: 999),
                // Switch back to cellular
                makeNetworkTypeUpdate   (at: 4, type: .cellular),
                // Should be processed again
                makeLocationUpdate      (at: 5, lat: 5.0, lon: 5.0),
                makePingUpdate          (at: 6, ms: 100)
            ])

            await sut.startTest()

            #expect(!sut.warningPopups.contains(makeWiFiWarningPopup()))
            #expect(sut.fenceItems.count == 2)
        }

        @Test func whenOnWiFiAndAccuracyIsBad_thenBothWiFiAndGpsWarningsAreShown() async throws {
            let clock = TestClock()
            let minAccuracy: CLLocationDistance = 10
            let sut = makeSUT(
                minimumLocationAccuracy: minAccuracy,
                updates: [
                    makeNetworkTypeUpdate   (at: 0, type: .wifi),
                    makeLocationUpdate      (at: 2, lat: 1.0, lon: 1.0, accuracy: minAccuracy * 10)
                ],
                overlayDelay: 0.1,
                clock: clock
            )

            await sut.startTest()
            await clock.advance(by: .seconds(0.2))

            #expect(sut.warningPopups.contains(makeWiFiWarningPopup()))
            #expect(sut.warningPopups.contains(makeInaccurateLocationWarningPopup()))
        }
        
        @Test func whenNotStarted_thenWiFiWarningIsNotDisplayed() async throws {
            let sut = makeSUT(updates: [
                makeNetworkTypeUpdate   (at: 0, type: .wifi),
                makeLocationUpdate      (at: 2, lat: 1.0, lon: 1.0)
            ])
            
            // Not started yet
            #expect(!sut.warningPopups.contains(makeWiFiWarningPopup()))
        }
        
        @Test func whenStartedOnWiFi_thenWarningAppearsImmediately() async throws {
            let sut = makeSUT(updates: [
                makeNetworkTypeUpdate(at: 0, type: .wifi)
            ])
            
            await sut.startTest()
            
            #expect(sut.warningPopups.contains(makeWiFiWarningPopup()))
        }
        
        @Test func whenMultipleNetworkSwitches_thenWarningTogglesCorrectly() async throws {
            let sut = makeSUT(updates: [
                makeLocationUpdate      (at: 0, lat: 1.0, lon: 1.0),
                makeNetworkTypeUpdate   (at: 1, type: .cellular),
                makeNetworkTypeUpdate   (at: 2, type: .wifi),
                makeNetworkTypeUpdate   (at: 3, type: .cellular),
                makeNetworkTypeUpdate   (at: 4, type: .wifi),
                makeLocationUpdate      (at: 5, lat: 2.0, lon: 2.0)
            ])
            
            await sut.startTest()
            
            #expect(sut.warningPopups.contains(makeWiFiWarningPopup()))
            #expect(sut.fenceItems.count == 1) // Only initial location processed
        }

        @Test func whenStayingOnWiFiBeyondInaccuracyTimeout_thenStillAutoStop() async throws {
            let minAccuracy: CLLocationDistance = 10
            let clock = TestClock()
            let timeout: TimeInterval = 30 * 60
            let sut = makeSUT(
                minimumLocationAccuracy: minAccuracy,
                updates: [
                    makeNetworkTypeUpdate   (at: 0, type: .wifi),
                    makeLocationUpdate      (at: 0, lat: 1.0, lon: 1.0, accuracy: minAccuracy * 2)
                ],
                overlayDelay: 0.0,
                clock: clock,
                insufficientAccuracyAutoStopInterval: timeout
            )

            await sut.startTest()
            await clock.advance(by: .seconds(timeout))

            #expect(!sut.isStarted)
            #expect(sut.stopTestReasons == [.insufficientLocationAccuracy(duration: timeout)])
        }

        @Test func whenNetworkConnectionIsUnknown_thenBehavesAsCellular() async throws {
            // Since we only have wifi/cellular enum, this tests the default behavior
            let sut = makeSUT(updates: [
                makeLocationUpdate  (at: 0, lat: 1.0, lon: 1.0),
                makePingUpdate      (at: 1, ms: 50)
            ])
            
            await sut.startTest()
            
            #expect(!sut.warningPopups.contains(makeWiFiWarningPopup()))
            #expect(sut.fenceItems.count == 1)
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
    currentTime: @escaping () -> Date = Date.init,
    overlayDelay: TimeInterval = 3.0,
    clock: some Clock<Duration> = ContinuousClock(),
    insufficientAccuracyAutoStopInterval: TimeInterval = 30 * 60,
    maxTestDuration: @escaping () -> TimeInterval = { 4 * 60 * 60 },
    renderingConfiguration: FencesRenderingConfiguration = .default
) -> NetworkCoverageViewModel {
    .init(
        fences: fences,
        refreshInterval: refreshInterval,
        minimumLocationAccuracy: minimumLocationAccuracy,
        locationInaccuracyWarningInitialDelay: overlayDelay,
        insufficientAccuracyAutoStopInterval: insufficientAccuracyAutoStopInterval,
        updates: { updates.publisher.values },
        currentRadioTechnology: RadioTechnologyServiceStub(),
        sendResultsService: sendResultsService,
        persistenceService: persistenceService,
        locale: locale,
        timeNow: currentTime,
        clock: clock,
        maxTestDuration: maxTestDuration,
        renderingConfiguration: renderingConfiguration
    )
}

private func expectFenceItems(
    _ items: [FenceItem],
    match fences: [Fence],
    sourceLocation location: SourceLocation = #_sourceLocation
) {
    let sortedItems = items.sorted { $0.id.uuidString < $1.id.uuidString }
    let sortedFences = fences.sorted { $0.id.uuidString < $1.id.uuidString }

    #expect(sortedItems.count == sortedFences.count, sourceLocation: location)

    for (item, fence) in zip(sortedItems, sortedFences) {
        #expect(item.id == fence.id, sourceLocation: location)
        #expect(item.coordinate.latitude == fence.startingLocation.coordinate.latitude, sourceLocation: location)
        #expect(item.coordinate.longitude == fence.startingLocation.coordinate.longitude, sourceLocation: location)
        let expectedTechnology = fence.significantTechnology.map { $0.radioTechnologyDisplayValue ?? $0 } ?? "N/A"
        #expect(item.technology == expectedTechnology, sourceLocation: location)
    }
}

func makeLocationUpdate(at timestampOffset: TimeInterval, lat: CLLocationDegrees, lon: CLLocationDegrees, accuracy: CLLocationAccuracy = 1) -> NetworkCoverageViewModel.Update {
    let timestamp = makeDate(offset: timestampOffset)
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
    .ping(.init(result: .interval(.milliseconds(ms)), timestamp: makeDate(offset: timestampOffset)))
}

func makeNetworkTypeUpdate(
    at timestampOffset: TimeInterval,
    type: NetworkTypeUpdate.NetworkConnectionType
) -> NetworkCoverageViewModel.Update {
    .networkType(.init(type: type, timestamp: makeDate(offset: timestampOffset)))
}

func makeSessionInitializedUpdate(
    at timestampOffset: TimeInterval,
    sessionID: String
) -> NetworkCoverageViewModel.Update {
    .sessionInitialized(.init(timestamp: makeDate(offset: timestampOffset), sessionID: sessionID))
}

func makeFence(
    id: UUID = UUID(),
    lat: CLLocationDegrees,
    lon: CLLocationDegrees,
    dateEntered: Date = makeDate(offset: 0),
    technology: String? = nil,
    pings: [PingResult] = [],
    radiusMeters: CLLocationDistance = 20
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
        pings: pings,
        radiusMeters: radiusMeters
    )
}

func makeSaveError() -> Error {
    NSError(domain: "test", code: 1, userInfo: nil)
}

func makeDate(offset: TimeInterval) -> Date {
    Date(timeIntervalSinceReferenceDate: offset)
}

func makeInaccurateLocationWarningPopup() -> NetworkCoverageViewModel.WarningPopupItem {
    .init(
        title: "Waiting for GPS",
        description: "Currently the location accuracy is insufficient. Please measure outdoors."
    )
}

func makeWiFiWarningPopup() -> NetworkCoverageViewModel.WarningPopupItem {
    .init(
        title: "Disable Wi‑Fi",
        description: "Please turn off Wi‑Fi to measure cellular coverage."
    )
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

final actor FencePersistenceServiceSpy: FencePersistenceService {
    enum CapturedMessage: Equatable {
        case save(fence: Fence)
        case sessionStarted(date: Date)
        case sessionFinalized(date: Date)
        case assign(testUUID: String, anchorDate: Date)
        case finalizeCurrentSession(date: Date)
        case deleteFinalizedNilUUIDSessions
    }

    private(set) var capturedSavedFences: [Fence] = []

    private(set) var capturedMessages: [CapturedMessage] = []

    func save(_ fence: Fence) throws {
        capturedSavedFences.append(fence)
        capturedMessages.append(.save(fence: fence))
    }

    func sessionStarted(at date: Date) throws {
        capturedMessages.append(.sessionStarted(date: date))
    }

    func sessionFinalized(at date: Date) throws {
        capturedMessages.append(.sessionFinalized(date: date))
    }

    func assignTestUUIDAndAnchor(_ uuid: String, anchorNow: Date) throws {
        capturedMessages.append(.assign(testUUID: uuid, anchorDate: anchorNow))
    }

    func finalizeCurrentSession(at date: Date) throws {
        capturedMessages.append(.finalizeCurrentSession(date: date))
    }

    func deleteFinalizedNilUUIDSessions() throws {
        capturedMessages.append(.deleteFinalizedNilUUIDSessions)
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

extension FencePersistenceServiceSpy.CapturedMessage: @retroactive CustomTestStringConvertible, @retroactive CustomDebugStringConvertible {
    public var debugDescription: String { testDescription }

    public var testDescription: String {
        switch self {

        case .save(fence: let fence):
            ".save(fence: \(fence))"
        case .sessionStarted(date: let date):
            ".sessionStarted(date: \(date))"
        case .sessionFinalized(date: let date):
            ".sessionFinalized(date: let \(date))"
        case .assign(testUUID: let testUUID, anchorDate: let anchorDate):
            ".assign(testUUID: \(testUUID), anchorDate: \(anchorDate))"
        case .finalizeCurrentSession(date: let date):
            ".finalizeCurrentSession(date: \(date))"
        case .deleteFinalizedNilUUIDSessions:
            ".deleteFinalizedNilUUIDSessions"
        }
    }
}
