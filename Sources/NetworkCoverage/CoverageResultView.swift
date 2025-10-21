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
    
    var body: some View {
        @Bindable var viewModel = viewModel
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
        .ignoresSafeArea()
        .safeAreaInset(edge: .top, spacing: 0) {
            stopReasonBanner()
        }
        .navigationTitle(NSLocalizedString("Coverage Test Results", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func stopReasonBanner() -> some View {
        if !stopReasons.isEmpty {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
        }
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
        CoverageResultView(stopReasons: [.insufficientLocationAccuracy(duration: 30*60)])
            .environment(NetworkCoverageFactory().makeReadOnlyCoverageViewModel(fences: Fence.mockFences))
    }
}
