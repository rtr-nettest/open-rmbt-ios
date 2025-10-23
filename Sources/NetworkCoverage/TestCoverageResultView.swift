//
//  TestCoverageResultView.swift
//  RMBT
//
//  Created by Jiri Urbasek on 10/23/25.
//  Copyright 2025 appscape gmbh. All rights reserved.
//

import SwiftUI

struct TestCoverageResultView: View {
    @Environment(NetworkCoverageViewModel.self) private var viewModel
    let stopReasons: [StopTestReason]
    let onClose: () -> Void

    var body: some View {
        ZStack {
            CoverageResultView(stopReasons: stopReasons)
                .environment(viewModel)
                .safeAreaInset(edge: .top, spacing: -10) {
                    CoverageHeader(
                        title: "Coverage Test Results",
                        action: .init(title: "Close", action: onClose)
                    ) {
                        EmptyView()
                    }
                }
        }
        .navigationBarHidden(true)
    }
}

#Preview {
    TestCoverageResultView(
        stopReasons: [.insufficientLocationAccuracy(duration: 30*60)],
        onClose: {}
    )
    .environment(NetworkCoverageFactory().makeReadOnlyCoverageViewModel(fences: Fence.mockFences))
}
