//
//  CurrentNetworkTypeProvider.swift
//  RMBT
//
//  Copyright 2025 appscape gmbh. All rights reserved.
//

import Foundation
import Network

protocol CurrentNetworkTypeProvider: Sendable {
    func currentNetworkType() -> NetworkTypeUpdate.NetworkConnectionType?
}

final class NWPathMonitorCurrentNetworkTypeProvider: CurrentNetworkTypeProvider, @unchecked Sendable {
    private let monitor = NWPathMonitor()

    init() {
        monitor.start(queue: DispatchQueue(label: "at.rmbt.coverage.nwpath.poll"))
    }

    func currentNetworkType() -> NetworkTypeUpdate.NetworkConnectionType? {
        let path = monitor.currentPath
        guard path.status == .satisfied else { return nil }
        if path.usesInterfaceType(.wifi) { return .wifi }
        else if path.usesInterfaceType(.cellular) { return .cellular }
        return nil
    }

    deinit { monitor.cancel() }
}
