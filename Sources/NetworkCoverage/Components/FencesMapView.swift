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

struct FencesMapView: View {
    let fenceItems: [FenceItem]
    let locations: [LocationUpdate]
    let selectedFenceID: Binding<UUID?>
    let selectedFenceDetail: FenceDetail?
    let fenceRadius: Double
    let isExpertMode: Bool
    let showsSettingsButton: Bool
    let showsSettings: Bool
    let onSettingsToggle: () -> Void
    let trackUserLocation: Bool
    
    @State private var position: MapCameraPosition
    
    init(fenceItems: [FenceItem], locations: [LocationUpdate], selectedFenceID: Binding<UUID?>, selectedFenceDetail: FenceDetail?, fenceRadius: Double, isExpertMode: Bool, showsSettingsButton: Bool, showsSettings: Bool, onSettingsToggle: @escaping () -> Void, trackUserLocation: Bool) {
        self.fenceItems = fenceItems
        self.locations = locations
        self.selectedFenceID = selectedFenceID
        self.selectedFenceDetail = selectedFenceDetail
        self.fenceRadius = fenceRadius
        self.isExpertMode = isExpertMode
        self.showsSettingsButton = showsSettingsButton
        self.showsSettings = showsSettings
        self.onSettingsToggle = onSettingsToggle
        self.trackUserLocation = trackUserLocation
        
        // Calculate initial position to show all fences
        if trackUserLocation {
            _position = State(initialValue: .userLocation(fallback: .automatic))
        } else if !fenceItems.isEmpty {
            let coordinates = fenceItems.map { $0.coordinate }
            let center = Self.calculateCenter(coordinates: coordinates)
            let span = Self.calculateSpan(coordinates: coordinates)
            _position = State(initialValue: .region(MKCoordinateRegion(center: center, span: span)))
        } else {
            _position = State(initialValue: .automatic)
        }
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
        Map(position: $position, selection: selectedFenceID) {
            UserAnnotation()

            ForEach(fenceItems) { fence in
                if !isExpertMode && fence.isCurrent {
                    fenceCircle(for: fence)
                    fenceAnnotation(for: fence)
                        .tag(fence.id)
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
                    .tag(fence.id)
                } else {
                    fenceAnnotation(for: fence)
                        .tag(fence.id)
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
}

#Preview {
    FencesMapView(
        fenceItems: [
            FenceItem(
                id: UUID(),
                date: Date(),
                coordinate: CLLocationCoordinate2D(latitude: 49.748, longitude: 13.377),
                technology: "4G/LTE",
                isSelected: false,
                isCurrent: true,
                color: .blue
            )
        ],
        locations: [],
        selectedFenceID: .constant(nil),
        selectedFenceDetail: nil,
        fenceRadius: 20.0,
        isExpertMode: false,
        showsSettingsButton: false,
        showsSettings: false,
        onSettingsToggle: {},
        trackUserLocation: false
    )
}
