//
//  SIMInfoModels.swift
//  RMBT
//
//  Models that describe the cellular services iOS exposes through CoreTelephony, used to verify
//  what dual-SIM information is actually available, plus a best-effort offline/airplane-mode hint.
//
//  Important: CoreTelephony exposes opaque *service* identifiers, not physical SIM cards.
//  It does not surface the user's SIM label, physical slot, eSIM vs pSIM, ICCID, or a
//  "primary/secondary" identity. These models therefore describe "cellular services exposed
//  by CoreTelephony", and deliberately avoid claiming anything about physical SIMs.
//
//  Only the reliable, non-deprecated API is used: `serviceCurrentRadioAccessTechnology` and
//  `dataServiceIdentifier`. The deprecated `serviceSubscriberCellularProviders` / `CTCarrier`
//  carrier API was dropped because it returns placeholder values on iOS 16.4+ and yields nothing
//  useful.
//

import Foundation

/// Raw, OS-provided snapshot of all cellular services. This is the pure input to
/// `SIMInfoSnapshotBuilder`, deliberately free of CoreTelephony so it can be unit tested.
struct CellularSnapshot: Equatable, Sendable {
    /// Keyed by opaque service identifier (e.g. `"0000000100000001"`), value is a
    /// `CTRadioAccessTechnology*` constant. Mirrors `serviceCurrentRadioAccessTechnology`
    /// (public, non-deprecated).
    var radioTechnologyByService: [String: String]
    /// The service identifier currently carrying cellular **data** (`dataServiceIdentifier`,
    /// public, non-deprecated). Does not describe the voice/SMS line.
    var dataServiceIdentifier: String?

    init(
        radioTechnologyByService: [String: String] = [:],
        dataServiceIdentifier: String? = nil
    ) {
        self.radioTechnologyByService = radioTechnologyByService
        self.dataServiceIdentifier = dataServiceIdentifier
    }
}

/// A single cellular service prepared for display.
///
/// `displayName` is positional only (`"Cellular service 1"`). The ordering is deterministic for a
/// stable UI but does not correspond to a physical SIM slot or any user-facing SIM identity.
struct SIMInfoItem: Equatable, Sendable, Identifiable {
    var id: String { serviceIdentifier }

    /// Opaque CoreTelephony service identifier.
    let serviceIdentifier: String
    /// Positional label such as `"Cellular service 1"`. Not a physical slot or SIM name.
    let displayName: String
    /// Friendly radio technology, e.g. `"4G/LTE"`. `nil` when the service is not registered to any
    /// radio (no signal) or the constant is unknown.
    let technologyLabel: String?
    /// Coarse generation derived from `technologyLabel`, e.g. `"4G"`.
    let generationLabel: String?
    /// Whether this service is the one currently providing cellular **data**. This does not imply
    /// it carries voice/SMS, nor which path traffic uses while on Wi-Fi.
    let isDataService: Bool
    /// Whether the service is registered to a radio (has a current radio technology).
    let isRegistered: Bool
}

/// High-level summary across all detected services.
struct SIMInfoSummary: Equatable, Sendable {
    /// Number of cellular services exposed by the non-deprecated API.
    let serviceCount: Int
    let dataServiceIdentifier: String?

    /// Whether any cellular service is exposed at all.
    var hasCellularService: Bool { serviceCount >= 1 }
    /// Whether more than one cellular service is exposed (i.e. dual SIM is observable).
    var exposesMultipleServices: Bool { serviceCount >= 2 }
}

/// Pure transformation from an OS snapshot into display models. No CoreTelephony here so it is
/// fully unit testable.
enum SIMInfoSnapshotBuilder {
    static func makeSummary(from snapshot: CellularSnapshot) -> SIMInfoSummary {
        SIMInfoSummary(
            serviceCount: serviceIdentifiers(in: snapshot).count,
            dataServiceIdentifier: snapshot.dataServiceIdentifier
        )
    }

    static func makeItems(from snapshot: CellularSnapshot) -> [SIMInfoItem] {
        let allIdentifiers = serviceIdentifiers(in: snapshot).sorted()

        return allIdentifiers.enumerated().map { index, serviceID in
            let rawTechnology = snapshot.radioTechnologyByService[serviceID]
            let isRegistered = !(rawTechnology ?? "").isEmpty
            let technologyLabel = friendlyTechnology(for: rawTechnology)

            return SIMInfoItem(
                serviceIdentifier: serviceID,
                displayName: "Cellular service \(index + 1)",
                technologyLabel: technologyLabel,
                generationLabel: generation(from: technologyLabel),
                isDataService: serviceID == snapshot.dataServiceIdentifier,
                isRegistered: isRegistered
            )
        }
    }

    /// Service identifiers from the radio-technology dictionary plus the current data service.
    /// Including `dataServiceIdentifier` ensures a transient snapshot that has a data identifier but
    /// momentarily empty dictionaries is not reported as "no cellular".
    private static func serviceIdentifiers(in snapshot: CellularSnapshot) -> Set<String> {
        var identifiers = Set(snapshot.radioTechnologyByService.keys)
        if let dataServiceIdentifier = snapshot.dataServiceIdentifier {
            identifiers.insert(dataServiceIdentifier)
        }
        return identifiers
    }

    /// Maps a `CTRadioAccessTechnology*` constant to a friendly label, falling back to the raw value
    /// when unknown. Reuses the project-wide mapping in `String.radioTechnologyCode`.
    private static func friendlyTechnology(for rawTechnology: String?) -> String? {
        guard let rawTechnology, !rawTechnology.isEmpty else { return nil }
        return rawTechnology.radioTechnologyCode ?? rawTechnology
    }

    private static func generation(from technologyLabel: String?) -> String? {
        guard let technologyLabel else { return nil }
        return technologyLabel.split(separator: "/").first.map(String.init)
    }
}

// MARK: - Airplane-mode / offline heuristic

/// Best-effort interpretation of the device's connectivity. iOS exposes no airplane-mode API, so
/// this is inferred from two signals and is never a certainty.
enum AirplaneModeHint: Equatable, Sendable {
    /// The network path status has not been evaluated yet.
    case undetermined
    /// At least one network path is available — the device is online.
    case connected
    /// No usable network path, but the cellular radio still reports a technology. Usually means
    /// mobile data is off or the device is briefly out of a data path rather than airplane mode.
    case noPathButRadioPresent
    /// No usable network path and the cellular radio reports nothing. The strongest "probably
    /// offline / airplane mode" signal available — but indistinguishable from being out of coverage
    /// with Wi-Fi and mobile data both off.
    case likelyAirplaneModeOrOffline
}

enum ConnectivityHeuristic {
    /// Combines whether any network path is satisfied (`NWPathMonitor`) with whether the cellular
    /// radio reports a technology. `hasNetworkPath == nil` means the path has not been evaluated yet.
    static func airplaneModeHint(hasNetworkPath: Bool?, hasCellularRadio: Bool) -> AirplaneModeHint {
        guard let hasNetworkPath else { return .undetermined }
        if hasNetworkPath { return .connected }
        return hasCellularRadio ? .noPathButRadioPresent : .likelyAirplaneModeOrOffline
    }

    /// Whether any cellular service reports a non-empty radio access technology, i.e. the cellular
    /// radio is powered up and registered.
    static func hasCellularRadio(in snapshot: CellularSnapshot) -> Bool {
        snapshot.radioTechnologyByService.values.contains { !$0.isEmpty }
    }
}
