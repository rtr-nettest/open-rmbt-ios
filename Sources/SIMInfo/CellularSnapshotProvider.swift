//
//  CellularSnapshotProvider.swift
//  RMBT
//
//  Reads the current cellular service information from CoreTelephony and converts it into a
//  CoreTelephony-free `CellularSnapshot`, and reports live changes.
//

import Foundation
import CoreTelephony

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
    private var changeHandler: (@MainActor () -> Void)?
    private var radioTechnologyObserver: NSObjectProtocol?

    init(networkInfo: CTTelephonyNetworkInfo = CTTelephonyNetworkInfo()) {
        self.networkInfo = networkInfo
        super.init()
    }

    deinit {
        if let radioTechnologyObserver {
            NotificationCenter.default.removeObserver(radioTechnologyObserver)
        }
    }

    func currentSnapshot() -> CellularSnapshot {
        CellularSnapshot(
            radioTechnologyByService: networkInfo.serviceCurrentRadioAccessTechnology ?? [:],
            carrierByService: carrierDetailsByService(),
            dataServiceIdentifier: networkInfo.dataServiceIdentifier
        )
    }

    // MARK: - Live updates

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        changeHandler = handler
        // Fires when dataServiceIdentifier changes (e.g. data SIM switch).
        networkInfo.delegate = self
        // Fires when a service's current radio access technology changes (non-deprecated, iOS 12+).
        radioTechnologyObserver = NotificationCenter.default.addObserver(
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
            NotificationCenter.default.removeObserver(radioTechnologyObserver)
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

    // MARK: - Carrier (deprecated)

    /// `serviceSubscriberCellularProviders` / `CTCarrier` are deprecated since iOS 16.0 with no
    /// replacement and return placeholder values on iOS 16.4+. We intentionally still read them for
    /// this diagnostic so the screen shows exactly what the OS reports today.
    private func carrierDetailsByService() -> [String: CarrierDetails] {
        guard let providers = legacySubscriberProviders() else { return [:] }
        return providers.reduce(into: [:]) { result, entry in
            let carrier = entry.value
            result[entry.key] = CarrierDetails(
                carrierName: carrier.carrierName,
                mobileCountryCode: carrier.mobileCountryCode,
                mobileNetworkCode: carrier.mobileNetworkCode,
                isoCountryCode: carrier.isoCountryCode,
                allowsVOIP: carrier.allowsVOIP
            )
        }
    }

    @available(iOS, deprecated: 16.0, message: "Deprecated by Apple; used intentionally for SIM diagnostics.")
    private func legacySubscriberProviders() -> [String: CTCarrier]? {
        networkInfo.serviceSubscriberCellularProviders
    }
}
