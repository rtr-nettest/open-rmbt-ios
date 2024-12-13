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
    @Bindable var viewModel = NetworkCoverageViewModel()

    var body: some View {
        map
    }

    @State private var position: MapCameraPosition = .userLocation(
        fallback: .automatic
    )

    @State private var showsSetings = false
    @State private var showsIndividualLocationUpdates = true

    var map: some View {
        Map(position: $position) {
            UserAnnotation()

            ForEach(viewModel.locationsItems) { location in
                MapCircle(center: location.coordinate, radius: viewModel.fenceRadius)
                    .foregroundStyle(.green.opacity(0.1))
                    .stroke(.green.opacity(0.8), lineWidth: 1)
                    .mapOverlayLevel(level: .aboveLabels)

                Annotation(coordinate: location.coordinate, content: {
                    VStack(spacing: 16) {
                        Text(location.technology)
                        Text(location.averagePing)
                    }
                    .font(.caption)
                }, label: { EmptyView() })
            }

            if showsIndividualLocationUpdates {
                ForEach(viewModel.locations) { location in
                    MapCircle(center: location.coordinate, radius: location.horizontalAccuracy)
                        .foregroundStyle(.blue.opacity(0.2))
                        .mapOverlayLevel(level: .aboveLabels)

                }
            }
        }
        .overlay() {
            VStack {
                HStack {
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("Loc. accuracy")
                            .font(.caption)
                        Text(viewModel.locationAccuracy)
                    }

                    Spacer()

                    VStack(alignment: .leading) {
                        Text("Ping")
                            .font(.caption)
                        Text(viewModel.latestPing)
                    }

                    Spacer()

                    VStack(alignment: .leading) {
                        Text("Technology")
                            .font(.caption)
                        Text(viewModel.latestTechnology)
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
                .padding()

                Spacer()

                if showsSetings {
                    VStack(spacing: 12) {
                        HStack {
                            Toggle("Show location updates", isOn: $showsIndividualLocationUpdates)
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
                    .padding()
                }
                HStack(spacing: 8) {
                    Spacer()

                    if !position.followsUserLocation {
                        Button(
                            action: {
                                position = .userLocation(fallback: .automatic)
                            },
                            label: { Image(systemName: "location.circle").padding() }
                        )
                        .mapOverlay()
                    }

                    Button(
                        action: { showsSetings.toggle() },
                        label: { Image(systemName: "gearshape").padding() }
                    )
                    .mapOverlay()

                }
                .padding()

//                viewModel.locationsItems.last.map(NetworkCoverageInfoView.init)?
//                    .mapOverlay()
            }
        }
    }

    var list: some View {
        VStack {
            List(viewModel.locationsItems) { item in
                VStack {
                    HStack {
                        Text("Location")
                        Spacer()
                        Text("Distance")
                    }
                    .font(.caption)

                    HStack {
                        Text(item.coordinateString)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.trailing)

                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("from start: **\(item.distanceFromStart ?? "n/a")**")
                            Text("from previous: **\(item.distanceFromPrevious ?? "n/a")**")
                        }
                        .font(.subheadline)
                    }

                    Text(item.pingInfo.pings)
                        .font(.footnote)
                }
            }
            Button(viewModel.isStarted ? "Stop" : "Start") {
                Task { await viewModel.toggleMeasurement() }
            }
            .padding()
        }
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
}

private extension View {
    func mapOverlay() -> some View {
        background(Color.white.opacity(0.8))
        .cornerRadius(8)
    }
}
struct NetworkCoverageInfoView: View {
    let item: NetworkCoverageViewModel.LocationItem

    var body: some View {
        VStack {
            HStack {
                Text(item.coordinateString)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.trailing)

                Spacer()
                VStack(alignment: .trailing) {
                    Text("Ping: **\(item.averagePing)**")
                    Text("Technology: **\(item.technology)**")
                }
                .font(.subheadline)
            }

            Text(item.pingInfo.pings)
                .font(.footnote)
        }
    }
}

#Preview {
    NetworkCoverageView()
}

#Preview {
    NetworkCoverageInfoView(
        item: .init(
            id: "0",
            coordinate: .init(latitude: 37.777777, longitude: -123.777777),
            distanceFromStart: "230 m",
            distanceFromPrevious: "25 m",
            technology: "LTE",
            pings: [.init(interval: .milliseconds(123), error: nil)]
        )
    )
}
