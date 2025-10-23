//
//  HistoryCoverageResultView.swift
//  RMBT
//
//  Created by Jiri Urbasek on 10/23/25.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import SwiftUI

/// Wraps CoverageResultView for presentation from the history screen.
/// Displays results with standard navigation bar and back button.
struct HistoryCoverageResultView: View {
    @Environment(NetworkCoverageViewModel.self) private var viewModel
    let stopReasons: [StopTestReason]

    var body: some View {
        CoverageResultView(stopReasons: stopReasons)
            .environment(viewModel)
            .navigationTitle(NSLocalizedString("Coverage Test Results", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HistoryCoverageResultView(
            stopReasons: []
        )
        .environment(NetworkCoverageFactory().makeReadOnlyCoverageViewModel(fences: Fence.mockFences))
    }
}
