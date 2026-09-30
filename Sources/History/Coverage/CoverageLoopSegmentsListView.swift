//
//  CoverageLoopSegmentsListView.swift
//  RMBT
//
//  Copyright © 2026 appscape gmbh. All rights reserved.
//

import SwiftUI

/// Lists the individual segments (each a separate open_test_uuid) that make up a signal-measurement loop,
/// latest on top. Selecting a segment opens its regular single-segment result (map + "Test details"),
/// exactly like tapping a single measurement. Mirrors Android's `CoverageLoopSegmentsActivity`.
struct CoverageLoopSegmentsListView: View {
    struct SegmentRow: Identifiable {
        let id: String
        let title: String
        let pointsText: String?
        let result: RMBTHistoryCoverageResult
    }

    let segments: [SegmentRow]
    let onSelect: (RMBTHistoryCoverageResult) -> Void

    var body: some View {
        List(segments) { segment in
            Button {
                onSelect(segment.result)
            } label: {
                HStack(spacing: 12) {
                    Image("tab_coverage")
                        .renderingMode(.template)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.title)
                            .foregroundStyle(.primary)
                        if let pointsText = segment.pointsText {
                            Text(pointsText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
        }
        .listStyle(.plain)
    }
}
