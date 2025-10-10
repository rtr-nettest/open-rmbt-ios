//
//  CoverageResultView.swift
//  RMBT
//
//  Created by Jiri Urbasek on 7/21/25.
//  Copyright 2024 appscape gmbh. All rights reserved.
//

import SwiftUI
import CoreLocation

struct CoverageResultView: View {
    @Environment(NetworkCoverageViewModel.self) private var viewModel
    let stopReasons: [StopTestReason]
    let onClose: () -> Void
    
    var body: some View {
        @Bindable var viewModel = viewModel
        ZStack {
            FencesMapView(
                visibleFenceItems: viewModel.visibleFenceItems,
                fencePolylineSegments: viewModel.fencePolylineSegments,
                mapRenderMode: viewModel.mapRenderMode,
                locations: viewModel.locations.map { LocationUpdate(location: $0, timestamp: $0.timestamp) },
                selectedFenceItem: $viewModel.selectedFenceItem,
                selectedFenceDetail: viewModel.selectedFenceDetail,
                fenceRadius: viewModel.fenceRadius,
                isExpertMode: false,
                showsSettingsButton: false,
                showsSettings: false,
                onSettingsToggle: {},
                trackUserLocation: false,
                onVisibleRegionChange: viewModel.updateVisibleRegion(_:)
            )
            .safeAreaInset(edge: .top, spacing: -10) {
                VStack(spacing: 0) {
                    CoverageHeader(title: "Coverage Test Results", action: .init(title: "Close", action: onClose))

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(stopReasons.enumerated()), id: \.offset) { _, reason in
                            let content = content(for: reason)
                            WarningMessageView(title: content.title, description: content.description)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.85))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func content(for reason: StopTestReason) -> (title: String, description: String) {
        switch reason {
        case .insufficientLocationAccuracy(let duration):
            let minutes = Int(duration / 60)
            return (
                title: "Waiting for GPS",
                description: "No sufficiently accurate location was obtained within \(minutes) minutes."
            )
        }
    }
}

#Preview {
    NavigationStack {
        CoverageResultView(stopReasons: [.insufficientLocationAccuracy(duration: 30*60)], onClose: {})
            .environment(NetworkCoverageFactory().makeReadOnlyCoverageViewModel(fences: Fence.mockFences))
    }
}
