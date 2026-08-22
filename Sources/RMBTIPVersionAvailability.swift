//
//  RMBTIPVersionAvailability.swift
//  RMBT
//
//  Tracks whether the current connection can reach the internet over IPv4 and/or IPv6,
//  derived from the start-page IP request (`ConnectivityInfo`). Both NAT and non-NAT
//  connections count as "available" — the only requirement is that the IP request for
//  that version succeeded (an external address was obtained).
//
//  This is a lightweight, process-wide cache updated by the intro screen whenever a
//  connectivity check completes, so the settings screen can gate the IPv4/IPv6-only
//  restrictions and the start-test flow can validate them.
//

import Foundation

final class RMBTIPVersionAvailability {
    static let shared = RMBTIPVersionAvailability()

    private(set) var ipv4Available = false
    private(set) var ipv6Available = false

    private init() {}

    /// Update the cache from the latest connectivity result.
    func update(with info: ConnectivityInfo) {
        ipv4Available = info.ipv4.connectionAvailable
        ipv6Available = info.ipv6.connectionAvailable
    }

    /// Whether the given restriction can currently be satisfied by the connection.
    func isAvailable(forRestriction restriction: IPVersionRestriction) -> Bool {
        switch restriction {
        case .ipv4Only: return ipv4Available
        case .ipv6Only: return ipv6Available
        }
    }

    /// Pure decision used to gate starting a test: is the active IP-version restriction (if any)
    /// satisfiable given the current per-version reachability? With no restriction, always true.
    static func restrictionSatisfied(forceIPv4: Bool, forceIPv6: Bool, ipv4Available: Bool, ipv6Available: Bool) -> Bool {
        if forceIPv4 { return ipv4Available }
        if forceIPv6 { return ipv6Available }
        return true
    }
}

enum IPVersionRestriction {
    case ipv4Only
    case ipv6Only
}
