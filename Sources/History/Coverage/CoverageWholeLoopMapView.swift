//
//  CoverageWholeLoopMapView.swift
//  RMBT
//
//  Copyright © 2026 appscape gmbh. All rights reserved.
//

import SwiftUI

/// Shows an entire signal-measurement loop as a single map, with the fences of all its segments
/// (open_test_uuids) aggregated into one view — the same map the user sees when a measurement ends.
///
/// The bottom "Details" button opens the list of the individual segments that make up the loop
/// (mirrors Android's whole-loop mode of `CoverageResultsActivity`, where "Test details" becomes
/// "Details" and opens `CoverageLoopSegmentsActivity`).
struct CoverageWholeLoopMapView: View {
    let openTestUUIDs: [String]
    /// Invoked when the user taps "Details" — pushes the segment list.
    let onDetails: () -> Void

    @State private var detailService = CoverageHistoryDetailService()
    @State private var coverageViewModel: NetworkCoverageViewModel?
    @State private var isLoading = true
    @State private var error: CoverageHistoryError?

    var body: some View {
        Group {
            switch (isLoading, error, coverageViewModel) {
            case (true, _, _):
                CoverageLoadingView()
            case (false, .some(let error), _):
                CoverageErrorView(error: error) {
                    await load()
                }
            case (false, .none, .some(let viewModel)):
                ZStack {
                    HistoryCoverageResultView(stopReasons: [])
                        .environment(viewModel)

                    // Floating "Details" button (opens the segment list).
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(NSLocalizedString("coverage_details_button", comment: "")) {
                                onDetails()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.brand)
                            .padding(16)
                        }
                    }
                }
            case (false, .none, .none):
                CoverageEmptyView()
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }

        guard !openTestUUIDs.isEmpty else {
            await MainActor.run {
                self.error = .missingTestUUID
                self.isLoading = false
            }
            return
        }

        do {
            let fences = try await detailService.loadAggregatedFences(for: openTestUUIDs)
            guard !fences.isEmpty else {
                throw CoverageHistoryError.insufficientData
            }
            await MainActor.run {
                self.coverageViewModel = NetworkCoverageFactory().makeReadOnlyCoverageViewModel(fences: fences)
                self.isLoading = false
            }
        } catch let coverageError as CoverageHistoryError {
            await MainActor.run {
                self.error = coverageError
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = .networkFailure(error)
                self.isLoading = false
            }
        }
    }
}
