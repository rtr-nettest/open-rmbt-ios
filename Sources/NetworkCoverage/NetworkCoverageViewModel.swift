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
import MapKit

// Standalone reason type for why a coverage test was stopped
enum StopTestReason: Equatable, Hashable {
    case insufficientLocationAccuracy(duration: TimeInterval)
}

extension AsyncMerge2Sequence: AsynchronousSequence where Element == NetworkCoverageViewModel.Update {}

@rethrows protocol PingsAsyncSequence: AsyncSequence where Element == PingResult { }

protocol CurrentRadioTechnologyService {
    func technologyCode() -> String?
}

protocol NetworkConnectionTypeUpdatesService: Sendable {
    associatedtype SequenceType: AsyncSequence where SequenceType.Element == NetworkTypeUpdate, SequenceType: Sendable
    func networkConnectionTypes() -> SequenceType
}

protocol SendCoverageResultsService {
    func send(fences: [Fence]) async throws
}

protocol FencePersistenceService {
    func save(_ fence: Fence) throws
    func sessionStarted(at date: Date) throws
    func sessionFinalized(at date: Date) throws
}

struct FenceItem: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let coordinate: CLLocationCoordinate2D
    let radiusMeters: CLLocationDistance
    let technology: String
    let isSelected: Bool
    let isCurrent: Bool
    let color: Color
}

enum FencesRenderMode: Equatable {
    case circles
    case polylines
}

struct FencePolylineSegment: Identifiable, Equatable {
    typealias ID = String

    let id: ID
    let technology: String
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
}

/// Configuration that tunes how fences are rendered on the map.
///
/// All values are deterministic to keep SwiftUI diffing stable and
/// should be adjusted carefully because they directly affect
/// performance on dense coverage measurements.
struct FencesRenderingConfiguration {
    /// Maximum number of circle annotations that can be rendered before switching to polylines.
    /// Lower values trade detail for better rendering performance in zoomed-out states.
    let maxCircleCountBeforePolyline: Int
    /// Minimum map span (in degrees) that must be visible before polylines are allowed.
    /// This avoids switching to polylines while the user is zoomed in very closely.
    let minimumSpanForPolylineMode: CLLocationDegrees
    /// Multiplier applied to the visible region when deciding which fences remain rendered.
    /// Padding helps prevent hard culling when the user pans slightly.
    let visibleRegionPaddingFactor: Double
    /// Toggles whether fences outside the padded region should be filtered out.
    let cullsToVisibleRegion: Bool

    /// Default rendering thresholds tuned for history detail and live measurement screens.
    static let `default` = FencesRenderingConfiguration(
        maxCircleCountBeforePolyline: 60,
        minimumSpanForPolylineMode: 0.03,
        visibleRegionPaddingFactor: 1.2,
        cullsToVisibleRegion: true
    )
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
        case networkType(NetworkTypeUpdate)
    }

    // Private state
    @ObservationIgnored private var iterationTask: Task<Void, Never>?
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
    @ObservationIgnored private let maxTestDuration: () -> TimeInterval
    @ObservationIgnored private let timeNow: () -> Date
    @ObservationIgnored private let locationInaccuracyWarningInitialDelay: TimeInterval
    @ObservationIgnored private var locationInaccuracyWarningTask: Task<Void, Never>?
    @ObservationIgnored private var canCheckForLocationInaccuracyWarning: Bool = false
    @ObservationIgnored private let insufficientAccuracyAutoStopInterval: TimeInterval
    @ObservationIgnored private var autoStopDueToInaccuracyTask: Task<Void, Never>?
    @ObservationIgnored private var hasEverHadAccurateLocation: Bool = false
    @ObservationIgnored private var isOnWiFi: Bool = false

    // Dependencies
    @ObservationIgnored private let currentRadioTechnology: any CurrentRadioTechnologyService
    @ObservationIgnored private let sendResultsService: any SendCoverageResultsService
    @ObservationIgnored private let updates: () -> any AsynchronousSequence<Update>
    @ObservationIgnored private let persistenceService: any FencePersistenceService
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let ipVersionProvider: () -> IPVersion?
    @ObservationIgnored private let connectionsCountProvider: () -> Int
    @ObservationIgnored private let renderingConfiguration: FencesRenderingConfiguration
    @ObservationIgnored private var visibleRegion: MKCoordinateRegion?
    @ObservationIgnored private var isUpdatingRenderedFences = false

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
    private(set) var fenceItems: [FenceItem] = [] {
        didSet { updateRenderedFencesIfNeeded() }
    }
    private(set) var visibleFenceItems: [FenceItem] = []
    private(set) var fencePolylineSegments: [FencePolylineSegment] = []
    private(set) var mapRenderMode: FencesRenderMode = .circles
    private(set) var connectionFragmentsCount: Int = 1

    private(set) var warningPopups: [WarningPopupItem] = []
    private(set) var stopTestReasons: [StopTestReason] = []

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

    func updateVisibleRegion(_ region: MKCoordinateRegion?) {
        visibleRegion = region.flatMap { region in
            guard region.span.latitudeDelta > 0, region.span.longitudeDelta > 0 else { return nil }
            return region
        }
        updateRenderedFencesIfNeeded()
    }

    init(
        fences: [Fence] = [],
        refreshInterval: TimeInterval,
        minimumLocationAccuracy: CLLocationDistance,
        locationInaccuracyWarningInitialDelay: TimeInterval,
        insufficientAccuracyAutoStopInterval: TimeInterval,
        updates: @escaping @Sendable () -> some AsynchronousSequence<Update>,
        currentRadioTechnology: some CurrentRadioTechnologyService,
        sendResultsService: some SendCoverageResultsService,
        persistenceService: some FencePersistenceService,
        locale: Locale,
        timeNow: @escaping () -> Date = Date.init,
        clock: some Clock<Duration>,
        maxTestDuration: @escaping () -> TimeInterval,
        ipVersionProvider: @escaping () -> IPVersion? = { nil },
        connectionsCountProvider: @escaping () -> Int = { 1 },
        renderingConfiguration: FencesRenderingConfiguration = .default
    ) {
        self.refreshInterval = refreshInterval
        self.minimumLocationAccuracy = minimumLocationAccuracy
        self.locationInaccuracyWarningInitialDelay = locationInaccuracyWarningInitialDelay
        self.insufficientAccuracyAutoStopInterval = insufficientAccuracyAutoStopInterval
        self.currentRadioTechnology = currentRadioTechnology
        self.sendResultsService = sendResultsService
        self.persistenceService = persistenceService
        self.updates = updates
        self.timeNow = timeNow
        self.clock = clock
        self.maxTestDuration = maxTestDuration
        self.ipVersionProvider = ipVersionProvider
        self.connectionsCountProvider = connectionsCountProvider
        self.renderingConfiguration = renderingConfiguration

        selectedItemDateFormatter = {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = locale
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium
            return dateFormatter
        }()

        self.fences = fences

        if !fences.isEmpty {
            let initialFenceItems = fences.map(fenceItem)
            fenceItems = initialFenceItems
            visibleFenceItems = initialFenceItems
            updateRenderedFences()
        }
    }

    convenience init(
        fences: [Fence] = [],
        refreshInterval: TimeInterval,
        minimumLocationAccuracy: CLLocationDistance,
        locationInaccuracyWarningInitialDelay: TimeInterval,
        insufficientAccuracyAutoStopInterval: TimeInterval,
        pingMeasurementService: @escaping () -> some PingsAsyncSequence,
        locationUpdatesService: some LocationUpdatesService,
        networkConnectionUpdatesService: some NetworkConnectionTypeUpdatesService,
        currentRadioTechnology: some CurrentRadioTechnologyService,
        sendResultsService: some SendCoverageResultsService,
        persistenceService: some FencePersistenceService,
        locale: Locale = .autoupdatingCurrent,
        clock: some Clock<Duration>,
        maxTestDuration: @escaping () -> TimeInterval,
        ipVersionProvider: @escaping () -> IPVersion? = { nil },
        connectionsCountProvider: @escaping () -> Int = { 1 },
        renderingConfiguration: FencesRenderingConfiguration = .default
    ) {
        self.init(
            fences: fences,
            refreshInterval: refreshInterval,
            minimumLocationAccuracy: minimumLocationAccuracy,
            locationInaccuracyWarningInitialDelay: locationInaccuracyWarningInitialDelay,
            insufficientAccuracyAutoStopInterval: insufficientAccuracyAutoStopInterval,
            updates: {
                let merged = merge(
                    pingMeasurementService().map { NetworkCoverageViewModel.Update.ping($0) },
                    locationUpdatesService.locations().map { NetworkCoverageViewModel.Update.location($0) }
                )
                return merge(
                    merged,
                    networkConnectionUpdatesService
                        .networkConnectionTypes()
                        .map { NetworkCoverageViewModel.Update.networkType($0) }
                )
            },
            currentRadioTechnology: currentRadioTechnology,
            sendResultsService: sendResultsService,
            persistenceService: persistenceService,
            locale: locale,
            clock: clock,
            maxTestDuration: maxTestDuration,
            ipVersionProvider: ipVersionProvider,
            connectionsCountProvider: connectionsCountProvider,
            renderingConfiguration: renderingConfiguration
        )
    }

    private func iterate(_ sequence: some AsynchronousSequence<NetworkCoverageViewModel.Update>) async {
        do {
            for try await update in sequence {
                try Task.checkCancellation()
                guard isStarted else { break }

                if let startTime = testStartTime, timeNow().timeIntervalSince(startTime) >= maxTestDuration() {
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
            guard !isOnWiFi else { return }
            
            if firstPingTimestamp == nil {
                firstPingTimestamp = pingUpdate.timestamp
            }
            guard !wasInsideInaccurateLocationWindow(pingUpdate) else {
                return
            }
            pingResults.append(pingUpdate)
            connectionFragmentsCount = connectionsCountProvider()

            if var (fence, idx) = fences.fence(at: pingUpdate.timestamp) {
                fence.append(ping: pingUpdate)
                fences[idx] = fence
            }
            
        case .location(let locationUpdate):
            let location = locationUpdate.location
            let radioTechnologyCode = currentRadioTechnology.technologyCode()
            locations.append(location)
            locationAccuracy = String(format: "%.2fm", location.horizontalAccuracy)
            latestTechnology = displayValue(forRadioTechnology: radioTechnologyCode ?? "N/A")

            guard isLocationPreciseEnough(location) else {
                startInaccurateLocationWindowIfNeeded(at: location.timestamp)
                checkForLocationInaccuracyWarning(location: location)
                return
            }
            stopInaccurateLocationWindow(at: location.timestamp)
            warningPopups.removeAll { $0 == .inaccurateLocationWarning }

            if
                !hasEverHadAccurateLocation,
                let testStartTime,
                testStartTime.addingTimeInterval(insufficientAccuracyAutoStopInterval) > location.timestamp {
                hasEverHadAccurateLocation = true
            }

            // On Wi‑Fi: update warning/UI only, ignore measurement state/fences
            guard !isOnWiFi else { return }

            let currentFence = currentFence
            if var currentFence {
                if currentFence.startingLocation.distance(from: location) >= fenceRadius {
                    let newFence = Fence(
                        startingLocation: location,
                        dateEntered: locationUpdate.timestamp,
                        technology: radioTechnologyCode,
                        pings: [],
                        radiusMeters: fenceRadius
                    )

                    currentFence.exit(at: locationUpdate.timestamp)
                    fences[fences.endIndex - 1] = currentFence

                    try? persistenceService.save(currentFence)

                    fences.append(newFence)
                } else {
                    currentFence.append(location: location)
                    radioTechnologyCode.map { currentFence.append(technology: $0) }
                    fences[fences.endIndex - 1] = currentFence
                }
            } else {
                fences.append(.init(
                    startingLocation: location,
                    dateEntered: locationUpdate.timestamp,
                    technology: radioTechnologyCode,
                    pings: [],
                    radiusMeters: fenceRadius
                ))
            }
        case .networkType(let netUpdate):
            handleNetworkTypeChange(netUpdate.type)
        }
    }

    private func start() async {
        guard !isStarted else { return }
        let sessionStartDate = timeNow()
        isStarted = true
        testStartTime = sessionStartDate
        fences.removeAll()
        locations.removeAll()
        canCheckForLocationInaccuracyWarning = false
        hasEverHadAccurateLocation = false
        stopTestReasons.removeAll()
        isOnWiFi = false

        try? persistenceService.sessionStarted(at: sessionStartDate)

        await BackgroundActivityActor.shared.startActivity()

        locationInaccuracyWarningTask = Task { @MainActor in
            try? await clock.sleep(for: .seconds(locationInaccuracyWarningInitialDelay))

            guard !Task.isCancelled else { return }

            canCheckForLocationInaccuracyWarning = true
            locations.last.map(checkForLocationInaccuracyWarning)
        }

        autoStopDueToInaccuracyTask = Task { @MainActor in
            try? await clock.sleep(for: .seconds(insufficientAccuracyAutoStopInterval))

            guard isStarted, !Task.isCancelled else { return }

            if !hasEverHadAccurateLocation {
                await stop()
                stopTestReasons.append(.insufficientLocationAccuracy(duration: insufficientAccuracyAutoStopInterval))
            }
        }

        iterationTask = Task { @MainActor in
            await iterate(updates())
        }
        await iterationTask?.value
    }
    
    private func handleNetworkTypeChange(_ type: NetworkTypeUpdate.NetworkConnectionType) {
        let newIsOnWiFi = (type == .wifi)
        guard newIsOnWiFi != isOnWiFi else { return }

        isOnWiFi = newIsOnWiFi
        if isOnWiFi {
            if !warningPopups.contains(where: { $0 == .wifiWarning }) {
                warningPopups.append(.wifiWarning)
            }
        } else {
            warningPopups.removeAll { $0 == .wifiWarning }
        }
    }

    private func stop() async {
        let finalizationDate = timeNow()
        isStarted = false
        testStartTime = nil
        locationAccuracy = "N/A"
        latestTechnology = "N/A"
        warningPopups.removeAll()
        connectionFragmentsCount = 1
        
        // Cancel async sequences
        iterationTask?.cancel()
        iterationTask = nil
        locationInaccuracyWarningTask?.cancel()
        locationInaccuracyWarningTask = nil
        autoStopDueToInaccuracyTask?.cancel()
        autoStopDueToInaccuracyTask = nil
        
        await BackgroundActivityActor.shared.stopActivity()
        
        // Handle saving and sending results...
        if !fences.isEmpty {
            if var lastFence = fences.last, lastFence.dateExited == nil {
                lastFence.exit(at: finalizationDate)
                fences[fences.endIndex - 1] = lastFence
                try? persistenceService.save(lastFence)
            }

            do {
                Log.logger.info("Stopping coverage test: sending \(fences.count) fences")
                
                try await sendResultsService.send(fences: fences)
            } catch {
                // TODO: display error
            }
        }

        try? persistenceService.sessionFinalized(at: finalizationDate)
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
        autoStopDueToInaccuracyTask?.cancel()
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

    private func startInaccurateLocationWindowIfNeeded(at date: Date) {
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

        static var wifiWarning: Self {
            .init(
                title: "Disable Wi‑Fi",
                description: "Please turn off Wi‑Fi to measure cellular coverage."
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

fileprivate extension NetworkCoverageViewModel {
    func updateRenderedFencesIfNeeded() {
        guard !isUpdatingRenderedFences else { return }
        isUpdatingRenderedFences = true
        defer { isUpdatingRenderedFences = false }
        updateRenderedFences()
    }

    func updateRenderedFences() {
        let allItems = fenceItems

        if allItems.isEmpty {
            if !visibleFenceItems.isEmpty { visibleFenceItems = [] }
            if !fencePolylineSegments.isEmpty { fencePolylineSegments = [] }
            if mapRenderMode != .circles { mapRenderMode = .circles }
            return
        }

        ensureInitialVisibleRegionIfNeeded(for: allItems)

        let region = visibleRegion
        let desiredMode: FencesRenderMode = shouldUsePolylineMode(for: allItems, region: region) ? .polylines : .circles

        if mapRenderMode != desiredMode {
            mapRenderMode = desiredMode
            if desiredMode == .polylines, selectedFenceItem != nil {
                selectedFenceItem = nil
            }
        }

        let filteredItems = filteredFenceItems(allItems, within: region)
        if visibleFenceItems != filteredItems {
            visibleFenceItems = filteredItems
        }

        if desiredMode == .polylines {
            let segments = buildPolylineSegments(from: allItems)
            let filteredSegments = filteredPolylineSegments(segments, within: region)
            if fencePolylineSegments != filteredSegments {
                fencePolylineSegments = filteredSegments
            }
        } else if !fencePolylineSegments.isEmpty {
            fencePolylineSegments = []
        }
    }

    private func filteredFenceItems(_ items: [FenceItem], within region: MKCoordinateRegion?) -> [FenceItem] {
        guard renderingConfiguration.cullsToVisibleRegion, let region else { return items }
        return items.filter { contains($0.coordinate, in: region, paddingFactor: renderingConfiguration.visibleRegionPaddingFactor) }
    }

    private func filteredPolylineSegments(_ segments: [FencePolylineSegment], within region: MKCoordinateRegion?) -> [FencePolylineSegment] {
        guard renderingConfiguration.cullsToVisibleRegion, let region else { return segments }
        return segments.filter { segment in
            segment.coordinates.contains {
                contains($0, in: region, paddingFactor: renderingConfiguration.visibleRegionPaddingFactor)
            }
        }
    }

    /// Determines if the map should render polylines instead of circles.
    ///
    /// The switch happens only when the amount of rendered circles would exceed
    /// `maxCircleCountBeforePolyline` **and** the visible map span is large enough.
    /// Requiring both conditions prevents toggling while zoomed in and keeps
    /// circle detail when only a few fences are present.
    private func shouldUsePolylineMode(for items: [FenceItem], region: MKCoordinateRegion?) -> Bool {
        guard items.count >= renderingConfiguration.maxCircleCountBeforePolyline else { return false }
        guard let region else { return false }
        let maxSpan = max(region.span.latitudeDelta, region.span.longitudeDelta)
        return maxSpan >= renderingConfiguration.minimumSpanForPolylineMode
    }

    private func buildPolylineSegments(from items: [FenceItem]) -> [FencePolylineSegment] {
        guard items.count > 1 else { return [] }

        func segmentIdentifier(for technology: String, fenceIds: [UUID]) -> FencePolylineSegment.ID {
            let joinedIds = fenceIds.map(\.uuidString).joined(separator: ":")
            return "\(technology)|\(joinedIds)"
        }

        var segments: [FencePolylineSegment] = []
        var currentTechnology = items[0].technology
        var currentColor = items[0].color
        var coordinates: [CLLocationCoordinate2D] = [items[0].coordinate]
        var fenceIds: [UUID] = [items[0].id]
        var previousItem = items[0]

        func appendCurrentSegment() {
            guard coordinates.count >= 2 else { return }
            segments.append(
                FencePolylineSegment(
                    id: segmentIdentifier(for: currentTechnology, fenceIds: fenceIds),
                    technology: currentTechnology,
                    coordinates: coordinates,
                    color: currentColor
                )
            )
        }

        for item in items.dropFirst() {
            let distance = distanceBetween(previousItem.coordinate, item.coordinate)
            // it might happen that server returns radius = 0. In this case use default value of 20
            // otherwise polylines would not be properly rendered
            let radius = previousItem.radiusMeters > 0 ? previousItem.radiusMeters : 20
            let gapThreshold = radius * 4
            let hasGap = distance > gapThreshold
            let technologyChanged = item.technology != currentTechnology

            if technologyChanged || hasGap {
                appendCurrentSegment()

                currentTechnology = item.technology
                currentColor = item.color
                fenceIds = [item.id]
                coordinates = []

                if technologyChanged && !hasGap {
                    coordinates.append(previousItem.coordinate)
                }

                coordinates.append(item.coordinate)
            } else {
                coordinates.append(item.coordinate)
                fenceIds.append(item.id)
            }

            previousItem = item
        }

        appendCurrentSegment()

        return segments
    }

    private func distanceBetween(_ first: CLLocationCoordinate2D, _ second: CLLocationCoordinate2D) -> CLLocationDistance {
        let firstLocation = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let secondLocation = CLLocation(latitude: second.latitude, longitude: second.longitude)
        return firstLocation.distance(from: secondLocation)
    }

    private func contains(_ coordinate: CLLocationCoordinate2D, in region: MKCoordinateRegion, paddingFactor: Double) -> Bool {
        let paddedLatitudeDelta = max(region.span.latitudeDelta * paddingFactor, 0.0001)
        let paddedLongitudeDelta = max(region.span.longitudeDelta * paddingFactor, 0.0001)

        let halfLat = paddedLatitudeDelta / 2
        let halfLon = paddedLongitudeDelta / 2

        let minLat = region.center.latitude - halfLat
        let maxLat = region.center.latitude + halfLat
        let minLon = region.center.longitude - halfLon
        let maxLon = region.center.longitude + halfLon

        return coordinate.latitude >= minLat &&
            coordinate.latitude <= maxLat &&
            coordinate.longitude >= minLon &&
            coordinate.longitude <= maxLon
    }

    /// Seeds the visible region with a bounding box of all fences so read-only views
    /// display measurements even before the map reports camera updates.
    private func ensureInitialVisibleRegionIfNeeded(for items: [FenceItem]) {
        guard visibleRegion == nil, let region = regionEnclosing(items) else { return }
        visibleRegion = region
    }

    private func regionEnclosing(_ items: [FenceItem]) -> MKCoordinateRegion? {
        guard !items.isEmpty else { return nil }

        let latitudes = items.map { $0.coordinate.latitude }
        let longitudes = items.map { $0.coordinate.longitude }

        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else {
            return nil
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let latDelta = max((maxLat - minLat) * 1.5, 0.01)
        let lonDelta = max((maxLon - minLon) * 1.5, 0.01)

        let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        return MKCoordinateRegion(center: center, span: span)
    }

    private func fenceItem(from fence: Fence) -> FenceItem {
        .init(
            id: fence.id,
            date: fence.dateEntered,
            coordinate: fence.startingLocation.coordinate,
            radiusMeters: fence.radiusMeters,
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

extension NetworkCoverageViewModel {
    var pingProtocolDisplay: String {
        guard isStarted else { return "-" }
        switch ipVersionProvider() {
        case .some(.IPv4): return "IPv4"
        case .some(.IPv6): return "IPv6"
        case .none: return "-"
        }
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
    /// Creates a color for the given radio technology display value
    init(technology: String?) {
        self = switch technology {
        case "2G": Color(red: 0.988, green: 0.651, blue: 0.212) // #fca636
        case "3G": Color(red: 0.882, green: 0.392, blue: 0.384) // #e16462  
        case "4G": Color(red: 0.694, green: 0.165, blue: 0.565) // #b12a90
        case "5G NSA": Color(red: 0.416, green: 0.0, blue: 0.659) // #6a00a8
        case "5G SA": Color(red: 0.051, green: 0.031, blue: 0.529) // #0d0887
        default: Color(red: 0.851, green: 0.851, blue: 0.851) // #d9d9d9
        }
    }
}
