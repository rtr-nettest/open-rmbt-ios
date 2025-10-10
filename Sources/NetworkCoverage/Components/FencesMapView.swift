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
    let fenceRadius: Double
    let isExpertMode: Bool
    let showsSettingsButton: Bool
    let showsSettings: Bool
    let onSettingsToggle: () -> Void
    let trackUserLocation: Bool
    let onVisibleRegionChange: (MKCoordinateRegion?) -> Void
    
    @State private var position: MapCameraPosition
    @State private var lastReportedRegion: MKCoordinateRegion?
    @State private var didCenterOnVisibleItems: Bool
    
    init(
        visibleFenceItems: [FenceItem],
        fencePolylineSegments: [FencePolylineSegment],
        mapRenderMode: FencesRenderMode,
        locations: [LocationUpdate],
        selectedFenceItem: Binding<FenceItem?>,
        selectedFenceDetail: FenceDetail?,
        fenceRadius: Double,
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
        self.fenceRadius = fenceRadius
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
        _lastReportedRegion = State(initialValue: nil)
        _didCenterOnVisibleItems = State(initialValue: trackUserLocation || !visibleFenceItems.isEmpty)
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
            guard trackUserLocation || didCenterOnVisibleItems else { return }
            let region = context.region
            if shouldReportRegionChange(to: region) {
                lastReportedRegion = region
                onVisibleRegionChange(region)
            }
        }
        .onChange(of: visibleFenceItems) { newItems in
            if newItems.isEmpty {
                didCenterOnVisibleItems = trackUserLocation
            } else if !didCenterOnVisibleItems, !trackUserLocation {
                centerMap(on: newItems)
            }
        }
        .onAppear {
            if !didCenterOnVisibleItems, !trackUserLocation, !visibleFenceItems.isEmpty {
                centerMap(on: visibleFenceItems)
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
            .stroke(segment.color.opacity(0.85), lineWidth: 4)
            .mapOverlayLevel(level: .aboveRoads)
    }

    func fenceCircle(for fence: FenceItem) -> some MapContent {
        MapCircle(center: fence.coordinate, radius: fenceRadius)
            .foregroundStyle(fence.color.opacity(fence.isSelected ? 0.4 : 0.1))
            .stroke(
                fence.color.opacity(fence.isSelected ? 1 : 0.8),
                lineWidth: fence.isSelected ? 2 : 1
            )
            .mapOverlayLevel(level: .aboveLabels)
    }

    func fenceAnnotation(for fence: FenceItem) -> some MapContent {
        Annotation(
            coordinate: fence.coordinate,
            content: {
                Circle()
                    .fill(fence.color.opacity(fence.isSelected ? 1 : 0.6))
                    .stroke(
                        fence.isSelected ? Color.black.opacity(0.6) :
                            fence.color,
                        lineWidth: fence.isSelected ? 2 : 1
                    )
                    .frame(width: 20, height: 20)
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
        didCenterOnVisibleItems = true
    }

    private func shouldReportRegionChange(to region: MKCoordinateRegion) -> Bool {
        guard let previous = lastReportedRegion else { return true }
        let centerTolerance: CLLocationDegrees = 0.0002
        let spanTolerance: CLLocationDegrees = 0.0002

        return abs(region.center.latitude - previous.center.latitude) > centerTolerance ||
            abs(region.center.longitude - previous.center.longitude) > centerTolerance ||
            abs(region.span.latitudeDelta - previous.span.latitudeDelta) > spanTolerance ||
            abs(region.span.longitudeDelta - previous.span.longitudeDelta) > spanTolerance
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
            HStack(alignment: .bottom) {
                Text("Ping:")
                    .font(.headline)
                Text(detail.averagePing)
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
        fenceRadius: 20.0,
        isExpertMode: false,
        showsSettingsButton: true,
        showsSettings: true,
        onSettingsToggle: {},
        trackUserLocation: false,
        onVisibleRegionChange: viewModel.updateVisibleRegion(_:)
    )
}
