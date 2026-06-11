//
//  SIMInfoView.swift
//  RMBT
//
//  Proof-of-concept screen that displays the cellular services iOS currently exposes, including
//  which one carries data and its radio technology. Used to verify what dual-SIM information is
//  actually obtainable on current iOS versions.
//
//  The screen deliberately frames everything as "cellular services exposed by CoreTelephony"
//  rather than physical SIMs, and separates reliable (non-deprecated API) data from low-confidence
//  deprecated carrier data.
//

import SwiftUI

struct SIMInfoView: View {
    @State private var viewModel: SIMInfoViewModel

    @MainActor
    init() {
        self.init(viewModel: SIMInfoViewModel())
    }

    init(viewModel: SIMInfoViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            overviewSection

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
            LabeledContent("Cellular services", value: "\(viewModel.summary.reliableServiceCount)")
            if viewModel.summary.subscriberServiceCount > 0 {
                LabeledContent("Carrier records (deprecated API)", value: "\(viewModel.summary.subscriberServiceCount)")
            }
        } header: {
            Text("Overview")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("\"Cellular services\" comes from the reliable, non-deprecated API (current radio access technology + data service identifier).")
                if viewModel.summary.subscriberCountDiffersFromReliable && viewModel.summary.subscriberServiceCount > 0 {
                    Text("The deprecated carrier API reports a different number of services; treat carrier-only entries as low confidence.")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Per-service

    private func serviceSection(for item: SIMInfoItem) -> some View {
        Section {
            LabeledContent("Technology", value: item.technologyLabel ?? "No service")
            if let generation = item.generationLabel {
                LabeledContent("Generation", value: generation)
            }
            LabeledContent("Used for data") {
                Text(item.isDataService ? "Yes" : "No")
                    .foregroundStyle(item.isDataService ? Color.green : Color.secondary)
            }
            LabeledContent("Registered", value: item.isRegistered ? "Yes" : "No")
            if !item.isReportedByReliableAPI {
                Text("Only reported by the deprecated carrier API — low confidence.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            carrierRows(for: item.carrier)
            DisclosureGroup("Raw values") {
                rawRow("Service identifier", item.serviceIdentifier)
                rawRow("Carrier name", item.carrier?.carrierName)
                rawRow("Mobile country code (MCC)", item.carrier?.mobileCountryCode)
                rawRow("Mobile network code (MNC)", item.carrier?.mobileNetworkCode)
                rawRow("ISO country code", item.carrier?.isoCountryCode)
                rawRow("Allows VoIP", item.carrier?.allowsVOIP.map { $0 ? "Yes" : "No" })
            }
            .font(.footnote)
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
        } footer: {
            Text("Service ID: \(item.serviceIdentifier) (opaque; not a physical slot or SIM name)")
                .font(.caption2)
        }
    }

    @ViewBuilder
    private func carrierRows(for carrier: CarrierDetails?) -> some View {
        if let carrier {
            if carrier.looksLikePlaceholder {
                LabeledContent("Carrier") {
                    Text("Not available")
                        .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("Carrier", value: carrier.carrierName ?? "Unknown")
            }
        }
    }

    @ViewBuilder
    private func rawRow(_ title: String, _ value: String?) -> some View {
        LabeledContent(title) {
            Text(value ?? "nil")
                .foregroundStyle(value == nil ? .secondary : .primary)
                .textSelection(.enabled)
        }
    }

    private var disclaimerSection: some View {
        Section {
            Text("""
            What iOS reliably exposes: the radio technology per service and which service carries \
            cellular data (dataServiceIdentifier). What it does NOT expose: the physical SIM slot, \
            eSIM vs physical SIM, ICCID, a user-facing SIM name, or a primary/secondary identity — \
            so the "Cellular service 1/2" labels are positional only. "Used for data" means the \
            current cellular data service; it does not identify the voice/SMS line, nor which path \
            traffic takes while on Wi-Fi. Carrier identity (name, MCC/MNC) was deprecated in iOS 16 \
            with no replacement and returns placeholder values on iOS 16.4+, so it must not be used \
            for business logic.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview("Two services") {
    NavigationStack {
        SIMInfoView(viewModel: SIMInfoViewModel(provider: PreviewCellularSnapshotProvider.twoServices))
    }
}

#Preview("Single service") {
    NavigationStack {
        SIMInfoView(viewModel: SIMInfoViewModel(provider: PreviewCellularSnapshotProvider.singleService))
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
        carrierByService: [
            "0000000100000001": CarrierDetails(carrierName: "--", mobileCountryCode: "65535", mobileNetworkCode: "65535", isoCountryCode: nil, allowsVOIP: true),
            "0000000100000002": CarrierDetails(carrierName: "--", mobileCountryCode: "65535", mobileNetworkCode: "65535", isoCountryCode: nil, allowsVOIP: true)
        ],
        dataServiceIdentifier: "0000000100000001"
    ))

    static let singleService = PreviewCellularSnapshotProvider(snapshot: CellularSnapshot(
        radioTechnologyByService: ["0000000100000001": "CTRadioAccessTechnologyLTE"],
        carrierByService: ["0000000100000001": CarrierDetails(carrierName: "--", mobileCountryCode: "65535", mobileNetworkCode: "65535", isoCountryCode: nil, allowsVOIP: true)],
        dataServiceIdentifier: "0000000100000001"
    ))
}
