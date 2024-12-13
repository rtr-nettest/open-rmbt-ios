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

// MARK: -

var backgroundActivity: CLBackgroundActivitySession?

struct LocationCoverage {
    struct Location {
        let latitude: Double
        let longitude: Double
    }

    let location: Location
}


@Observable @MainActor class NetworkCoverageViewModel {
    struct LocationItem: Identifiable {
        struct PingInfo {
            let pings: String
        }

        let id: String
        let coordinate: CLLocationCoordinate2D
        let distanceFromStart: String?
        let distanceFromPrevious: String?
        let technology: String

        var coordinateString: String {
            "\(coordinate.latitude)\n\(coordinate.longitude)"
        }
        var pingInfo: PingInfo {
            PingInfo(pings: pings
                .map { $0.error.map { _  in "err" } ?? "\($0.interval.milliseconds) ms" }
                .joined(separator: ", ")
            )
        }

        var averagePing: String { "\(Int(pings.map(\.interval).map(\.milliseconds).average)) ms" }

        var pings: [PingResult] = []
    }

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
    var minimumLocationAccuracy: CLLocationDistance = 5
    private(set) var isStarted = false
    private(set) var errorMessage: String?
    private(set) var locationsItems: [LocationItem] = [
        .init(
            id: "3",
            coordinate: .init(latitude: 37.7777777777777777, longitude: -123.7777777777777777),
            distanceFromStart: "230 m",
            distanceFromPrevious: "25 m",
            technology: "LTE",
            pings: [.init(interval: .milliseconds(123), error: nil)]
        ),
        .init(
            id: "2",
            coordinate: .init(latitude: 37.777777, longitude: -123.777777),
            distanceFromStart: "230 m",
            distanceFromPrevious: "25 m",
            technology: "LTE"
        ),
        .init(
            id: "1",
            coordinate: .init(latitude: 37.777777, longitude: -123.777777),
            distanceFromStart: "230 m",
            distanceFromPrevious: "25 m",
            technology: "LTE"
        ),
        .init(
            id: "0",
            coordinate: .init(latitude: 37.777777, longitude: -123.777777),
            distanceFromStart: "230 m",
            distanceFromPrevious: "25 m",
            technology: "LTE"
        )
    ]

    private(set) var locations: [CLLocation] = []
    private(set) var locationAccuracy = "N/A"
    private(set) var latestPing = "N/A"
    private(set) var latestTechnology = "N/A"

    @MainActor
    private var locationAreas: [LocationArea] = [] {
        didSet {
            var items = [LocationItem]()

            for i in locationAreas.indices {
                let current = locationAreas[i]
                let previous = i - 1 >= 0 ? locationAreas[i - 1] : nil

                items.append(LocationItem(area: current, previous: previous))
            }

            locationsItems = items
        }
    }

    private func start() async {
        guard !isStarted else { return }
        isStarted = true

        backgroundActivity = CLBackgroundActivitySession()

        let pingsSequence = pingMeasurementService.start().map(Update.ping)
        let locationsSequece = CLLocationUpdate.liveUpdates(.fitness).compactMap(Update.init(locationUpdate:))

        do {
            for try await update in merge(pingsSequence, locationsSequece) {
                guard isStarted else { break }

                switch update {
                case .ping(let pingUpdate):
                    latestPing = pingUpdate.error != nil ? "err" : "\(pingUpdate.interval.milliseconds) ms"

                    if var currentArea = locationAreas.last {
                        currentArea.append(ping: pingUpdate)
                        locationAreas[locationAreas.endIndex - 1] = currentArea
                    }

                case .location(let locationUpdate):
                    locations.append(locationUpdate)
                    locationAccuracy = String(format: "%.2f", locationUpdate.horizontalAccuracy)
                    latestTechnology = currentRadioTechnology() ?? "N/A"

                    guard locationUpdate.horizontalAccuracy <= minimumLocationAccuracy else {
                        continue
                    }

                    let currentArea = locationAreas.last
                    if var currentArea {
                        if currentArea.startingLocation.distance(from: locationUpdate) >= fenceRadius {
                            let newArea = LocationArea(startingLocation: locationUpdate, technology: latestTechnology)
                            locationAreas.append(newArea)
                        } else {
                            currentArea.append(location: locationUpdate)
                            currentArea.append(technology: latestTechnology)
                            locationAreas[locationAreas.endIndex - 1] = currentArea
                        }
                    } else {
                        let newArea = LocationArea(startingLocation: locationUpdate, technology: latestTechnology)
                        locationAreas.append(newArea)
//                        currentArea = newArea
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

        return radioAccessTechnology?.radioTechnologyDisplayValue
    }

    private func stop() {
        isStarted = false
        locationAccuracy = "N/A"
        latestPing = "N/A"
        latestTechnology = "N/A"
    }

    func toggleMeasurement() async {
        if !isStarted {
            await start()
        } else {
            stop()
        }
    }

//    private func processLocationUpdate(_ location: CLLocationUpdate.Updates.Element) {
//        guard let location = location.location else { return }
//
//        let initialLocation = locations.first
//        let previousLocation = locations.last
//        let distanceFromPrevious = previousLocation?.distance(from: location)
//
//        if (distanceFromPrevious ?? 0) > 20 {
//
//        } else {
//            
//        }
//
//        locations.append(location)
//
//        let locationItem = LocationItem(
//            id: "\(locations.count)",
//            coordinate: location.coordinate,
//            distanceFromStart: initialLocation.map { String(format: "%.1f m", $0.distance(from: location)) },
//            distanceFromPrevious: previousLocation.map { String(format: "%.1f m", $0.distance(from: location)) },
//            pings: []
//        )
//
//        if locationsItems.isEmpty {
//            locationsItems.append(locationItem)
//        } else {
//            locationsItems.insert(locationItem, at: 0)
//        }
//    }
}

extension NetworkCoverageViewModel.LocationItem {
    init(area: LocationArea, previous: LocationArea?) {
        let location = area.locations.last!
        let startLocation = area.startingLocation
        let previousLocation = previous?.locations.last

        self.init(
            id: area.id.uuidString,
            coordinate: startLocation.coordinate,
            distanceFromStart: String(format: "%.1f m", startLocation.distance(from: location)),
            distanceFromPrevious: previousLocation.map { String(format: "%.1f m", $0.distance(from: location)) },
            technology: area.technologies.last ?? "N/A",
            pings: area.pings
        )
    }
}

extension CLLocation: @retroactive Identifiable {
    public var id: String { "\(coordinate.latitude),\(coordinate.longitude)" }
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
