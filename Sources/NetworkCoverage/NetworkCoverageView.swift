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
    @State private var showsSettings = false
    @State private var isExpertMode = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                FencesMapView(
                    fenceItems: viewModel.fenceItems,
                    locations: viewModel.locations.map { LocationUpdate(location: $0, timestamp: $0.timestamp) },
                    selectedFenceItem: $viewModel.selectedFenceItem,
                    selectedFenceDetail: viewModel.selectedFenceDetail,
                    fenceRadius: viewModel.fenceRadius,
                    isExpertMode: isExpertMode,
                    showsSettingsButton: true,
                    showsSettings: showsSettings,
                    onSettingsToggle: { showsSettings.toggle() },
                    trackUserLocation: true
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if showsSettings {
                        showsSettings = false
                    }
                }
                
                VStack {
                    Text("Network Coverage")
                        .font(.title2)
                    topBarView
                        .padding(.leading, 8)
                        .padding(.trailing, 56)
                    
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
                        navigationPath.append("results")
                    }
                }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { destination in
                if destination == "results" {
                    CoverageResultView(onClose: onClose)
                        .environment(viewModel)
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
                    showStopTestPopup = true
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
        ],
        onClose: {}
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
