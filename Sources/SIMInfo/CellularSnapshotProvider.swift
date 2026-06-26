//
//  CellularSnapshotProvider.swift
//  RMBT
//
//  Reads the current cellular service information from CoreTelephony and converts it into a
//  CoreTelephony-free `CellularSnapshot`, and reports live changes. Also provides a best-effort
//  network-path monitor used by the offline/airplane-mode hint.
//

import Foundation
import CoreTelephony
import Network

/// Supplies a snapshot of the device's cellular services and, optionally, notifies when that state
/// changes. Abstracted so the view model can be driven with deterministic data in tests / previews.
protocol CellularSnapshotProviding {
    func currentSnapshot() -> CellularSnapshot

    /// Registers a handler invoked on the main actor whenever the cellular state changes (data
    /// service or radio technology). Default implementation is a no-op for providers that don't
    /// support live updates (tests, previews).
    func observeChanges(_ handler: @escaping @MainActor () -> Void)
    func stopObserving()
}

extension CellularSnapshotProviding {
    func observeChanges(_ handler: @escaping @MainActor () -> Void) {}
    func stopObserving() {}
}

/// Live CoreTelephony-backed provider.
///
/// `delegate` callbacks are dispatched by CoreTelephony to a background queue, so change handling
/// hops to the main actor before invoking the handler.
final class CTTelephonyCellularSnapshotProvider: NSObject, CellularSnapshotProviding, CTTelephonyNetworkInfoDelegate {
    private let networkInfo: CTTelephonyNetworkInfo
    private let notificationCenter: NotificationCenter
    private var changeHandler: (@MainActor () -> Void)?
    private var radioTechnologyObserver: NSObjectProtocol?

    init(
        networkInfo: CTTelephonyNetworkInfo = CTTelephonyNetworkInfo(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.networkInfo = networkInfo
        self.notificationCenter = notificationCenter
        super.init()
    }

    deinit {
        if let radioTechnologyObserver {
            notificationCenter.removeObserver(radioTechnologyObserver)
        }
    }

    func currentSnapshot() -> CellularSnapshot {
        CellularSnapshot(
            radioTechnologyByService: networkInfo.serviceCurrentRadioAccessTechnology ?? [:],
            dataServiceIdentifier: networkInfo.dataServiceIdentifier
        )
    }

    // MARK: - Live updates

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        // Idempotent: drop any previous registration so repeated calls don't leak the prior
        // NotificationCenter observer or fire duplicate callbacks.
        stopObserving()
        changeHandler = handler
        // Fires when dataServiceIdentifier changes (e.g. data SIM switch).
        networkInfo.delegate = self
        // Fires when a service's current radio access technology changes (non-deprecated, iOS 12+).
        radioTechnologyObserver = notificationCenter.addObserver(
            forName: .CTServiceRadioAccessTechnologyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.notifyChange()
        }
    }

    func stopObserving() {
        networkInfo.delegate = nil
        if let radioTechnologyObserver {
            notificationCenter.removeObserver(radioTechnologyObserver)
        }
        radioTechnologyObserver = nil
        changeHandler = nil
    }

    // MARK: - CTTelephonyNetworkInfoDelegate

    func dataServiceIdentifierDidChange(_ identifier: String) {
        notifyChange()
    }

    private func notifyChange() {
        guard let handler = changeHandler else { return }
        Task { @MainActor in handler() }
    }
}

// MARK: - Network path monitoring

/// Reports whether any network path is currently satisfied. Abstracted so the view model can be
/// driven deterministically in tests.
@MainActor
protocol NetworkPathMonitoring {
    /// `nil` until the first path evaluation arrives; otherwise whether any interface has a
    /// satisfied path.
    var hasNetworkPath: Bool? { get }
    func startMonitoring(_ onChange: @escaping @MainActor () -> Void)
    func stopMonitoring()
}

/// Live `NWPathMonitor`-backed implementation.
///
/// `NWPathMonitor` delivers updates on a background queue, so each update hops to the main actor
/// before mutating state or invoking the handler. A monitor cannot be restarted after `cancel()`,
/// so a fresh one is created on every `startMonitoring` call.
@MainActor
final class NWPathNetworkMonitor: NetworkPathMonitoring {
    private let queue = DispatchQueue(label: "at.rtr.rmbt.sim-info.path-monitor")
    private var monitor: NWPathMonitor?
    private var onChange: (@MainActor () -> Void)?
    private(set) var hasNetworkPath: Bool?

    nonisolated init() {}

    func startMonitoring(_ onChange: @escaping @MainActor () -> Void) {
        stopMonitoring()
        self.onChange = onChange
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                // Ignore late callbacks from a monitor that was already replaced or cancelled.
                guard let self, self.monitor === monitor else { return }
                self.hasNetworkPath = satisfied
                self.onChange?()
            }
        }
        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
        onChange = nil
        hasNetworkPath = nil
    }
}
