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

    @State private var showStopTestPopup = false
    @State private var navigationPath = NavigationPath()
    @State private var resultStopReasons: [StopTestReason] = []
    @State private var showsSettings = false
    @State private var isExpertMode = false
    @State private var didFinishMeasurement = false

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle:
                CoverageTermsView(
                    onAccept: { Task { await viewModel.startTest() } },
                    onDecline: onClose
                )
            case .preparing:
                CoverageReadinessView(
                    gps: viewModel.gpsReadiness,
                    network: viewModel.networkReadiness,
                    onAbort: { Task { await viewModel.stopTest() } }
                )
            case .recording, .stopped:
                recordingBody
            }
        }
        // Whenever the measurement ends — user stop, auto max-duration stop, or the measurement dying —
        // leave the map instead of stranding the user: show results if anything was recorded, otherwise
        // return to the start screen. Runs once per presentation.
        .onChange(of: viewModel.phase) { newPhase in
            guard newPhase == .stopped, !didFinishMeasurement else { return }
            didFinishMeasurement = true
            if viewModel.fences.isEmpty {
                onClose()
            } else {
                resultStopReasons = viewModel.stopTestReasons
                navigationPath.append("results")
            }
        }
    }

    private var recordingBody: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                FencesMapView(
                    visibleFenceItems: viewModel.visibleFenceItems,
                    fencePolylineSegments: viewModel.fencePolylineSegments,
                    mapRenderMode: viewModel.mapRenderMode,
                    locations: viewModel.locations.map { LocationUpdate(location: $0, timestamp: $0.timestamp) },
                    selectedFenceItem: $viewModel.selectedFenceItem,
                    selectedFenceDetail: viewModel.selectedFenceDetail,
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
                        CoverageHeader(
                            title: "Network Coverage",
                            // Always offer an action so the user can never get stranded: "Stop" while the
                            // measurement is recording, otherwise "Close" (e.g. if it auto-stopped or died).
                            action: viewModel.isStarted
                                ? .init(title: "Stop", action: { showStopTestPopup = true })
                                : .init(title: "Close", action: onClose)
                        ) { topBarView }

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
            .testStopPopup(
                isPresented: $showStopTestPopup,
                title: NSLocalizedString("Stop Coverage Test", comment: ""),
                subtitle: NSLocalizedString("The test will be stopped and results will be sent to the server.", comment: ""),
                onStopTest: {
                    // Stopping flips the phase to .stopped; the .onChange(phase) handler navigates to results.
                    Task { await viewModel.toggleMeasurement() }
                }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { destination in
                if destination == "results" {
                    TestCoverageResultView(stopReasons: resultStopReasons, onClose: onClose)
                        .environment(viewModel)
                }
            }
            .keepScreenAwake(while: viewModel.isStarted)
        }
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

            Text("Current fence radius: **\(measurementValue(viewModel.currentFenceRadius))**")
                .frame(maxWidth: .infinity, alignment: .leading)

            if isExpertMode {
                horizontalSeparator()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Accepted location accuracy: **\(viewModel.minimumLocationAccuracy, format: .number) m**")
                    Text("Only locations at or below this accuracy contribute to fences and ping assignment.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .mapOverlay()
    }

    var topBarView: some View {
        // A Grid keeps all four values on a single, shared-height row so they stay vertically
        // aligned even when a caption wraps to two lines (e.g. German "Standortgenauigkeit" /
        // "Geschwindigkeit"), which independent VStacks per column cannot guarantee.
        Grid(horizontalSpacing: 0, verticalSpacing: 4) {
            GridRow(alignment: .top) {
                Text("Technology")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Ping")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Loc. accuracy")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(NSLocalizedString("location_dialog_label_speed", comment: ""))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GridRow(alignment: .top) {
                Text(viewModel.latestTechnology)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(viewModel.latestPing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(viewModel.locationAccuracy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(viewModel.speed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func measurementValue(_ value: CLLocationDistance?) -> String {
        guard let value else { return "N/A" }
        return "\(Int(value.rounded())) m"
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
