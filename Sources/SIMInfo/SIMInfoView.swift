//
//  SIMInfoView.swift
//  RMBT
//
//  Diagnostic screen that displays the cellular services iOS currently exposes, including which one
//  carries data and its radio technology, plus a best-effort offline/airplane-mode hint. Used to
//  verify what dual-SIM information is actually obtainable on current iOS versions.
//
//  The screen deliberately frames everything as "cellular services exposed by CoreTelephony"
//  rather than physical SIMs, and uses only the reliable, non-deprecated API.
//

import SwiftUI

struct SIMInfoView: View {
    @State private var viewModel: SIMInfoViewModel

    // `@autoclosure @MainActor` defers the default so the main-actor-isolated `SIMInfoViewModel()`
    // is built inside this isolated init rather than at the (nonisolated) default-argument site.
    @MainActor
    init(viewModel: @autoclosure @MainActor () -> SIMInfoViewModel = SIMInfoViewModel()) {
        _viewModel = State(initialValue: viewModel())
    }

    var body: some View {
        List {
            overviewSection
            connectivitySection

            if viewModel.summary.hasCellularService {
                ForEach(viewModel.items) { item in
                    serviceSection(for: item)
                }
            } else {
                Section {
                    Text("No cellular service detected. The device may have no SIM, be Wi-Fi only, or be in airplane mode.")
                        .foregroundStyle(.secondary)
                }
            }

            disclaimerSection
        }
        .navigationTitle("SIM Information")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
        }
        .onAppear {
            viewModel.refresh()
            viewModel.startObserving()
        }
        .onDisappear {
            viewModel.stopObserving()
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        Section {
            LabeledContent("Cellular services", value: "\(viewModel.summary.serviceCount)")
        } header: {
            Text("Overview")
        }
    }

    // MARK: - Connectivity / airplane-mode hint

    private var connectivitySection: some View {
        Section {
            LabeledContent("Status", value: connectivityStatusText)
                .foregroundStyle(connectivityStatusColor)
        } header: {
            Text("Connectivity")
        }
    }

    private var connectivityStatusText: String {
        switch viewModel.airplaneModeHint {
        case .undetermined: return NSLocalizedString("Checking…", comment: "")
        case .connected: return NSLocalizedString("Network path available", comment: "")
        case .noPathButRadioPresent: return NSLocalizedString("No connection (radio is on)", comment: "")
        case .likelyAirplaneModeOrOffline: return NSLocalizedString("Likely airplane mode or offline", comment: "")
        }
    }

    private var connectivityStatusColor: Color {
        switch viewModel.airplaneModeHint {
        case .undetermined: return .secondary
        case .connected: return .green
        case .noPathButRadioPresent: return .orange
        case .likelyAirplaneModeOrOffline: return .red
        }
    }

    // MARK: - Per-service

    private func serviceSection(for item: SIMInfoItem) -> some View {
        Section {
            LabeledContent("Technology", value: item.technologyLabel ?? NSLocalizedString("No service", comment: ""))
            if let generation = item.generationLabel {
                LabeledContent("Generation", value: generation)
            }
            LabeledContent("Used for data") {
                Text(item.isDataService ? "Yes" : "No")
                    .foregroundStyle(item.isDataService ? Color.green : Color.secondary)
            }
            LabeledContent("Registered", value: item.isRegistered ? "Yes" : "No")
        } header: {
            HStack {
                Text(item.displayName)
                if item.isDataService {
                    Text("DATA")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var disclaimerSection: some View {
        Section {
            Text("This information is a best-effort guess from iOS APIs and may be incomplete or inconsistent.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Two services") {
    NavigationStack {
        SIMInfoView(viewModel: SIMInfoViewModel(
            provider: PreviewCellularSnapshotProvider.twoServices,
            pathMonitor: PreviewNetworkPathMonitor(hasNetworkPath: true)
        ))
    }
}

#Preview("Airplane mode") {
    NavigationStack {
        SIMInfoView(viewModel: SIMInfoViewModel(
            provider: PreviewCellularSnapshotProvider.noService,
            pathMonitor: PreviewNetworkPathMonitor(hasNetworkPath: false)
        ))
    }
}

/// Static provider used only for SwiftUI previews.
private struct PreviewCellularSnapshotProvider: CellularSnapshotProviding {
    let snapshot: CellularSnapshot
    func currentSnapshot() -> CellularSnapshot { snapshot }

    static let twoServices = PreviewCellularSnapshotProvider(snapshot: CellularSnapshot(
        radioTechnologyByService: [
            "0000000100000001": "CTRadioAccessTechnologyNR",
            "0000000100000002": "CTRadioAccessTechnologyLTE"
        ],
        dataServiceIdentifier: "0000000100000001"
    ))

    static let noService = PreviewCellularSnapshotProvider(snapshot: CellularSnapshot())
}

/// Static path monitor used only for SwiftUI previews.
@MainActor
private final class PreviewNetworkPathMonitor: NetworkPathMonitoring {
    private(set) var hasNetworkPath: Bool?
    init(hasNetworkPath: Bool?) { self.hasNetworkPath = hasNetworkPath }
    func startMonitoring(_ onChange: @escaping @MainActor () -> Void) {}
    func stopMonitoring() {}
}
