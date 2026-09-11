//
//  CoverageActionButtons.swift
//  RMBT
//
//  Shared action-button styles for the signal-measurement screens so the terms/accept screen and the
//  readiness/waiting screen use the same button layout. The negative button carries a 1.5pt brand
//  stroke (white fill, brand-coloured text + outline), mirroring the recent Android negative-button
//  style — this keeps a lone negative button (e.g. the "Abort" on the waiting screen) clearly visible.
//

import SwiftUI

/// Filled primary action button (green/brand background, white text).
struct FilledActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .background(Color.brand)
                .cornerRadius(8)
        }
    }
}

/// Outlined "negative" action button: white/background fill with a 1.5pt brand stroke and brand text.
struct OutlinedNegativeButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.brand)
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.brand, lineWidth: 1.5)
                )
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        FilledActionButton(title: "Accept", action: {})
        OutlinedNegativeButton(title: "Decline", action: {})
    }
    .padding(24)
}
