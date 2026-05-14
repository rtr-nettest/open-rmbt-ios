//
//  NWPathMonitorNetworkConnectionTypeUpdatesService.swift
//  RMBT
//
//  Copyright 2025 appscape gmbh. All rights reserved.
//

import Foundation
import Network
import NetworkExtension
import UIKit

struct NWPathMonitorNetworkConnectionTypeUpdatesService: NetworkConnectionTypeUpdatesService {
    let now: @Sendable () -> Date

    func networkConnectionTypes() -> AsyncStream<NetworkTypeUpdate> {
        AsyncStream { continuation in
            let queue = DispatchQueue(label: "at.rmbt.coverage.nwpathmonitor")
            let primaryMonitor = NWPathMonitor()
            let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)

            var lastEmittedType: NetworkTypeUpdate.NetworkConnectionType?
            var lastWifiAvailable: Bool?

            primaryMonitor.pathUpdateHandler = { path in
                let appState = DispatchQueue.main.sync { UIApplication.shared.applicationState.rawValue }
                let ifs = path.availableInterfaces.map { "\($0.name):\($0.type)" }.joined(separator: ",")
                let wifiAvailable = wifiMonitor.currentPath.status == .satisfied

                let type: NetworkTypeUpdate.NetworkConnectionType? = {
                    guard path.status == .satisfied else { return nil }
                    if path.usesInterfaceType(.wifi) { return .wifi }
                    if path.usesInterfaceType(.cellular) { return .cellular }
                    return nil
                }()

                let typeDesc = type.map(String.init(describing:)) ?? "nil"
                Log.logger.debug("[NetPath] tick status=\(path.status) type=\(typeDesc) wifi_avail=\(wifiAvailable) ifs=[\(ifs)] appState=\(appState)")

                guard let type, type != lastEmittedType else { return }
                Log.logger.info("[NetPath] type: \(lastEmittedType.map(String.init(describing:)) ?? "nil") → \(type)")
                lastEmittedType = type
                continuation.yield(.init(type: type, timestamp: now()))
            }

            wifiMonitor.pathUpdateHandler = { path in
                let available = path.status == .satisfied
                guard lastWifiAvailable != available else { return }
                let previous = lastWifiAvailable
                lastWifiAvailable = available
                Log.logger.info("[NetPath] wifi_avail: \(previous.map(String.init(describing:)) ?? "nil") → \(available)")
                guard available else { return }

                // WiFi just became reachable: probe association so a later log review can tell
                // "WiFi associated but routed via cellular" apart from "WiFi not associated".
                NEHotspotNetwork.fetchCurrent { network in
                    if let network {
                        Log.logger.info("[NetPath] wifi_assoc ssid=\"\(network.ssid)\" bssid=\(network.bssid)")
                    } else {
                        Log.logger.info("[NetPath] wifi_assoc: nil (path satisfied but NEHotspotNetwork returned nil — check location auth)")
                    }
                }
            }

            primaryMonitor.start(queue: queue)
            wifiMonitor.start(queue: queue)
            continuation.onTermination = { _ in
                primaryMonitor.cancel()
                wifiMonitor.cancel()
            }
        }
    }
}
