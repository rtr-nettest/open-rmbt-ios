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
    private(set) var airplaneModeHint: AirplaneModeHint

    private let provider: CellularSnapshotProviding
    private let pathMonitor: NetworkPathMonitoring
    private var latestSnapshot: CellularSnapshot

    init(
        provider: CellularSnapshotProviding = CTTelephonyCellularSnapshotProvider(),
        pathMonitor: NetworkPathMonitoring = NWPathNetworkMonitor()
    ) {
        self.provider = provider
        self.pathMonitor = pathMonitor
        let snapshot = provider.currentSnapshot()
        self.latestSnapshot = snapshot
        self.summary = SIMInfoSnapshotBuilder.makeSummary(from: snapshot)
        self.items = SIMInfoSnapshotBuilder.makeItems(from: snapshot)
        self.airplaneModeHint = ConnectivityHeuristic.airplaneModeHint(
            hasNetworkPath: pathMonitor.hasNetworkPath,
            hasCellularRadio: ConnectivityHeuristic.hasCellularRadio(in: snapshot)
        )
    }

    func refresh() {
        let snapshot = provider.currentSnapshot()
        latestSnapshot = snapshot
        summary = SIMInfoSnapshotBuilder.makeSummary(from: snapshot)
        items = SIMInfoSnapshotBuilder.makeItems(from: snapshot)
        recomputeAirplaneModeHint()
    }

    /// Begins live updates; the screen refreshes automatically when the data service, a radio
    /// technology, or the network path changes.
    func startObserving() {
        provider.observeChanges { [weak self] in
            self?.refresh()
        }
        pathMonitor.startMonitoring { [weak self] in
            self?.recomputeAirplaneModeHint()
        }
    }

    func stopObserving() {
        provider.stopObserving()
        pathMonitor.stopMonitoring()
    }

    private func recomputeAirplaneModeHint() {
        airplaneModeHint = ConnectivityHeuristic.airplaneModeHint(
            hasNetworkPath: pathMonitor.hasNetworkPath,
            hasCellularRadio: ConnectivityHeuristic.hasCellularRadio(in: latestSnapshot)
        )
    }
}
