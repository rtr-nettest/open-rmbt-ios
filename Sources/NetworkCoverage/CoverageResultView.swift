//
//  CoverageResultView.swift
//  RMBT
//
//  Created by Claude Code on 7/21/25.
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
                selectedFenceID: $viewModel.selectedFenceID,
                selectedFenceDetail: viewModel.selectedFenceDetail,
                fenceRadius: viewModel.fenceRadius,
                isExpertMode: false,
                showsSettingsButton: false,
                showsSettings: false,
                onSettingsToggle: {},
                trackUserLocation: false
            )
            
            VStack {
                HStack {
                    Text("Coverage Test Results")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: onClose) {
                        Text("Close")
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color("greenButtonBackground"))
                            .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.85))
                .cornerRadius(8)
                .padding()
                
                Spacer()
            }
        }
        .navigationBarHidden(true)
    }
}

#Preview {
    NavigationStack {
        CoverageResultView(onClose: {})
            .environment(NetworkCoverageViewModel(
                fences: [
                    .init(
                        startingLocation: CLLocation(
                            latitude: 49.74805411063806,
                            longitude: 13.37696845562318
                        ),
                        dateEntered: .init(timeIntervalSince1970: 1734526653),
                        technology: "3G/HSDPA",
                        avgPing: .milliseconds(122)
                    ),
                    .init(
                        startingLocation: CLLocation(
                            latitude: 49.747849194587204,
                            longitude: 13.376917714305671
                        ),
                        dateEntered: .init(timeIntervalSince1970: 1734526656),
                        technology: "4G/LTE",
                        pings: [.init(result: .interval(.milliseconds(84)), timestamp: .init(timeIntervalSince1970: 1734526656))]
                    )
                ],
                refreshInterval: 1.0,
                minimumLocationAccuracy: 10.0,
                updates: { EmptyAsyncSequence().asOpaque() },
                currentRadioTechnology: MockCurrentRadioTechnologyService(),
                sendResultsService: MockSendCoverageResultsService(),
                persistenceService: MockFencePersistenceService(),
                locale: .current
            ))
    }
}

// MARK: - Mock Services for Preview

private struct MockCurrentRadioTechnologyService: CurrentRadioTechnologyService {
    func technologyCode() -> String? { "4G" }
}

private struct MockSendCoverageResultsService: SendCoverageResultsService {
    func send(fences: [Fence]) async throws {}
}

private struct MockFencePersistenceService: FencePersistenceService {
    func save(_ fence: Fence) throws {}
}

private struct EmptyAsyncSequence: AsyncSequence {
    typealias Element = NetworkCoverageViewModel.Update
    
    struct AsyncIterator: AsyncIteratorProtocol {
        mutating func next() async throws -> NetworkCoverageViewModel.Update? { nil }
    }
    
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
}
