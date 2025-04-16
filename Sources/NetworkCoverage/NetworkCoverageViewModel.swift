//
//  NetworkCoverageViewModel.swift
//  RMBT
//
//  Created by Jiri Urbasek on 12/12/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import Foundation
import CoreLocation
import AsyncAlgorithms
import CoreTelephony

var backgroundActivity: CLBackgroundActivitySession?

@rethrows private protocol UpdateAsyncIteratorProtocol: AsyncIteratorProtocol where Element == NetworkCoverageViewModel.Update { }
@rethrows private protocol UpdateAsyncSequence: AsyncSequence where Element == NetworkCoverageViewModel.Update { }

extension AsyncMerge2Sequence: AsynchronousSequence where Element == NetworkCoverageViewModel.Update {}

@rethrows protocol PingsAsyncSequence: AsyncSequence where Element == PingResult { }
// TODO: decide if we need a protocol here or not
//protocol PingMeasurementService<Sequence> {
//    associatedtype Sequence: PingsAsyncSequence
//
//    func pings() -> Sequence
//}

protocol CurrentRadioTechnologyService {
    func technologyCode() -> String?
}

protocol SendCoverageResultsService {
    func send(areas: [LocationArea]) async throws
}

@Observable @MainActor class NetworkCoverageViewModel {
    enum Update {
        case ping(PingResult)
        case location(LocationUpdate)
    }

    private var initialLocation: CLLocation?

    var fenceRadius: CLLocationDistance = 20
    var minimumLocationAccuracy: CLLocationDistance = 10
    private(set) var isStarted = false
    private(set) var errorMessage: String?

    private(set) var locations: [CLLocation] = []

    private let refreshInterval: TimeInterval
    private var firstPingTimestamp: Date?
    private var pingResults: [PingResult] = []

    private(set) var locationAccuracy = "N/A"

    var latestPing: String {
        guard let startTimestamp = firstPingTimestamp else { return "N/A" }

        let lastTimestamp = pingResults
            .sorted { $0.timestamp < $1.timestamp }
            .last?.timestamp

        guard let lastTimestamp else { return "N/A" }

        var currentRefreshIntervalStartTimestamp = startTimestamp
        var lastCompletedRefreshIntervalStartTimestamp: Date?
        while currentRefreshIntervalStartTimestamp.addingTimeInterval(refreshInterval) < lastTimestamp {
            lastCompletedRefreshIntervalStartTimestamp = currentRefreshIntervalStartTimestamp
            currentRefreshIntervalStartTimestamp = currentRefreshIntervalStartTimestamp.addingTimeInterval(refreshInterval)
        }

        guard let lastCompletedRefreshIntervalStartTimestamp else {
            return "-"
        }
        let averagePing = pingResults
            .filter { $0.timestamp >= lastCompletedRefreshIntervalStartTimestamp && $0.timestamp < currentRefreshIntervalStartTimestamp }
            .compactMap { $0.interval }
            .map(\.milliseconds)
            .average

        return "\(Int(averagePing.rounded())) ms"
    }
    
    private(set) var latestTechnology = "N/A"

    private let currentRadioTechnology: any CurrentRadioTechnologyService
    private let sendResultsService: any SendCoverageResultsService
    private let updates: () -> any AsynchronousSequence<Update>

    @MainActor
    private(set) var locationAreas: [LocationArea]
    var selectedArea: LocationArea?
    var currentArea: LocationArea? { locationAreas.last }

    init(
        areas: [LocationArea] = [],
        refreshInterval: TimeInterval,
        updates: @escaping () -> some AsynchronousSequence<Update>,
        currentRadioTechnology: some CurrentRadioTechnologyService,
        sendResultsService: some SendCoverageResultsService
    ) {
        self.locationAreas = areas
        self.refreshInterval = refreshInterval
        self.currentRadioTechnology = currentRadioTechnology
        self.sendResultsService = sendResultsService
        self.updates = updates
    }

    convenience init(
        areas: [LocationArea] = [],
        refreshInterval: TimeInterval,
        pingMeasurementService: @escaping () -> some PingsAsyncSequence,
        locationUpdatesService: some LocationUpdatesService,
        currentRadioTechnology: some CurrentRadioTechnologyService,
        sendResultsService: some SendCoverageResultsService
    ) {
        self.init(
            areas: areas,
            refreshInterval: refreshInterval,
            updates: { merge(
                pingMeasurementService().map(Update.ping),
                locationUpdatesService.locations().map(Update.location)
            )},
            currentRadioTechnology: currentRadioTechnology,
            sendResultsService: sendResultsService
        )
    }

    private func iterate(_ sequence: some AsynchronousSequence<NetworkCoverageViewModel.Update>) async {
        do {
            for try await update in sequence {
                guard isStarted else { break }

                switch update {
                case .ping(let pingUpdate):
                    if firstPingTimestamp == nil {
                        firstPingTimestamp = pingUpdate.timestamp
                    }

                    pingResults.append(pingUpdate)

                    if var (area, idx) = locationAreas.area(at: pingUpdate.timestamp) {
                        area.append(ping: pingUpdate)
                        locationAreas[idx] = area
                    }
                case .location(let locationUpdate):
                    let location = locationUpdate.location
                    locations.append(location)
                    locationAccuracy = String(format: "%.2fm", location.horizontalAccuracy)
                    let currentRadioTechnology = currentRadioTechnology.technologyCode()
                    latestTechnology = currentRadioTechnology ?? "N/A"

                    guard isLocationPreciseEnough(location) else {
                        continue
                    }

                    let currentArea = currentArea
                    if var currentArea {
                        if currentArea.startingLocation.distance(from: location) >= fenceRadius {
                            let newArea = LocationArea(
                                startingLocation: location,
                                dateEntered: locationUpdate.timestamp,
                                technology: currentRadioTechnology
                            )

                            currentArea.exit(at: locationUpdate.timestamp)
                            locationAreas[locationAreas.endIndex - 1] = currentArea

                            locationAreas.append(newArea)
                        } else {
                            currentArea.append(location: location)
                            currentRadioTechnology.map { currentArea.append(technology: $0) }
                            locationAreas[locationAreas.endIndex - 1] = currentArea
                        }
                    } else {
                        locationAreas.append(.init(
                            startingLocation: location,
                            dateEntered: locationUpdate.timestamp,
                            technology: currentRadioTechnology
                        ))
                    }
                }
            }
        } catch {
            errorMessage = "There were some errors"
        }
    }

    private func start() async {
        guard !isStarted else { return }
        isStarted = true
        locationAreas.removeAll()
        locations.removeAll()

        backgroundActivity = CLBackgroundActivitySession()

        await iterate(updates())
    }

    private func stop() async {
        isStarted = false
        locationAccuracy = "N/A"
        latestTechnology = "N/A"

        if !locationAreas.isEmpty {
            do {
                try await sendResultsService.send(areas: locationAreas)
            } catch {
                // TODO: display error
            }
        }
    }

    func toggleMeasurement() async {
        if !isStarted {
            await start()
        } else {
            await stop()
        }
    }

    private func isLocationPreciseEnough(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy <= minimumLocationAccuracy
    }
}

private extension [LocationArea] {
    func area(at timestamp: Date) -> (LocationArea, Self.Index)? {
        let reversedAreas = reversed()
        let reversedIdx = reversedAreas.firstIndex {
            if let dateExited = $0.dateExited {
                $0.dateEntered < timestamp && dateExited > timestamp
            } else {
                $0.dateEntered < timestamp
            }
        }
        return reversedIdx.map {
            let baseIdx = index(before: $0.base)
            return (self[baseIdx], baseIdx)
        }
    }
}

extension Array where Element: BinaryInteger {
    /// The average value of all the items in the array
    var average: Double {
        if self.isEmpty {
            return 0.0
        } else {
            let sum = self.reduce(0, +)
            return Double(sum) / Double(self.count)
        }
    }
}

extension CLLocationCoordinate2D: @retroactive Equatable, @retroactive Hashable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
}
