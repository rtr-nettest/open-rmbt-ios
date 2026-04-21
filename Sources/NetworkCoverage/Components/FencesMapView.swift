//
//  FencesMapView.swift
//  RMBT
//
//  Created by Jiri Urbasek on 21.07.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import SwiftUI
import CoreLocation
import MapKit

/// Coordinates how a fence map view forwards camera updates to its view model
/// and when it should auto-center on newly arriving fences.
///
/// Lives as a plain value type so the view's decision logic is unit-testable
/// without SwiftUI. Semantics:
/// - The coordinator starts open (ready to forward) when we already have fences to show
///   or when the map tracks the user's location.
/// - Otherwise it stays closed until fences appear — in which case the view is told to
///   center the map on them once.
/// - Once open, the coordinator never closes. Transient culling that empties the
///   visible fences (e.g. the user zooming into an empty area) must NOT stop future
///   camera reports, otherwise the view model's culled region stays stuck on an
///   empty area and the fences never reappear.
struct FencesMapRegionCoordinator {
    private(set) var lastReportedRegion: MKCoordinateRegion?
    private(set) var isOpen: Bool
    let tracksUserLocation: Bool

    init(hasInitialItems: Bool, tracksUserLocation: Bool) {
        self.tracksUserLocation = tracksUserLocation
        self.isOpen = tracksUserLocation || hasInitialItems
    }

    /// Returns the region to forward to `onVisibleRegionChange`, or nil to suppress
    /// (coordinator not yet open, or region is a near-duplicate of the last reported one).
    mutating func regionToReport(for region: MKCoordinateRegion) -> MKCoordinateRegion? {
        guard isOpen else { return nil }
        if let previous = lastReportedRegion, !hasDiverged(region, from: previous) {
            return nil
        }
        lastReportedRegion = region
        return region
    }

    /// Reports a change in the filtered (culled) fence items on the map.
    /// Returns `true` when the view should auto-center on the items — happens only on
    /// the first time items appear in a read-only, non-tracking map that mounted empty.
    @discardableResult
    mutating func visibleItemsDidChange(hasItems: Bool) -> Bool {
        guard hasItems, !isOpen, !tracksUserLocation else { return false }
        isOpen = true
        return true
    }

    private func hasDiverged(_ region: MKCoordinateRegion, from previous: MKCoordinateRegion) -> Bool {
        let centerTolerance: CLLocationDegrees = 0.0002
        let spanTolerance: CLLocationDegrees = 0.0002
        return abs(region.center.latitude - previous.center.latitude) > centerTolerance ||
            abs(region.center.longitude - previous.center.longitude) > centerTolerance ||
            abs(region.span.latitudeDelta - previous.span.latitudeDelta) > spanTolerance ||
            abs(region.span.longitudeDelta - previous.span.longitudeDelta) > spanTolerance
    }
}

/// “Dumb” SwiftUI map responsible for visualising network coverage fences.
///
/// All rendering decisions—culling, polyline switching, current selection—are
/// supplied by `NetworkCoverageViewModel`. The map reports camera changes back
/// so the view model can keep its derived state in sync.
struct FencesMapView: View {
    let visibleFenceItems: [FenceItem]
    let fencePolylineSegments: [FencePolylineSegment]
    let mapRenderMode: FencesRenderMode
    let locations: [LocationUpdate]
    let selectedFenceItem: Binding<FenceItem?>
    let selectedFenceDetail: FenceDetail?
    let isExpertMode: Bool
    let showsSettingsButton: Bool
    let showsSettings: Bool
    let onSettingsToggle: () -> Void
    let trackUserLocation: Bool
    let onVisibleRegionChange: (MKCoordinateRegion?) -> Void
    
    @State private var position: MapCameraPosition
    @State private var regionCoordinator: FencesMapRegionCoordinator
    
    init(
        visibleFenceItems: [FenceItem],
        fencePolylineSegments: [FencePolylineSegment],
        mapRenderMode: FencesRenderMode,
        locations: [LocationUpdate],
        selectedFenceItem: Binding<FenceItem?>,
        selectedFenceDetail: FenceDetail?,
        isExpertMode: Bool,
        showsSettingsButton: Bool,
        showsSettings: Bool,
        onSettingsToggle: @escaping () -> Void,
        trackUserLocation: Bool,
        onVisibleRegionChange: @escaping (MKCoordinateRegion?) -> Void
    ) {
        self.visibleFenceItems = visibleFenceItems
        self.fencePolylineSegments = fencePolylineSegments
        self.mapRenderMode = mapRenderMode
        self.locations = locations
        self.selectedFenceItem = selectedFenceItem
        self.selectedFenceDetail = selectedFenceDetail
        self.isExpertMode = isExpertMode
        self.showsSettingsButton = showsSettingsButton
        self.showsSettings = showsSettings
        self.onSettingsToggle = onSettingsToggle
        self.trackUserLocation = trackUserLocation
        self.onVisibleRegionChange = onVisibleRegionChange
        
        // Calculate initial position to show all fences
        if trackUserLocation {
            _position = State(initialValue: .userLocation(fallback: .automatic))
        } else if !visibleFenceItems.isEmpty {
            let coordinates = visibleFenceItems.map { $0.coordinate }
            let center = Self.calculateCenter(coordinates: coordinates)
            let span = Self.calculateSpan(coordinates: coordinates)
            _position = State(initialValue: .region(MKCoordinateRegion(center: center, span: span)))
        } else {
            _position = State(initialValue: .automatic)
        }
        _regionCoordinator = State(initialValue: FencesMapRegionCoordinator(
            hasInitialItems: !visibleFenceItems.isEmpty,
            tracksUserLocation: trackUserLocation
        ))
    }
    
    private static func calculateCenter(coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let totalLat = coordinates.reduce(0) { $0 + $1.latitude }
        let totalLon = coordinates.reduce(0) { $0 + $1.longitude }
        return CLLocationCoordinate2D(latitude: totalLat / Double(coordinates.count), longitude: totalLon / Double(coordinates.count))
    }
    
    private static func calculateSpan(coordinates: [CLLocationCoordinate2D]) -> MKCoordinateSpan {
        guard coordinates.count > 1 else { return MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01) }
        
        let lats = coordinates.map { $0.latitude }
        let lons = coordinates.map { $0.longitude }
        
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        
        let latDelta = (maxLat - minLat) * 1.5 // Add padding
        let lonDelta = (maxLon - minLon) * 1.5 // Add padding
        
        return MKCoordinateSpan(latitudeDelta: max(latDelta, 0.01), longitudeDelta: max(lonDelta, 0.01))
    }
    
    var body: some View {
        Map(position: $position, selection: selectedFenceItem) {
            UserAnnotation()

            switch mapRenderMode {
            case .circles:
                ForEach(visibleFenceItems) { fence in
                    if !isExpertMode && fence.isCurrent {
                        fenceCircle(for: fence)
                        fenceAnnotation(for: fence)
                            .tag(fence)
                    }
                    if isExpertMode {
                        fenceCircle(for: fence)

                        Annotation(
                            coordinate: fence.coordinate,
                            content: {
                                Text(fence.technology)
                                    .font(.caption)
                            },
                            label: { EmptyView() }
                        )
                        .tag(fence)
                    } else {
                        fenceAnnotation(for: fence)
                            .tag(fence)
                    }
                }
            case .polylines:
                ForEach(fencePolylineSegments) { segment in
                    fencePolyline(for: segment)
                }

                if let currentFence = visibleFenceItems.first(where: { $0.isCurrent }) {
                    fenceCircle(for: currentFence)
                }
            }

            if isExpertMode {
                ForEach(locations) { location in
                    MapCircle(center: location.coordinate, radius: location.horizontalAccuracy)
                        .foregroundStyle(.blue.opacity(0.2))
                        .mapOverlayLevel(level: .aboveLabels)
                }
            }
        }
        .onMapCameraChange(frequency: .continuous) { context in
            if let region = regionCoordinator.regionToReport(for: context.region) {
                onVisibleRegionChange(region)
            }
        }
        .onChange(of: visibleFenceItems) { _, newItems in
            if regionCoordinator.visibleItemsDidChange(hasItems: !newItems.isEmpty) {
                centerMap(on: newItems)
            }
        }
        .mapControls {
            MapScaleView()
            MapCompass()
            MapUserLocationButton()
        }
        .overlay() {
            VStack {
                Spacer()

                HStack(alignment: .bottom, spacing: 8) {
                    if let detail = selectedFenceDetail {
                        selectedFenceDetailView(detail)
                    } else {
                        Spacer()
                    }

                    if showsSettingsButton {
                        Button(
                            action: onSettingsToggle,
                            label: { Image(systemName: "gearshape").padding() }
                        )
                        .tint(.brand)
                        .mapOverlay()
                    }
                }
                .padding()
            }
        }
    }
    
    func fencePolyline(for segment: FencePolylineSegment) -> some MapContent {
        MapPolyline(coordinates: segment.coordinates)
            .stroke(segment.color.opacity(0.85), lineWidth: 5)
            .mapOverlayLevel(level: .aboveRoads)
    }

    func fenceCircle(for fence: FenceItem) -> some MapContent {
        MapCircle(center: fence.coordinate, radius: fence.radiusMeters)
            .foregroundStyle(fence.color.opacity(fence.isSelected ? 0.5 : 0.1))
            .stroke(
                fence.isSelected ? Color.black : fence.color.opacity(0.8),
                lineWidth: fence.isSelected ? 3 : 1
            )
            .mapOverlayLevel(level: .aboveLabels)
    }

    func fenceAnnotation(for fence: FenceItem) -> some MapContent {
        Annotation(
            coordinate: fence.coordinate,
            content: {
                let size: CGFloat = fence.isSelected ? 26 : 20
                Circle()
                    .fill(fence.color.opacity(fence.isSelected ? 1 : 0.6))
                    .stroke(
                        fence.isSelected ? Color.black : fence.color,
                        lineWidth: fence.isSelected ? 3 : 1
                    )
                    .frame(width: size, height: size)
            },
            label: { EmptyView() }
        )
    }

    func horizontalSeparator() -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(maxWidth: .infinity, maxHeight: 1, alignment: .center)
    }

    private func centerMap(on items: [FenceItem]) {
        guard !items.isEmpty else { return }

        let coordinates = items.map { $0.coordinate }
        let center = Self.calculateCenter(coordinates: coordinates)
        let span = Self.calculateSpan(coordinates: coordinates)
        position = .region(MKCoordinateRegion(center: center, span: span))
    }

    @ViewBuilder
    func selectedFenceDetailView(_ detail: FenceDetail) -> some View {
        VStack(alignment: .leading) {
            HStack(alignment: .bottom) {
                Text("Date:")
                    .font(.headline)
                Text(detail.date)
            }
            HStack(alignment: .bottom) {
                Text("Technology:")
                    .font(.headline)
                Text(detail.technology)
                    .foregroundStyle(detail.color)
            }
            if !detail.averagePing.isEmpty {
                HStack(alignment: .bottom) {
                    Text("Ping:")
                        .font(.headline)
                    Text(detail.averagePing)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .mapOverlay()
    }
}

private extension View {
    func mapOverlay() -> some View {
        background(Color.white.opacity(0.85))
            .cornerRadius(8)
    }

    func adjustTopSafeAreaInset() -> some View {
        self
    }
}

#Preview {
    @Previewable @State var selectedFenceItem: FenceItem?
    let viewModel = NetworkCoverageFactory().makeReadOnlyCoverageViewModel(fences: Fence.mockFences)
    
    FencesMapView(
        visibleFenceItems: viewModel.visibleFenceItems,
        fencePolylineSegments: viewModel.fencePolylineSegments,
        mapRenderMode: viewModel.mapRenderMode,
        locations: [],
        selectedFenceItem: $selectedFenceItem,
        selectedFenceDetail: nil,
        isExpertMode: false,
        showsSettingsButton: true,
        showsSettings: true,
        onSettingsToggle: {},
        trackUserLocation: false,
        onVisibleRegionChange: viewModel.updateVisibleRegion(_:)
    )
}
