//
//  SimulatorNetworkConnectionTypeUpdatesService.swift
//  RMBT
//
//  Created by Jiri Urbasek on 16.09.2025.
//

import Foundation

/// Simulator-only implementation that always reports `.cellular`.
/// This bypasses Wi‑Fi protection logic when running in the iOS Simulator.
struct SimulatorNetworkConnectionTypeUpdatesService: NetworkConnectionTypeUpdatesService {
    let now: @Sendable () -> Date

    @MainActor
    func networkConnectionTypes() -> AsyncStream<NetworkTypeUpdate> {
        AsyncStream { continuation in
            continuation.yield(.init(type: .cellular, timestamp: now()))
        }
    }
}

