//
//  SIMInfoModels.swift
//  RMBT
//
//  Proof-of-concept models that describe the cellular services iOS exposes through
//  CoreTelephony, used to verify what dual-SIM information is actually available.
//
//  Important: CoreTelephony exposes opaque *service* identifiers, not physical SIM cards.
//  It does not surface the user's SIM label, physical slot, eSIM vs pSIM, ICCID, or a
//  "primary/secondary" identity. These models therefore describe "cellular services exposed
//  by CoreTelephony", and deliberately avoid claiming anything about physical SIMs.
//

import Foundation

/// Carrier metadata as reported by `CTCarrier`.
///
/// `CTCarrier` and `serviceSubscriberCellularProviders` are deprecated since iOS 16.0 with no
/// replacement and return placeholder values (`"--"`, `"65535"`) on iOS 16.4+. We still surface
/// whatever the OS returns so the diagnostic screen reflects reality, but it must never be used
/// for business logic or backend truth.
struct CarrierDetails: Equatable, Sendable {
    var carrierName: String?
    var mobileCountryCode: String?
    var mobileNetworkCode: String?
    var isoCountryCode: String?
    var allowsVOIP: Bool?

    /// Apple returns these placeholders once the per-SIM carrier identity was locked down.
    var looksLikePlaceholder: Bool {
        let placeholderName = carrierName == nil || carrierName == "--" || carrierName?.isEmpty == true
        let placeholderMCC = mobileCountryCode == nil || mobileCountryCode == "65535"
        let placeholderMNC = mobileNetworkCode == nil || mobileNetworkCode == "65535"
        return placeholderName && placeholderMCC && placeholderMNC
    }
}

/// Raw, OS-provided snapshot of all cellular services. This is the pure input to
/// `SIMInfoSnapshotBuilder`, deliberately free of CoreTelephony so it can be unit tested.
struct CellularSnapshot: Equatable, Sendable {
    /// Keyed by opaque service identifier (e.g. `"0000000100000001"`), value is a
    /// `CTRadioAccessTechnology*` constant. Mirrors `serviceCurrentRadioAccessTechnology`
    /// (public, non-deprecated).
    var radioTechnologyByService: [String: String]
    /// Keyed by the same service identifiers. Mirrors `serviceSubscriberCellularProviders`
    /// (deprecated since iOS 16.0, no replacement).
    var carrierByService: [String: CarrierDetails]
    /// The service identifier currently carrying cellular **data** (`dataServiceIdentifier`,
    /// public, non-deprecated). Does not describe the voice/SMS line.
    var dataServiceIdentifier: String?

    init(
        radioTechnologyByService: [String: String] = [:],
        carrierByService: [String: CarrierDetails] = [:],
        dataServiceIdentifier: String? = nil
    ) {
        self.radioTechnologyByService = radioTechnologyByService
        self.carrierByService = carrierByService
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
    /// Whether the service is reported by a non-deprecated API (the radio-technology dictionary or
    /// `dataServiceIdentifier`). `false` means it was only seen via the deprecated carrier API and
    /// should be treated as low confidence.
    let isReportedByReliableAPI: Bool
    /// Carrier details (deprecated API; may be placeholders on iOS 16.4+).
    let carrier: CarrierDetails?
}

/// High-level summary across all detected services.
///
/// Counts are split by data source so the UI never presents deprecated, low-confidence data as a
/// definitive SIM count.
struct SIMInfoSummary: Equatable, Sendable {
    /// Services reported by non-deprecated APIs: `serviceCurrentRadioAccessTechnology` keys plus
    /// `dataServiceIdentifier`. This is the reliable count.
    let reliableServiceCount: Int
    /// Services reported by the deprecated `serviceSubscriberCellularProviders` API. Low confidence.
    let subscriberServiceCount: Int
    /// Distinct services across both sources (equals the number of listed items).
    let totalServiceCount: Int
    let dataServiceIdentifier: String?

    /// Whether any cellular service is exposed at all.
    var hasCellularService: Bool { totalServiceCount >= 1 }
    /// Whether the reliable (non-deprecated) API exposes more than one cellular service. Used in
    /// preference to the total so a deprecated placeholder carrier entry cannot imply dual SIM.
    var exposesMultipleReliableServices: Bool { reliableServiceCount >= 2 }
    /// Whether the deprecated carrier API reports a different number of services than the reliable
    /// API — worth surfacing so the discrepancy is visible rather than silently resolved.
    var subscriberCountDiffersFromReliable: Bool { subscriberServiceCount != reliableServiceCount }
}

/// Pure transformation from an OS snapshot into display models. No CoreTelephony here so it is
/// fully unit testable.
enum SIMInfoSnapshotBuilder {
    static func makeSummary(from snapshot: CellularSnapshot) -> SIMInfoSummary {
        let reliable = reliableServiceIdentifiers(in: snapshot)
        let subscriber = Set(snapshot.carrierByService.keys)
        return SIMInfoSummary(
            reliableServiceCount: reliable.count,
            subscriberServiceCount: subscriber.count,
            totalServiceCount: reliable.union(subscriber).count,
            dataServiceIdentifier: snapshot.dataServiceIdentifier
        )
    }

    static func makeItems(from snapshot: CellularSnapshot) -> [SIMInfoItem] {
        let reliable = reliableServiceIdentifiers(in: snapshot)
        let allIdentifiers = reliable.union(snapshot.carrierByService.keys).sorted()

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
                isRegistered: isRegistered,
                isReportedByReliableAPI: reliable.contains(serviceID),
                carrier: snapshot.carrierByService[serviceID]
            )
        }
    }

    /// Service identifiers known through non-deprecated APIs: the radio-technology dictionary and
    /// the current data service identifier. Including `dataServiceIdentifier` ensures a transient
    /// snapshot that has a data identifier but momentarily empty dictionaries is not reported as
    /// "no cellular".
    private static func reliableServiceIdentifiers(in snapshot: CellularSnapshot) -> Set<String> {
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
