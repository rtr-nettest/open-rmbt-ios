//
//  CoverageTermsView.swift
//  RMBT
//
//  Full-screen signal-measurement intro/terms screen shown before a coverage measurement starts
//  (the `.idle` phase). Mirrors Android's SignalMeasurementTermsActivity: a title, the terms text, and
//  Accept / Decline buttons. Accept proceeds to the readiness ("preparing") screen; Decline closes.
//

import SwiftUI

struct CoverageTermsView: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(NSLocalizedString("coverage_intro_title", comment: ""))
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                Text(NSLocalizedString("coverage_intro_description", comment: ""))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 12) {
                FilledActionButton(
                    title: NSLocalizedString("coverage_terms_accept", comment: ""),
                    action: onAccept
                )
                OutlinedNegativeButton(
                    title: NSLocalizedString("coverage_terms_decline", comment: ""),
                    action: onDecline
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }
}

#Preview {
    CoverageTermsView(onAccept: {}, onDecline: {})
}
