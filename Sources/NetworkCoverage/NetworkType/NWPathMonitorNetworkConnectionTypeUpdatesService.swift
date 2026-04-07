//
//  NWPathMonitorNetworkConnectionTypeUpdatesService.swift
//  RMBT
//
//  Copyright 2025 appscape gmbh. All rights reserved.
//

import Foundation
import Network
import UIKit

struct NWPathMonitorNetworkConnectionTypeUpdatesService: NetworkConnectionTypeUpdatesService {
    let now: @Sendable () -> Date

    func networkConnectionTypes() -> AsyncStream<NetworkTypeUpdate> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            var lastEmitted: NetworkTypeUpdate.NetworkConnectionType?

            monitor.pathUpdateHandler = { path in
                let interfaces = path.availableInterfaces.map { "\($0.name):\($0.type)" }.joined(separator: ",")
                let appState = DispatchQueue.main.sync { UIApplication.shared.applicationState.rawValue }
                Log.logger.debug("[NWPathMonitor] callback: status=\(path.status), interfaces=[\(interfaces)], appState=\(appState)")

                let type: NetworkTypeUpdate.NetworkConnectionType? = {
                    guard path.status == .satisfied else { return nil }
                    if path.usesInterfaceType(.wifi) { return .wifi }
                    else if path.usesInterfaceType(.cellular) { return .cellular }
                    return nil
                }()

                guard let type, type != lastEmitted else {
                    Log.logger.debug("[NWPathMonitor] no change from \(lastEmitted.map(String.init(describing:)) ?? "nil")")
                    return
                }
                Log.logger.info("[NWPathMonitor] network type changed: \(lastEmitted.map(String.init(describing:)) ?? "nil") → \(type)")
                lastEmitted = type
                continuation.yield(.init(type: type, timestamp: now()))
            }

            monitor.start(queue: DispatchQueue(label: "at.rmbt.coverage.nwpathmonitor"))
            continuation.onTermination = { _ in monitor.cancel() }
        }
    }
}
