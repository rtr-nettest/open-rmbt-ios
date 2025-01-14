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

protocol SendCoverageResultsService {
    func send(areas: [LocationArea]) async throws
}

@Observable @MainActor class NetworkCoverageViewModel {
    private enum Update {
        case ping(PingResult)
        case location(CLLocation)

        init?(locationUpdate: CLLocationUpdate.Updates.Element) {
            if let location = locationUpdate.location {
                self = .location(location)
            } else {
                return nil
            }
        }
    }

    private let pingMeasurementService = RESTPingMeasurementService(
        clock: ContinuousClock(),
        urlSession: URLSession(configuration: .ephemeral)
    )

    private var initialLocation: CLLocation?

    var fenceRadius: CLLocationDistance = 20
    var minimumLocationAccuracy: CLLocationDistance = 10
    private(set) var isStarted = false
    private(set) var errorMessage: String?

    private(set) var locations: [CLLocation] = []
    private(set) var locationAccuracy = "N/A"
    private(set) var latestPing = "N/A"
    private(set) var latestTechnology = "N/A"

    private let sendResultsService: any SendCoverageResultsService

    init(areas: [LocationArea] = [], sendResultsService: any SendCoverageResultsService = RMBTControlServer.shared) {
        self.locationAreas = areas
        self.sendResultsService = sendResultsService
    }

    @MainActor
    private(set) var locationAreas: [LocationArea]
    var selectedArea: LocationArea?
    var currentArea: LocationArea? { locationAreas.last }

    private func start() async {
        guard !isStarted else { return }
        isStarted = true
        locationAreas.removeAll()
        locations.removeAll()

        backgroundActivity = CLBackgroundActivitySession()

        let pingsSequence = pingMeasurementService.start().map(Update.ping)
        let locationsSequece = CLLocationUpdate.liveUpdates(.fitness).compactMap(Update.init(locationUpdate:))

        do {
            for try await update in merge(pingsSequence, locationsSequece) {
                guard isStarted else { break }

                switch update {
                case .ping(let pingUpdate):
                    latestPing = pingUpdate.displayValue

                    if
                        var currentArea = currentArea,
                        let lastLocation = locations.last,
                        isLocationPreciseEnough(lastLocation)
                    {
                        currentArea.append(ping: pingUpdate)
                        locationAreas[locationAreas.endIndex - 1] = currentArea
                    }

                case .location(let locationUpdate):
                    locations.append(locationUpdate)
                    locationAccuracy = String(format: "%.2fm", locationUpdate.horizontalAccuracy)
                    let currentRadioTechnology = currentRadioTechnology()
                    latestTechnology = currentRadioTechnology ?? "N/A"

                    guard isLocationPreciseEnough(locationUpdate) else {
                        continue
                    }

                    let currentArea = currentArea
                    if var currentArea {
                        if currentArea.startingLocation.distance(from: locationUpdate) >= fenceRadius {
                            let newArea = LocationArea(startingLocation: locationUpdate, technology: currentRadioTechnology)
                            locationAreas.append(newArea)
                        } else {
                            currentArea.append(location: locationUpdate)
                            currentRadioTechnology.map { currentArea.append(technology: $0) }
                            locationAreas[locationAreas.endIndex - 1] = currentArea
                        }
                    } else {
                        let newArea = LocationArea(startingLocation: locationUpdate, technology: currentRadioTechnology)
                        locationAreas.append(newArea)
                    }
                }
            }
        } catch {
            errorMessage = "There were some errors"
        }
    }

    private func currentRadioTechnology() -> String? {
        let netinfo = CTTelephonyNetworkInfo()
        var radioAccessTechnology: String?

        if let dataIndetifier = netinfo.dataServiceIdentifier {
            radioAccessTechnology = netinfo.serviceCurrentRadioAccessTechnology?[dataIndetifier]
        }
        return radioAccessTechnology
    }

    private func stop() async {
        isStarted = false
        locationAccuracy = "N/A"
        latestPing = "N/A"
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
