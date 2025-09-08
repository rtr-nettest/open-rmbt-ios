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
import SwiftUI

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
    func send(fences: [Fence]) async throws
}

protocol FencePersistenceService {
    func save(_ fence: Fence) throws
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
    @ObservationIgnored private var iterationTask: Task<Void, Never>?
    @ObservationIgnored private var initialLocation: Date?
    @ObservationIgnored private(set) var selectedItemDateFormatter: DateFormatter
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
    @ObservationIgnored private var selectedFence: Fence?
    @ObservationIgnored private var inaccurateLocationsWindows: [InaccurateLocationWindow] = []
    @ObservationIgnored private var testStartTime: Date?
    @ObservationIgnored private let maxTestDuration: TimeInterval = 4 * 60 * 60 // 4 hours in seconds
    @ObservationIgnored private let timeNow: () -> Date
    @ObservationIgnored private let locationInaccuracyWarningInitialDelay: TimeInterval
    @ObservationIgnored private var locationInaccuracyWarningTask: Task<Void, Never>?
    @ObservationIgnored private var canCheckForLocationInaccuracyWarning: Bool = false

    // Dependencies
    @ObservationIgnored private let currentRadioTechnology: any CurrentRadioTechnologyService
    @ObservationIgnored private let sendResultsService: any SendCoverageResultsService
    @ObservationIgnored private let updates: () -> any AsynchronousSequence<Update>
    @ObservationIgnored private let persistenceService: any FencePersistenceService
    @ObservationIgnored private let clock: any Clock<Duration>

    @ObservationIgnored private(set) var fences: [Fence] {
        didSet {
            // TODO: optimize: only very last fence is likely to need update, previous fences shoud remain untouched
            // so no need to mapp all `fences` into fences items, but can cache previous mappings and update only the very last one
            let newFences = fences.map(fenceItem)
            if fenceItems != newFences {
                fenceItems = newFences
            }
        }
    }

    @ObservationIgnored private var currentFence: Fence? { fences.last }

    // Observable state
    var fenceRadius: CLLocationDistance = 20
    var minimumLocationAccuracy: CLLocationDistance
    private(set) var isStarted = false
    private(set) var errorMessage: String?
    private(set) var locations: [CLLocation] = []

    private(set) var latestPing: String = "N/A"
    private(set) var latestTechnology = "N/A"
    private(set) var locationAccuracy = "N/A"
    private(set) var fenceItems: [FenceItem] = []

    private(set) var warningPopups: [WarningPopupItem] = []

    var selectedFenceItem: FenceItem? {
        didSet {
            selectedFence = selectedFenceItem.flatMap { selectedItem in
                fences.first { $0.id == selectedItem.id }
            }
            selectedFenceDetail = selectedFence.map {
                .init(fence: $0, selectedItemDateFormatter: selectedItemDateFormatter)
            }
            // Recreate fenceItems to update selection state
            fenceItems = fences.map(fenceItem)
        }
    }
    private(set) var selectedFenceDetail: FenceDetail?
    
    var currentUserLocation: CLLocation? { locations.last }

    init(
        fences: [Fence] = [],
        refreshInterval: TimeInterval,
        minimumLocationAccuracy: CLLocationDistance,
        locationInaccuracyWarningInitialDelay: TimeInterval,
        updates: @escaping @Sendable () -> some AsynchronousSequence<Update>,
        currentRadioTechnology: some CurrentRadioTechnologyService,
        sendResultsService: some SendCoverageResultsService,
        persistenceService: some FencePersistenceService,
        locale: Locale,
        timeNow: @escaping () -> Date = Date.init,
        clock: some Clock<Duration>
    ) {
        self.fences = fences
        self.refreshInterval = refreshInterval
        self.minimumLocationAccuracy = minimumLocationAccuracy
        self.locationInaccuracyWarningInitialDelay = locationInaccuracyWarningInitialDelay
        self.currentRadioTechnology = currentRadioTechnology
        self.sendResultsService = sendResultsService
        self.persistenceService = persistenceService
        self.updates = updates
        self.timeNow = timeNow
        self.clock = clock

        selectedItemDateFormatter = {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = locale
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium
            return dateFormatter
        }()

        if !fences.isEmpty {
            self.fenceItems = fences.map(fenceItem)
        }
    }

    convenience init(
        fences: [Fence] = [],
        refreshInterval: TimeInterval,
        minimumLocationAccuracy: CLLocationDistance,
        locationInaccuracyWarningInitialDelay: TimeInterval,
        pingMeasurementService: @escaping () -> some PingsAsyncSequence,
        locationUpdatesService: some LocationUpdatesService,
        currentRadioTechnology: some CurrentRadioTechnologyService,
        sendResultsService: some SendCoverageResultsService,
        persistenceService: some FencePersistenceService,
        locale: Locale = .autoupdatingCurrent,
        clock: some Clock<Duration>
    ) {
        self.init(
            fences: fences,
            refreshInterval: refreshInterval,
            minimumLocationAccuracy: minimumLocationAccuracy,
            locationInaccuracyWarningInitialDelay: locationInaccuracyWarningInitialDelay,
            updates: { merge(
                pingMeasurementService().map { .ping($0) },
                locationUpdatesService.locations().map { .location($0) }
            )},
            currentRadioTechnology: currentRadioTechnology,
            sendResultsService: sendResultsService,
            persistenceService: persistenceService,
            locale: locale,
            clock: clock
        )
    }

    private func iterate(_ sequence: some AsynchronousSequence<NetworkCoverageViewModel.Update>) async {
        do {
            for try await update in sequence {
                try Task.checkCancellation()
                guard isStarted else { break }

                if let startTime = testStartTime, timeNow().timeIntervalSince(startTime) >= maxTestDuration {
                    await stop()
                    break
                }

                await processUpdate(update)
            }
        } catch is CancellationError {
            // Expected cancellation - no error
            return
        } catch {
            errorMessage = "Network coverage measurement error: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func processUpdate(_ update: Update) async {
        switch update {
        case .ping(let pingUpdate):
            if firstPingTimestamp == nil {
                firstPingTimestamp = pingUpdate.timestamp
            }
            guard !wasInsideInaccurateLocationWindow(pingUpdate) else {
                return
            }
            pingResults.append(pingUpdate)

            if var (fence, idx) = fences.fence(at: pingUpdate.timestamp) {
                fence.append(ping: pingUpdate)
                fences[idx] = fence
            }
            
        case .location(let locationUpdate):
            let location = locationUpdate.location
            locations.append(location)
            locationAccuracy = String(format: "%.2fm", location.horizontalAccuracy)
            let currentRadioTechnology = currentRadioTechnology.technologyCode()
            latestTechnology = displayValue(forRadioTechnology: currentRadioTechnology ?? "N/A")

            guard isLocationPreciseEnough(location) else {
                startInaccurateLocationWidnowIfNeeded(at: location.timestamp)
                checkForLocationInaccuracyWarning(location: location)
                return
            }
            stopInaccurateLocationWindow(at: location.timestamp)
            warningPopups.removeAll { $0 == .inaccurateLocationWarning }

            // Handle fence logic...
            let currentFence = currentFence
            if var currentFence {
                if currentFence.startingLocation.distance(from: location) >= fenceRadius {
                    let newFence = Fence(
                        startingLocation: location,
                        dateEntered: locationUpdate.timestamp,
                        technology: currentRadioTechnology
                    )

                    currentFence.exit(at: locationUpdate.timestamp)
                    fences[fences.endIndex - 1] = currentFence

                    try? persistenceService.save(currentFence)

                    fences.append(newFence)
                } else {
                    currentFence.append(location: location)
                    currentRadioTechnology.map { currentFence.append(technology: $0) }
                    fences[fences.endIndex - 1] = currentFence
                }
            } else {
                fences.append(.init(
                    startingLocation: location,
                    dateEntered: locationUpdate.timestamp,
                    technology: currentRadioTechnology
                ))
            }
        }
    }

    private func start() async {
        guard !isStarted else { return }
        isStarted = true
        testStartTime = timeNow()
        fences.removeAll()
        locations.removeAll()
        canCheckForLocationInaccuracyWarning = false

        await BackgroundActivityActor.shared.startActivity()

        locationInaccuracyWarningTask = Task { @MainActor in
            try? await clock.sleep(for: .seconds(locationInaccuracyWarningInitialDelay))

            canCheckForLocationInaccuracyWarning = true
            locations.last.map(checkForLocationInaccuracyWarning)
        }

        iterationTask = Task { @MainActor in
            await iterate(updates())
        }
        await iterationTask?.value
    }

    private func stop() async {
        isStarted = false
        testStartTime = nil
        locationAccuracy = "N/A"
        latestTechnology = "N/A"
        warningPopups.removeAll()
        
        // Cancel async sequences
        iterationTask?.cancel()
        iterationTask = nil
        locationInaccuracyWarningTask?.cancel()
        locationInaccuracyWarningTask = nil
        
        await BackgroundActivityActor.shared.stopActivity()
        
        // Handle saving and sending results...
        if !fences.isEmpty {
            if var lastFence = fences.last, lastFence.dateExited == nil {
                lastFence.exit(at: timeNow())
                fences[fences.endIndex - 1] = lastFence
                try? persistenceService.save(lastFence)
            }
            
            do {
                try await sendResultsService.send(fences: fences)
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
    
    deinit {
        iterationTask?.cancel()
        Task {
            await BackgroundActivityActor.shared.stopActivity()
        }
        locationInaccuracyWarningTask?.cancel()
    }

    private func isLocationPreciseEnough(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy <= minimumLocationAccuracy
    }
}

@MainActor extension NetworkCoverageViewModel {
    func startTest() async {
        await toggleMeasurement()
    }
    
    func stopTest() async {
        if isStarted {
            await toggleMeasurement()
        }
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

// Functionality related to displaying Warning Popups
// - when GPS location is not accurate enough
// - when user is on WiFi network
extension NetworkCoverageViewModel {
    struct WarningPopupItem: Identifiable, Equatable {
        var id: String { title + description }
        let title: String
        let description: String

        static var inaccurateLocationWarning: Self {
            .init(
                title: "Waiting for GPS",
                description: "Currently the location accuracy is insufficient. Please measure outdoors."
            )
        }
    }

    private func checkForLocationInaccuracyWarning(location: CLLocation) {
        if
            isStarted,
            canCheckForLocationInaccuracyWarning,
            !isLocationPreciseEnough(location),
            !warningPopups.contains(where: { $0 == .inaccurateLocationWarning } )
        {
            warningPopups.append(.inaccurateLocationWarning)
        }
    }
}

private extension NetworkCoverageViewModel {
    private func fenceItem(from fence: Fence) -> FenceItem {
        .init(
            id: fence.id,
            date: fence.dateEntered,
            coordinate: fence.startingLocation.coordinate,
            technology: fence.significantTechnology.map(displayValue) ?? "N/A",
            isSelected: selectedFenceItem?.id == fence.id,
            isCurrent: currentFence?.id == fence.id,
            color: Color(technology: fence.significantTechnology?.radioTechnologyDisplayValue)
        )
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
}

extension RMBTNetworkTypeConstants.NetworkType {
    var radioTechnologyDisplayValue: String {
        switch self {
        case .type2G: "2G"
        case .type3G: "3G"
        case .type4G: "4G"
        case .type5G, .type5GAvailable: "5G SA"
        case .type5GNSA: "5G NSA"
        case .wlan, .lan, .bluetooth, .unknown, .browser: "--"
        }
    }
}

private extension [Fence] {
    func fence(at timestamp: Date) -> (Fence, Self.Index)? {
        let reversedFences = reversed()
        let reversedIdx = reversedFences.firstIndex {
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

extension FenceDetail {
    init(fence: Fence, selectedItemDateFormatter: DateFormatter) {
        id = fence.id
        date = selectedItemDateFormatter.string(from: fence.dateEntered)
        technology = fence.significantTechnology?.radioTechnologyDisplayValue ?? "N/A"
        averagePing = fence.averagePing.map { "\($0) ms" } ?? ""
        color = Color(technology: fence.significantTechnology?.radioTechnologyDisplayValue)
    }
}

extension Color {
    /// The `technology` should be  String value produced by `RMBTNetworkTypeConstants.NetworkType.radioTechnologyDisplayValue`
    init(technology: String?) {
        switch technology {
        case "2G":
            self.init(hex: "#fca636")
        case "3G":
            self.init(hex: "#e16462")
        case "4G":
            self.init(hex: "#b12a90")
        case "5G NSA":
            self.init(hex: "#6a00a8")
        case "5G SA":
            self.init(hex: "#0d0887")
        default:
            self.init(hex: "#d9d9d9")
        }
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}


