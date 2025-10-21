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
    let onClose: () -> Void

    init(fences: [Fence] = [], onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        viewModel = NetworkCoverageFactory(database: UserDatabase.shared).makeCoverageViewModel(fences: fences)
    }

    @State private var showStartTestPopup = false
    @State private var showStopTestPopup = false
    @State private var navigationPath = NavigationPath()
    @State private var resultStopReasons: [StopTestReason] = []
    @State private var showsSettings = false
    @State private var isExpertMode = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                FencesMapView(
                    visibleFenceItems: viewModel.visibleFenceItems,
                    fencePolylineSegments: viewModel.fencePolylineSegments,
                    mapRenderMode: viewModel.mapRenderMode,
                    locations: viewModel.locations.map { LocationUpdate(location: $0, timestamp: $0.timestamp) },
                    selectedFenceItem: $viewModel.selectedFenceItem,
                    selectedFenceDetail: viewModel.selectedFenceDetail,
                    fenceRadius: viewModel.fenceRadius,
                    isExpertMode: isExpertMode,
                    showsSettingsButton: true,
                    showsSettings: showsSettings,
                    onSettingsToggle: { showsSettings.toggle() },
                    trackUserLocation: true,
                    onVisibleRegionChange: viewModel.updateVisibleRegion(_:)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if showsSettings {
                        showsSettings = false
                    }
                }
                .safeAreaInset(edge: .top, spacing: -10) {
                    VStack(spacing: 0) {
                        CoverageHeader(title: "Network Coverage") { topBarView }

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.warningPopups) { item in
                                WarningMessageView(title: item.title, description: item.description)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .mapOverlay()
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }

                VStack {
                    Spacer()
                    if showsSettings {
                        settingsView
                            .padding(.horizontal, 16)
                            .padding(.bottom, 80)
                    }
                }
            }
            .testStartPopup(
                isPresented: $showStartTestPopup,
                title: "Start Coverage Test",
                subtitle: "This will begin the network coverage test to measure signal quality in your area.",
                onStartTest: {
                    Task { await viewModel.toggleMeasurement() }
                },
                onCancel: onClose
            )
            .onAppear {
                if !viewModel.isStarted {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showStartTestPopup = true
                    }
                }
            }
            .testStopPopup(
                isPresented: $showStopTestPopup,
                title: "Stop Coverage Test",
                subtitle: "The test will be stopped and results will be sent to the server.",
                onStopTest: {
                    Task {
                        await viewModel.toggleMeasurement()
                        resultStopReasons = []
                        navigationPath.append("results")
                    }
                }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { destination in
                if destination == "results" {
                    CoverageResultView(stopReasons: resultStopReasons)
                        .environment(viewModel)
                }
            }
            .onChange(of: viewModel.stopTestReasons) { reasons in
                // Navigate to results when auto-stop reason for insufficient accuracy is recorded
                if reasons.contains(where: { reason in
                    if case .insufficientLocationAccuracy = reason { return true }
                    return false
                }) {
                    resultStopReasons = reasons
                    navigationPath.append("results")
                }
            }
        }
    }

    func verticalSeparator() -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(maxWidth: 1, maxHeight: .infinity, alignment: .center)
    }

    func horizontalSeparator() -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(maxWidth: .infinity, maxHeight: 1, alignment: .center)
    }

    var settingsView: some View {
        VStack(spacing: 12) {
            HStack {
                Toggle("Experts details", isOn: $isExpertMode)
            }

            horizontalSeparator()

            HStack {
                Text("\(viewModel.fences.count) points/\(viewModel.connectionFragmentsCount) connection\(viewModel.connectionFragmentsCount == 1 ? "" : "s")")

                Spacer()

                if viewModel.isStarted {
                    Text(viewModel.pingProtocolDisplay)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
            HStack(spacing: 0) {
                VStack(alignment: .leading) {
                    Text("Technology")
                        .font(.caption)
                    Text(viewModel.latestTechnology)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading) {
                    Text("Ping")
                        .font(.caption)
                    Text(viewModel.latestPing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading) {
                    Text("Loc. accuracy")
                        .font(.caption)
                    Text(viewModel.locationAccuracy)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            verticalSeparator()
                .frame(height: 44)

            Spacer()

            Button(viewModel.isStarted ? "Stop" : "") {
                if viewModel.isStarted {
                    showStopTestPopup = true
                } else {
                    showStartTestPopup = true
                }
            }
            .frame(minWidth: 40) // to maintain space when the button text is empty (Start scenario)
            .tint(.brand)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct WarningMessageView: View {
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.large)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
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
        fences: Fence.mockFences,
        onClose: {}
    )
}

extension Fence {
    init(
        startingLocation: CLLocation,
        dateEntered: Date,
        technology: String?,
        avgPing: Duration,
        radiusMeters: CLLocationDistance
    ) {
        self.init(
            startingLocation: startingLocation,
            dateEntered: dateEntered,
            technology: technology,
            pings: [.init(result: .interval(avgPing), timestamp: dateEntered)],
            radiusMeters: radiusMeters
        )
    }
}
