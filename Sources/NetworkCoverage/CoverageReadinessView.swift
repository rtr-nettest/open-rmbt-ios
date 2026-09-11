//
//  CoverageReadinessView.swift
//  RMBT
//
//  Signal-measurement "waiting for GPS / mobile network" screen, shown while the measurement is in
//  its `.preparing` phase. It displays two live readiness rows (GPS and network) and an Abort button.
//  Recording begins automatically — the view model flips `phase` to `.recording` — once the phone has a
//  fresh, accurate GPS fix on a mobile network, at which point the presenting view swaps to the live map.
//

import SwiftUI

struct CoverageReadinessView: View {
    let gps: ReadinessRow
    let network: ReadinessRow
    let onAbort: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text(NSLocalizedString("coverage_readiness_title", comment: ""))
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(NSLocalizedString("coverage_readiness_subtitle", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("signal_readiness_status_heading", comment: ""))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                readinessRow(gps)
                readinessRow(network)
            }
            .padding(.vertical, 8)

            Spacer()

            VStack(spacing: 12) {
                OutlinedNegativeButton(
                    title: NSLocalizedString("Abort", comment: ""),
                    action: onAbort
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func readinessRow(_ row: ReadinessRow) -> some View {
        Label {
            Text(row.text)
                .foregroundStyle(row.isOK ? Color.green : Color.red)
        } icon: {
            Image(systemName: row.isOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(row.isOK ? Color.green : Color.red)
        }
        .font(.headline)
    }
}

#Preview("Waiting") {
    CoverageReadinessView(
        gps: .init(isOK: false, text: "GPS: accuracy 30 m (limit 15 m)"),
        network: .init(isOK: true, text: "Network: 5G"),
        onAbort: {}
    )
}

#Preview("Ready") {
    CoverageReadinessView(
        gps: .init(isOK: true, text: "GPS: ok"),
        network: .init(isOK: true, text: "Network: 5G"),
        onAbort: {}
    )
}
