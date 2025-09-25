//
//  CoverageTestDetailsModel.swift
//  RMBT
//
//  Created by OpenAI Codex CLI on 25/09/2025.
//

import Foundation

protocol HistoryDetailsProvider: AnyObject {
    var timeStringIn24hFormat: String? { get }
    var fullDetailsItems: [Any]? { get }
    func ensureFullDetails(success: @escaping RMBTBlock)
}

extension RMBTHistoryResult: HistoryDetailsProvider {}

@MainActor
@Observable
final class CoverageTestDetailsModel {
    // MARK: - Inputs
    private let provider: HistoryDetailsProvider

    // MARK: - State
    var isLoading: Bool = false
    var items: [RMBTHistoryResultItem] = []
    var loadError: Error? = nil

    // MARK: - Derived
    var title: String {
        provider.timeStringIn24hFormat ?? NSLocalizedString("Test details", comment: "")
    }

    // MARK: - Init
    init(provider: HistoryDetailsProvider) {
        self.provider = provider
    }

    convenience init(result: RMBTHistoryResult) {
        self.init(provider: result)
    }

    // MARK: - API
    func reload() {
        isLoading = true
        loadError = nil
        provider.ensureFullDetails { [weak self] in
            guard let self else { return }
            // ensureFullDetails populates provider.fullDetailsItems
            if let details = self.provider.fullDetailsItems as? [RMBTHistoryResultItem] {
                self.items = details
            } else {
                self.items = []
            }
            self.isLoading = false
        }
    }
}

