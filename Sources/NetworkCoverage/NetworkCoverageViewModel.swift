//
//  NetworkCoverageViewModel.swift
//  RMBT
//
//  Created by Jiri Urbasek on 12/12/24.
//  Copyright 2024 appscape gmbh. All rights reserved.
//

import Foundation
import CoreLocation
import AsyncAlgorithms
import CoreTelephony
import SwiftUI
import SwiftData

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

protocol FencePersistenceService {
    func save(_ area: LocationArea) throws
    func clearAll() throws
}

struct FenceItem: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let coordinate: CLLocationCoordinate2D
    let technology: String
    let isSelected: Bool
    let isCurrent: Bool
    let color: Color
}

struct FenceDetail: Equatable, Identifiable {
    let id: UUID
    let date: String
    let technology: String
    let averagePing: String
    let color: Color
}

@Observable @MainActor class NetworkCoverageViewModel {
    enum Update {
        case ping(PingResult)
        case location(LocationUpdate)
    }

    // Private state
    @ObservationIgnored private var initialLocation: Date?
    @ObservationIgnored private let selectedItemDateFormatter: DateFormatter
    @ObservationIgnored private let refreshInterval: TimeInterval
    @ObservationIgnored private var firstPingTimestamp: Date?
    @ObservationIgnored private var pingResults: [PingResult] = [] {
        // TODO: optimize: no need to recompute latest ping each time `pingResults` is updated but based on `refreshInterval`
        // e.g. using timer calling `latestPingValue` periodicaly every `refreshInterval`. But pings might arrive with delay so need
        // to take also timeout interval for ping service into account?
        didSet {
            let updatedLatestPing = latestPingValue()
            if latestPing != updatedLatestPing {
                latestPing = updatedLatestPing
            }
        }
    }
    @ObservationIgnored private var selectedFence: FenceItem?
    @ObservationIgnored private var currentArea: LocationArea? { locationAreas.last }
    @ObservationIgnored private var inaccurateLocationsWindows: [InaccurateLocationWindow] = []

    // Dependencies
    @ObservationIgnored private let currentRadioTechnology: any CurrentRadioTechnologyService
    @ObservationIgnored private let sendResultsService: any SendCoverageResultsService
    @ObservationIgnored private let updates: () -> any AsynchronousSequence<Update>
    @ObservationIgnored private let persistenceService: any FencePersistenceService

    // Observable state
    var fenceRadius: CLLocationDistance = 20
    var minimumLocationAccuracy: CLLocationDistance
    private(set) var isStarted = false
    private(set) var errorMessage: String?
    private(set) var locations: [CLLocation] = []

    private(set) var latestPing: String = "N/A"
    private(set) var latestTechnology = "N/A"
    private(set) var locationAccuracy = "N/A"

    @MainActor
    private var locationAreas: [LocationArea] {
        didSet {
            // TODO: optimize: only very last fence is likely to need update, previous fences shoud remain untouched
            // so no need to mapp all `locationAreas` into fences, but can cache previous mappings and update only the very last one
            let newFences = locationAreas.map(fence)
            if fences != newFences {
                fences = newFences
            }
        }
    }

    private(set) var fences: [FenceItem] = []
    var selectedFenceID: FenceItem.ID? {
        didSet {
            selectedFenceDetail = locationAreas
                .first { $0.id == selectedFenceID }
                .map(fenceDetail)
        }
    }
    private(set) var selectedFenceDetail: FenceDetail?

    init(
        areas: [LocationArea] = [],
        refreshInterval: TimeInterval,
        minimumLocationAccuracy: CLLocationDistance,
        updates: @escaping () -> some AsynchronousSequence<Update>,
        currentRadioTechnology: some CurrentRadioTechnologyService,
        sendResultsService: some SendCoverageResultsService,
        persistenceService: some FencePersistenceService,
        locale: Locale
    ) {
        self.locationAreas = areas
        self.refreshInterval = refreshInterval
        self.minimumLocationAccuracy = minimumLocationAccuracy
        self.currentRadioTechnology = currentRadioTechnology
        self.sendResultsService = sendResultsService
        self.persistenceService = persistenceService
        self.updates = updates
        selectedItemDateFormatter = {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = locale
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium
            return dateFormatter
        }()
    }

    convenience init(
        areas: [LocationArea] = [],
        refreshInterval: TimeInterval,
        minimumLocationAccuracy: CLLocationDistance,
        pingMeasurementService: @escaping () -> some PingsAsyncSequence,
        locationUpdatesService: some LocationUpdatesService,
        currentRadioTechnology: some CurrentRadioTechnologyService,
        sendResultsService: some SendCoverageResultsService,
        persistenceService: some FencePersistenceService,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.init(
            areas: areas,
            refreshInterval: refreshInterval,
            minimumLocationAccuracy: minimumLocationAccuracy,
            updates: { merge(
                pingMeasurementService().map(Update.ping),
                locationUpdatesService.locations().map(Update.location)
            )},
            currentRadioTechnology: currentRadioTechnology,
            sendResultsService: sendResultsService,
            persistenceService: persistenceService,
            locale: locale
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
                    guard !wasInsideInaccurateLocationWindow(pingUpdate) else {
                        continue
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
                    latestTechnology = displayValue(forRadioTechnology: currentRadioTechnology ?? "N/A")

                    guard isLocationPreciseEnough(location) else {
                        startInaccurateLocationWidnowIfNeeded(at: location.timestamp)
                        continue
                    }
                    stopInaccurateLocationWindow(at: location.timestamp)

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

                            try? persistenceService.save(currentArea)

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
            // save last location unexited location area into the persistence layer
            if let lastArea = locationAreas.last, lastArea.dateExited == nil {
                try? persistenceService.save(lastArea)
            }

            do {
                try await sendResultsService.send(areas: locationAreas)
                // Clear persisted data after successful send
                try persistenceService.clearAll()
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

// functionality related to `InaccurateLocationWindow` = a time window in which location updates accuracy was below
// required threshold. In such situations, we want the received ping updates to be ignored, not be assigned to any fence
// since we do not know for sure, where we are located
private extension NetworkCoverageViewModel {
    struct InaccurateLocationWindow {
        let begin: Date
        private(set) var end: Date?

        init(begin: Date) {
            self.begin = begin
            self.end = nil
        }

        mutating func end(at endDate: Date) {
            self.end = endDate
        }
    }

    private func startInaccurateLocationWidnowIfNeeded(at date: Date) {
        if let lastInterval = inaccurateLocationsWindows.last, lastInterval.end == nil {
            // we are inside "ignore pings window", do nothing
        } else {
            // start new "ignore pings window"
            inaccurateLocationsWindows.append(.init(begin: date))
        }
    }

    private func stopInaccurateLocationWindow(at date: Date) {
        if let lastInterval = inaccurateLocationsWindows.last, lastInterval.end == nil {
            inaccurateLocationsWindows[inaccurateLocationsWindows.count - 1].end(at: date)
        }
    }

    private func wasInsideInaccurateLocationWindow(_ pingUpdate: PingResult) -> Bool {
        !inaccurateLocationsWindows
            .filter { ($0.end == nil || $0.end! > pingUpdate.timestamp) &&  $0.begin < pingUpdate.timestamp }
            .isEmpty
    }
}

private extension NetworkCoverageViewModel {
    private func fence(from area: LocationArea) -> FenceItem {
        .init(
            id: area.id,
            date: area.dateEntered,
            coordinate: area.startingLocation.coordinate,
            technology: area.significantTechnology?.radioTechnologyDisplayValue ?? "N/A",
            isSelected: selectedFence?.id == area.id,
            isCurrent: currentArea?.id == area.id,
            color: color(for: area.significantTechnology)
        )
    }

    private func fenceDetail(from area: LocationArea) -> FenceDetail {
        .init(
            id: area.id,
            date: selectedItemDateFormatter.string(from: area.dateEntered),
            technology: area.significantTechnology?.radioTechnologyDisplayValue ?? "N/A",
            averagePing: area.averagePing.map { "\($0) ms" } ?? "",
            color: color(for: area.significantTechnology)
        )
    }

    private func color(for technology: String?) -> Color {
        .init(uiColor: .byResultClass(technology?.radioTechnologyColorClassification))
    }

    private func latestPingValue() -> String {
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

    func displayValue(forRadioTechnology technology: String) -> String {
        technology.radioTechnologyDisplayValue ?? technology
    }
}

extension CLLocation: @retroactive Identifiable {
    public var id: String { "\(coordinate.latitude),\(coordinate.longitude)" }
}

extension PingResult {
    var displayValue: String {
        switch self.result {
        case .interval(let duration):
            "\(duration.milliseconds) ms"
        case .error:
            "err"
        }
    }
}

extension LocationArea {
    var significantTechnology: String? {
        technologies.last
    }
}

extension String {
    var radioTechnologyDisplayValue: String? {
        if
            let code = radioTechnologyCode,
            let celularCodeDescription = RMBTNetworkTypeConstants.cellularCodeDescriptionDictionary[code] {
            return celularCodeDescription.radioTechnologyDisplayValue
        } else {
            return nil
        }
    }

    var radioTechnologyColorClassification: Int? {
        if
            let code = radioTechnologyCode,
            let celularCodeDescription = RMBTNetworkTypeConstants.cellularCodeDescriptionDictionary[code] {
            return celularCodeDescription.radioTechnologyColorClassification
        } else {
            return nil
        }
    }
}

extension RMBTNetworkTypeConstants.NetworkType {
    var radioTechnologyDisplayValue: String {
        switch self {
        case .type2G: "2G"
        case .type3G: "3G"
        case .type4G: "4G"
        case .type5G, .type5GNSA, .type5GAvailable: "5G"
        case .wlan, .lan, .bluetooth, .unknown, .browser: "--"
        }
    }

    var radioTechnologyColorClassification: Int? {
        switch self {
        case .type2G: 1
        case .type3G: 2
        case .type4G: 3
        case .type5G, .type5GNSA, .type5GAvailable: 4
        case .wlan, .lan, .bluetooth, .unknown, .browser: nil
        }
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
