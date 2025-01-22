//
//  Test.swift
//  RMBTTest
//
//  Created by Jiri Urbasek on 13.01.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Testing
@testable import RMBT


// TODO: exaple test, not yet working

struct Test {
    @MainActor @Test func test() async throws {
        let pingMeasurements = PingMeasurementsStub()
        let locationUpdates = LocationUpdatesStub()
        let sut = NetworkCoverageViewModel(
            areas: [],
            pingMeasurementService: pingMeasurements,
            locationUpdatesService: locationUpdates,
            sendResultsService: SendCoverageResultsServiceSpy()
        )

        await withCheckedContinuation { continuation in
            Task {
                continuation.resume()
                await sut.toggleMeasurement()
            }
        }

        #expect(sut.locationAreas.isEmpty)

        locationUpdates.simulateReceivedLocation(.init(latitude: 1.00000000, longitude: 1.00000000))

        await Task.yield()
        await Task.yield()
        await Task.yield()
        await Task.yield()

        // fails due to asynchronous nature of async sequences, need to find a workaround
//        #expect(sut.locationAreas.count == 1)
    }
}

final class SendCoverageResultsServiceSpy: SendCoverageResultsService {
    private(set) var capturedSentAreas: [[LocationArea]] = []

    func send(areas: [LocationArea]) async throws {
        capturedSentAreas.append(areas)
    }
}

import Combine

extension AsyncThrowingPublisher: @retroactive PingsAsyncSequence where Element == PingResult {}

final class PingMeasurementsStub: PingMeasurementService {
    private let publisher = PassthroughSubject<PingResult, Never>()

    func pings() -> some PingsAsyncSequence {
        publisher.values
    }

    func simulateReceivedPing(_ pingResult: PingResult) {
        publisher.send(pingResult)
    }
}

import CoreLocation

extension AsyncThrowingPublisher: @retroactive LocationsAsyncSequence where Element == CLLocation {}

final class LocationUpdatesStub: LocationUpdatesService {
    private let publisher = PassthroughSubject<CLLocation, Never>()

    func locations() -> some LocationsAsyncSequence {
        publisher.values
    }

    func simulateReceivedLocation(_ location: CLLocation) {
        publisher.send(location)
    }
}
