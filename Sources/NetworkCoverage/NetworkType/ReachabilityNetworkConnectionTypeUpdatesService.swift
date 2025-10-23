//
//  ReachabilityNetworkConnectionTypeUpdatesService.swift
//  RMBT
//
//  Created by Jiri Urbasek on 16.09.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation

struct ReachabilityNetworkConnectionTypeUpdatesService: NetworkConnectionTypeUpdatesService {
    let now: @Sendable () -> Date

    func networkConnectionTypes() -> AsyncStream<NetworkTypeUpdate> {
        AsyncStream { continuation in
            // Map reachability status to our NetworkConnectionType
            var lastEmitted: NetworkTypeUpdate.NetworkConnectionType?
            let callback = { (status: NetworkReachability.NetworkReachabilityStatus) in
                switch status {
                case .wifi:
                    if lastEmitted != .wifi {
                        lastEmitted = .wifi
                        continuation.yield(.init(type: .wifi, timestamp: now()))
                    }
                case .mobile:
                    if lastEmitted != .cellular {
                        lastEmitted = .cellular
                        continuation.yield(.init(type: .cellular, timestamp: now()))
                    }
                default:
                    break
                }
            }

            // Start monitoring and emit initial state on the main actor
            Task { @MainActor in
                NetworkReachability.shared.startMonitoring()
                callback(NetworkReachability.shared.status)
                let token = NetworkReachability.shared.addReachabilityCallbackReturningToken(callback)

                continuation.onTermination = { _ in
                    NetworkReachability.shared.removeReachabilityCallback(token)
                }
            }
        }
    }
}
