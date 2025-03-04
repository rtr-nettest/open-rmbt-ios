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

@MainActor struct NetworkCoverageTests {
    @Test func whenInitializedWithNoPrefilledLocationAreas_thenAreasAreEmpty() async throws {
        let sut = makeSUT(areas: [])
        #expect(sut.fences.isEmpty)
    }

    @Test func whenReceivingFirstLocationUpdate_thenCreatesFirstArea() async throws {
        let location = CLLocation(latitude: 1.0, longitude: 1.0)
        let sut = makeSUT(updates: [.location(location)])
        await sut.startTest()

        #expect(sut.fences.count == 1)
        #expect(sut.fences.first?.locationItem.coordinate == location.coordinate)
    }
    
    @Test func whenReceivingMultiplePingsForOneLocation_thenCombinesPingTotalValue() async throws {
        let sut = makeSUT(updates: [
            makeLocationUpdate(.init(latitude: 1.0, longitude: 1.0), at: 1),
            makePingUpdate(interval: .milliseconds(10), at: 2),
            makePingUpdate(interval: .milliseconds(20), at: 3),
            makePingUpdate(interval: .milliseconds(26), at: 4),
            makeLocationUpdate(.init(latitude: 2.0, longitude: 1.0), at: 5),
        ])
        await sut.startTest()

        #expect(sut.fences.count == 2)
        #expect(sut.fences.first?.locationItem.averagePing == "18 ms")
        #expect(sut.fences.last?.locationItem.averagePing == "")
    }

    @Test func whenReceivingPingsForDifferentLocations_thenAssignesPingsToProperLocations() async throws {
        let sut = makeSUT(updates: [
            makeLocationUpdate(.init(latitude: 1.0, longitude: 1.0), at: 1),
            makePingUpdate(interval: .milliseconds(10), at: 2),
            makePingUpdate(interval: .milliseconds(20), at: 3),
            makeLocationUpdate(.init(latitude: 2.0, longitude: 1.0), at: 4),
            makePingUpdate(interval: .milliseconds(26), at: 5)
        ])
        await sut.startTest()

        #expect(sut.fences.count == 2)
        #expect(sut.fences.first?.locationItem.averagePing == "15 ms")
        #expect(sut.fences.last?.locationItem.averagePing == "26 ms")
    }
}

extension NetworkCoverageTests {
    struct NetworkCoverageScene {
        let viewModel: NetworkCoverageViewModel
        let presenter: NetworkCoverageViewPresenter
    }

    func makeSUT(
        areas: [LocationArea] = [],
        updates: [NetworkCoverageViewModel.Update] = [],
        locale: Locale = Locale(identifier: "en_US")
    ) -> NetworkCoverageScene {
        let viewModel = NetworkCoverageViewModel(
            areas: areas,
            updates: { updates.publisher.values },
            sendResultsService: SendCoverageResultsServiceSpy()
        )
        let presenter = NetworkCoverageViewPresenter(locale: locale)

        return .init(viewModel: viewModel, presenter: presenter)
    }

    func makeLocationUpdate(_ location: CLLocation, at timestampOffset: TimeInterval) -> NetworkCoverageViewModel.Update {
        .location(location)
    }

    func makePingUpdate(interval: Duration, at timestampOffset: TimeInterval) -> NetworkCoverageViewModel.Update {
        .ping(.init(result: .interval(interval), timestamp: Date(timeIntervalSince1970: timestampOffset)))
    }
}

@MainActor extension NetworkCoverageTests.NetworkCoverageScene {
    func startTest() async {
        await viewModel.toggleMeasurement()
    }

    var fences: [NetworkCoverageViewPresenter.Fence] { presenter.fences(from: viewModel) }
}

final class SendCoverageResultsServiceSpy: SendCoverageResultsService {
    private(set) var capturedSentAreas: [[LocationArea]] = []

    func send(areas: [LocationArea]) async throws {
        capturedSentAreas.append(areas)
    }
}

extension AsyncThrowingPublisher: @retroactive AsynchronousSequence {}
