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
    private let detailService: CoverageHistoryDetailService
    
    @State private var coverageViewModel: NetworkCoverageViewModel?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    init(coverageResult: RMBTHistoryCoverageResult, detailService: CoverageHistoryDetailService = CoverageHistoryDetailService()) {
        self.coverageResult = coverageResult
        self.detailService = detailService
    }
    
    var body: some View {
        Group {
            if isLoading {
                VStack {
                    ProgressView("Loading coverage data...")
                        .scaleEffect(1.2)
                    Spacer()
                }
                .padding()
            } else if let errorMessage = errorMessage {
                VStack {
                    Text("Error loading coverage data")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .padding()
            } else if let coverageViewModel = coverageViewModel {
                CoverageResultView(onClose: {
                    dismiss()
                })
                .environment(coverageViewModel)
            } else {
                VStack {
                    Text("No coverage data available")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
            }
        }
        .navigationBarHidden(true)
        .task {
            await loadCoverageData()
        }
    }
    
    private func loadCoverageData() async {
        guard let testUUID = coverageResult.openTestUuid else {
            await MainActor.run {
                self.errorMessage = CoverageHistoryError.missingTestUUID.localizedDescription
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
        } catch let error as CoverageHistoryError {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = CoverageHistoryError.networkFailure(error).localizedDescription
                self.isLoading = false
            }
        }
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