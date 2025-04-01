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
            makeLocationUpdate  (at: 1, lat: 1.0, lon: 1.0),
            makePingUpdate      (at: 2, ms: 10),
            makePingUpdate      (at: 3, ms: 20),
            makePingUpdate      (at: 4, ms: 26),
            makeLocationUpdate  (at: 5, lat: 2.0, lon: 1.0),
        ])
        await sut.startTest()

        #expect(sut.fences.count == 2)
        #expect(sut.fences.first?.locationItem.averagePing == "18 ms")
        #expect(sut.fences.last?.locationItem.averagePing == "")
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
            currentRadioTechnology: RadioTechnologyServiceStub(),
            sendResultsService: SendCoverageResultsServiceSpy()
        )
        let presenter = NetworkCoverageViewPresenter(locale: locale)

        return .init(viewModel: viewModel, presenter: presenter)
    }

    func makeLocationUpdate(at timestampOffset: TimeInterval, lat: CLLocationDegrees, lon: CLLocationDegrees) -> NetworkCoverageViewModel.Update {
        .location(.init(latitude: lat, longitude: lon))
    }

    func makePingUpdate(at timestampOffset: TimeInterval, ms: some BinaryInteger) -> NetworkCoverageViewModel.Update {
        .ping(.init(result: .interval(.milliseconds(ms)), timestamp: Date(timeIntervalSince1970: timestampOffset)))
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

final class RadioTechnologyServiceStub: CurrentRadioTechnologyService {
    func technologyCode() -> String? {
        nil
    }
}
