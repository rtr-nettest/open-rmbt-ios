//
//  NetworkCoverageView.swift
//  RMBT
//
//  Created by Jiri Urbasek on 11/25/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import SwiftUI
import CoreLocation
import MapKit

struct NetworkCoverageView: View {
    @Bindable var viewModel: NetworkCoverageViewModel
    let presenter: NetworkCoverageViewPresenter

    init(areas: [LocationArea] = []) {
        // TODO: move setup code below into some "Composition root" file
        let dateNow: () -> Date = Date.init
        let sessionInitializer = CoverageMeasurementSessionInitializer(
            now: dateNow,
            controlServer: RMBTControlServer.shared
        )
        let resultSender = ControlServerCoverageResultsService(
            controlServer: RMBTControlServer.shared,
            testUUID: sessionInitializer.lastTestUUID
        )
        viewModel = NetworkCoverageViewModel(
            areas: areas,
            refreshInterval: 1,
            pingMeasurementService: { PingMeasurementService.pings2(
                clock: ContinuousClock(),
                pingSender: UDPPingSession(
                    sessionInitiator: sessionInitializer,
                    udpConnection: UDPConnection(),
                    timeoutIntervalMs: 1000,
                    now: RMBTHelpers.RMBTCurrentNanos
                ),
                frequency: .milliseconds(100)
            ) },
            locationUpdatesService: RealLocationUpdatesService(now: dateNow),
            currentRadioTechnology: CTTelephonyRadioTechnologyService(),
            sendResultsService: resultSender
        )
        presenter = NetworkCoverageViewPresenter(locale: .autoupdatingCurrent)
    }

    @State private var position: MapCameraPosition = .userLocation(
        fallback: .automatic
    )

    @State private var showsSetings = false
    @State private var isExpertMode = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)

        Map(position: $position, selection: $viewModel.selectedArea) {
            UserAnnotation()

            ForEach(presenter.fences(from: viewModel)) { fence in
                let area = fence.locationArea
                let locationItem = fence.locationItem

                if !isExpertMode && area == viewModel.currentArea {
                    fenceCircle(locationItem: locationItem, area: area)
                    fenceAnnotation(locationItem: locationItem, area: area)
                }
                if isExpertMode {
                    fenceCircle(locationItem: locationItem, area: area)

                    Annotation(
                        coordinate: locationItem.coordinate,
                        content: {
                            VStack(spacing: 16) {
                                Text(locationItem.technology)
                                Text(locationItem.averagePing)
                            }
                            .font(.caption)
                        },
                        label: { EmptyView() }
                    )
                    .tag(area)
                } else {
                    fenceAnnotation(locationItem: locationItem, area: area)
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
                    if let selectedItem = viewModel.selectedArea {
                        selectedItemDetailView(selectedItem)
                    } else {
                        Spacer()
                    }

                    Button(
                        action: { showsSetings.toggle() },
                        label: { Image(systemName: "gearshape").padding() }
                    )
                    .mapOverlay()
                }
                .padding()
            }
        }
    }

    func fenceCircle(locationItem: LocationItem, area: LocationArea) -> some MapContent {
        MapCircle(center: area.startingLocation.coordinate, radius: viewModel.fenceRadius)
            .foregroundStyle(locationItem.color.opacity(locationItem.isSelected ? 0.4 : 0.1))
            .stroke(
                locationItem.color.opacity(locationItem.isSelected ? 1 : 0.8),
                lineWidth: locationItem.isSelected ? 2 : 1
            )
            .mapOverlayLevel(level: .aboveLabels)
    }

    func fenceAnnotation(locationItem: LocationItem, area: LocationArea) -> some MapContent {
        Annotation(
            coordinate: locationItem.coordinate,
            content: {
                Circle()
                    .fill(locationItem.color.opacity(locationItem.isSelected ? 1 : 0.6))
                    .stroke(
                        locationItem.isSelected ? Color.black.opacity(0.6) :
                        locationItem.color,
                        lineWidth: locationItem.isSelected ? 2 : 1
                    )
                    .frame(width: 20, height: 20)
            },
            label: { EmptyView() }
        )
        .tag(area)
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
                Text(presenter.displayValue(forRadioTechnology: viewModel.latestTechnology))
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
                Task { await viewModel.toggleMeasurement() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(12)
        .mapOverlay()
    }

    @ViewBuilder
    func selectedItemDetailView(_ selectedItem: LocationArea) -> some View {
        let item = presenter.selectedItemDetail(from: selectedItem)

        VStack(alignment: .leading) {
            HStack(alignment: .bottom) {
                Text("Date:")
                    .font(.headline)
                Text(item.date)
            }
            HStack(alignment: .bottom) {
                Text("Technology:")
                    .font(.headline)
                Text(item.technology)
                    .foregroundStyle(item.color)
            }
            HStack(alignment: .bottom) {
                Text("Ping:")
                    .font(.headline)
                Text(item.averagePing)
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
        areas: [
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
                avgPing: .milliseconds(84)
            ),
            .init(
                startingLocation: CLLocation(
                    latitude: 49.74741067132995,
                    longitude: 13.376784518347213
                ),
                dateEntered: .init(timeIntervalSince1970: 1734526659),
                technology: "4G/LTE",
                avgPing: .milliseconds(41)
            ),
            .init(
                startingLocation: CLLocation(
                    latitude: 49.74700902972835,
                    longitude: 13.376651322388751
                ),
                dateEntered: .init(timeIntervalSince1970: 1734526661),
                technology: "5G/NRNSA",
                avgPing: .milliseconds(26)
            )
        ]
    )
}

#if DEBUG
extension LocationArea {
    init(startingLocation: CLLocation, dateEntered: Date, technology: String?, avgPing: Duration) {
        self.init(
            startingLocation: startingLocation,
            dateEntered: dateEntered,
            technology: technology,
            pings: [.init(result: .interval(avgPing), timestamp: dateEntered)]
        )
    }
}
#endif
