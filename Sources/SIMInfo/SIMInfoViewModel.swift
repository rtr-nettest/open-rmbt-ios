//
//  SIMInfoViewModel.swift
//  RMBT
//

import Foundation
import Observation

@MainActor
@Observable
final class SIMInfoViewModel {
    private(set) var summary: SIMInfoSummary
    private(set) var items: [SIMInfoItem]

    private let provider: CellularSnapshotProviding

    init(provider: CellularSnapshotProviding = CTTelephonyCellularSnapshotProvider()) {
        self.provider = provider
        let snapshot = provider.currentSnapshot()
        self.summary = SIMInfoSnapshotBuilder.makeSummary(from: snapshot)
        self.items = SIMInfoSnapshotBuilder.makeItems(from: snapshot)
    }

    func refresh() {
        let snapshot = provider.currentSnapshot()
        summary = SIMInfoSnapshotBuilder.makeSummary(from: snapshot)
        items = SIMInfoSnapshotBuilder.makeItems(from: snapshot)
    }

    /// Begins live updates; the screen refreshes automatically when the data service or a radio
    /// technology changes.
    func startObserving() {
        provider.observeChanges { [weak self] in
            self?.refresh()
        }
    }

    func stopObserving() {
        provider.stopObserving()
    }
}
