//
//  CoverageTestDetailsView.swift
//  RMBT
//
//  Created by Jiri Urbasek on 24/09/2025.
//

import SwiftUI

struct CoverageTestDetailsView: View {
    @State var model: CoverageTestDetailsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if model.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text(NSLocalizedString("Loading details…", comment: ""))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let _ = model.loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 42))
                        .foregroundStyle(.orange)
                    Text(NSLocalizedString("Unable to load test details", comment: ""))
                        .font(.headline)
                    Button(NSLocalizedString("Try Again", comment: "")) { model.reload() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.items.enumerated()), id: \.offset) { _, item in
                            TestDetailRow(title: item.title, value: item.value)
                            Divider()
                                .padding(.leading, 20)
                                .padding(.trailing, 20)
                        }
                    }
                }
                .background(Color(.systemBackground))
            }
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(NSLocalizedString("Close", comment: "")) {
                    dismiss()
                }
            }
        }
        .onAppear { model.reload() }
    }
}

private struct TestDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.custom("Roboto-Medium", size: 16))
                .foregroundStyle(Color(.displayP3, red: 0.2519, green: 0.2507, blue: 0.2531, opacity: 1))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(.custom("Roboto-Regular", size: 12))
                .foregroundStyle(Color(.displayP3, red: 0.6188, green: 0.6158, blue: 0.6218, opacity: 1))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 60) // match UIKit row height
        .contentShape(Rectangle())
        .background(Color(.systemBackground))
    }
}

// MARK: - Preview

#Preview {
    let mock = RMBTHistoryResult()
    let items = [
        RMBTHistoryResultItem(title: "Test UUID", value: "123e4567-e89b-12d3-a456-426614174000", classification: -1, hasDetails: false),
        RMBTHistoryResultItem(title: "Platform", value: "iOS 17.5", classification: -1, hasDetails: false),
        RMBTHistoryResultItem(title: "Device", value: "iPhone 15 Pro", classification: -1, hasDetails: false)
    ]
    mock.setValue(items, forKey: "fullDetailsItems")
    return NavigationStack {
        CoverageTestDetailsView(model: CoverageTestDetailsModel(result: mock))
    }
}
