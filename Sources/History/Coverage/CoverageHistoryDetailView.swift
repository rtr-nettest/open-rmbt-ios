//
//  CoverageHistoryDetailView.swift
//  RMBT
//
//  Created by Jiri Urbasek on 18/08/2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import SwiftUI
import CoreLocation

enum CoverageHistoryError: LocalizedError {
    case missingTestUUID
    case networkFailure(Error)
    case invalidData(String)
    case apiTimeout
    case insufficientData
    
    var errorDescription: String? {
        switch self {
        case .missingTestUUID:
            return "Test identifier is missing or invalid"
        case .networkFailure(let error):
            return "Network connection failed: \(error.localizedDescription)"
        case .invalidData(let details):
            return "Invalid coverage data: \(details)"
        case .apiTimeout:
            return "Request timed out. Please try again."
        case .insufficientData:
            return "Not enough coverage data to display"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .missingTestUUID:
            return "Please select a valid coverage test from the history list"
        case .networkFailure:
            return "Check your internet connection and try again"
        case .invalidData:
            return "This coverage test data may be corrupted"
        case .apiTimeout:
            return "Try again with a better network connection"
        case .insufficientData:
            return "This test may not have completed successfully"
        }
    }
}

struct CoverageHistoryDetailView: View {
    let coverageResult: RMBTHistoryCoverageResult
    @State private var detailService = CoverageHistoryDetailService()

    @State private var coverageViewModel: NetworkCoverageViewModel?
    @State private var isLoading = true
    @State private var error: CoverageHistoryError?
    @State private var showMoreDetails = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            switch (isLoading, error, coverageViewModel) {
            case (true, _, _):
                CoverageLoadingView()
            case (false, .some(let error), _):
                CoverageErrorView(error: error) {
                    await retry()
                }
            case (false, .none, .some(let viewModel)):
                ZStack {
                    HistoryCoverageResultView(stopReasons: [])
                        .environment(viewModel)

                    // Floating "Test details" button
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(NSLocalizedString("Test details", comment: "")) {
                                showMoreDetails = true
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
            await loadCoverageData()
        }
        .sheet(isPresented: $showMoreDetails) {
            NavigationStack {
                CoverageTestDetailsView(model: CoverageTestDetailsModel(result: coverageResult))
            }
        }
    }
    
    private func loadCoverageData() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        guard let testUUID = coverageResult.openTestUuid else {
            await MainActor.run {
                self.error = .missingTestUUID
                self.isLoading = false
            }
            return
        }
        
        do {
            let detail = try await detailService.loadCoverageDetails(for: testUUID)
            
            // Validate that we have sufficient data
            guard !detail.fences.isEmpty else {
                throw CoverageHistoryError.insufficientData
            }
            
            await MainActor.run {
                self.coverageViewModel = NetworkCoverageFactory().makeReadOnlyCoverageViewModel(fences: detail.fences)
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
    
    private func retry() async {
        await loadCoverageData()
    }
}

// MARK: - Component Views

struct CoverageLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading coverage data...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

struct CoverageErrorView: View {
    let error: CoverageHistoryError
    let onRetry: () async -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            
            VStack(spacing: 12) {
                Text("Error Loading Coverage Data")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                if let description = error.errorDescription {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Button("Try Again") {
                Task { await onRetry() }
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

struct CoverageEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Coverage Data Available")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("This test may not have completed successfully or contains no coverage information.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    let mockItem = HistoryItem()
    mockItem.testUuid = "test-uuid"
    mockItem.openTestUuid = "open-test-uuid"
    mockItem.timeString = "Dec 18 14:30"
    mockItem.fencesCount = 5
    mockItem.isCoverageFences = true
    
    let mockResult = RMBTHistoryCoverageResult(historyItem: mockItem)
    
    return NavigationView {
        CoverageHistoryDetailView(coverageResult: mockResult)
    }
}
