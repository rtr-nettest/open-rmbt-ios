//
//  NetworkCoverageView.swift
//  RMBT
//
//  Created by Jiri Urbasek on 11/25/24.
//  Copyright 2024 appscape gmbh. All rights reserved.
//

import SwiftUI
import CoreLocation
import MapKit

struct NetworkCoverageView: View {
    @Bindable var viewModel: NetworkCoverageViewModel

    init(fences: [Fence] = []) {
        viewModel = NetworkCoverageFactory(database: UserDatabase.shared).makeCoverageViewModel(fences: fences)
    }

    @State private var position: MapCameraPosition = .userLocation(
        fallback: .automatic
    )

    @State private var showsSetings = false
    @State private var isExpertMode = false
    @State private var showStartTestPopup = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)

        Map(position: $position, selection: $viewModel.selectedFenceID) {
            UserAnnotation()

            ForEach(viewModel.fenceItems) { fence in
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
                ForEach(viewModel.locations) { location in
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
                topBarView
                    .padding(.leading, 8)
                    .padding(.trailing, 56)

                Spacer()

                if showsSetings {
                    settingsView
                        .padding(.horizontal, 16)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    if let detail = viewModel.selectedFenceDetail {
                        selectedFenceDetailView(detail)
                    } else {
                        Spacer()
                    }

                    Button(
                        action: { showsSetings.toggle() },
                        label: { Image(systemName: "gearshape").padding() }
                    )
                    .tint(.brand)
                    .mapOverlay()
                }
                .padding()
            }
        }
        .testStartPopup(
            isPresented: $showStartTestPopup,
            title: "Start Coverage Test",
            subtitle: "This will begin the network coverage test to measure signal quality in your area.",
            onStartTest: {
                Task { await viewModel.toggleMeasurement() }
            }
        )
    }

    func fenceCircle(for fence: FenceItem) -> some MapContent {
        MapCircle(center: fence.coordinate, radius: viewModel.fenceRadius)
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

    func verticalSeparator() -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(maxWidth: 1, maxHeight: .infinity, alignment: .center)
    }

    var settingsView: some View {
        VStack(spacing: 12) {
            HStack {
                Toggle("Experts details", isOn: $isExpertMode)
            }

            horizontalSeparator()

            VStack(alignment: .leading) {
                Text("Fence radius: **\(viewModel.fenceRadius, format: .number) m**")
                Slider(
                    value: $viewModel.fenceRadius,
                    in: 10...50,
                    step: 1,
                    label: { Text("\(viewModel.fenceRadius) m").font(.footnote) },
                    minimumValueLabel: { Text("10 m").font(.footnote) },
                    maximumValueLabel: { Text("50 m").font(.footnote) }
                )
            }

            horizontalSeparator()

            VStack(alignment: .leading) {
                Text("Accuracy: **\(viewModel.minimumLocationAccuracy, format: .number) m**")
                Slider(
                    value: $viewModel.minimumLocationAccuracy,
                    in: 3...20,
                    step: 1,
                    label: { Text("\(viewModel.minimumLocationAccuracy) m").font(.footnote) },
                    minimumValueLabel: { Text("3 m").font(.footnote) },
                    maximumValueLabel: { Text("20 m").font(.footnote) }
                )
            }
        }
        .padding()
        .mapOverlay()
    }

    var topBarView: some View {
        HStack {
            Spacer()
            VStack(alignment: .leading) {
                Text("Technology")
                    .font(.caption)
                Text(viewModel.latestTechnology)
            }

            Spacer()

            VStack(alignment: .leading) {
                Text("Ping")
                    .font(.caption)
                Text(viewModel.latestPing)
            }

            Spacer()

            VStack(alignment: .leading) {
                Text("Loc. accuracy")
                    .font(.caption)
                Text(viewModel.locationAccuracy)
            }

            Spacer()

            verticalSeparator()
                .frame(height: 44)

            Spacer()

            Button(viewModel.isStarted ? "Stop" : "Start") {
                if viewModel.isStarted {
                    Task { await viewModel.toggleMeasurement() }
                } else {
                    showStartTestPopup = true
                }
            }
            .tint(.brand)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(12)
        .mapOverlay()
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
    NetworkCoverageView(
        fences: [
            .init(
                startingLocation: CLLocation(
                    latitude: 49.74805411063806,
                    longitude: 13.37696845562318
                ),
                dateEntered: .init(timeIntervalSince1970: 1734526653),
                technology: "3G/HSDPA",
                avgPing: .milliseconds(122)
            ),
            .init(
                startingLocation: CLLocation(
                    latitude: 49.747849194587204,
                    longitude: 13.376917714305671
                ),
                dateEntered: .init(timeIntervalSince1970: 1734526656),
                technology: "4G/LTE",
                pings: [.init(result: .interval(.milliseconds(84)), timestamp: .init(timeIntervalSince1970: 1734526656))]
            ),
            .init(
                startingLocation: CLLocation(
                    latitude: 49.74741067132995,
                    longitude: 13.376784518347213
                ),
                dateEntered: .init(timeIntervalSince1970: 1734526659),
                technology: "4G/LTE",
                pings: [.init(result: .interval(.milliseconds(41)), timestamp: .init(timeIntervalSince1970: 1734526659))]
            ),
            .init(
                startingLocation: CLLocation(
                    latitude: 49.74700902972835,
                    longitude: 13.376651322388751
                ),
                dateEntered: .init(timeIntervalSince1970: 1734526661),
                technology: "5G/NRNSA",
                pings: [.init(result: .interval(.milliseconds(26)), timestamp: .init(timeIntervalSince1970: 1734526661))]
            )
        ]
    )
}

extension Fence {
    init(startingLocation: CLLocation, dateEntered: Date, technology: String?, avgPing: Duration) {
        self.init(
            startingLocation: startingLocation,
            dateEntered: dateEntered,
            technology: technology,
            pings: [.init(result: .interval(avgPing), timestamp: dateEntered)]
        )
    }
}
