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
    let onClose: () -> Void
    
    var body: some View {
        @Bindable var viewModel = viewModel
        ZStack {
            FencesMapView(
                fenceItems: viewModel.fenceItems,
                locations: viewModel.locations.map { LocationUpdate(location: $0, timestamp: $0.timestamp) },
                selectedFenceItem: $viewModel.selectedFenceItem,
                selectedFenceDetail: viewModel.selectedFenceDetail,
                fenceRadius: viewModel.fenceRadius,
                isExpertMode: false,
                showsSettingsButton: false,
                showsSettings: false,
                onSettingsToggle: {},
                trackUserLocation: false
            )
            .safeAreaInset(edge: .top, spacing: -10) {
                CoverageHeader(title: "Coverage Test Results", action: .init(title: "Close", action: onClose))
            }
        }
        .navigationBarHidden(true)
    }
}

#Preview {
    NavigationStack {
        CoverageResultView(onClose: {})
            .environment(NetworkCoverageFactory().makeReadOnlyCoverageViewModel(fences: Fence.mockFences))
    }
}
