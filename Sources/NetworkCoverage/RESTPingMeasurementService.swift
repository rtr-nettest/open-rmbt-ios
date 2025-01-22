//
//  RESTPingMeasurementService.swift
//  RMBT
//
//  Created by Jiri Urbasek on 12/12/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import Foundation

struct RESTPingMeasurementService: PingMeasurementService {
    let clock: any Clock<Duration>
    let urlSession: URLSession

    func pings() -> PingsSequence {
        PingsSequence(
            urlSession: urlSession,
            request: URLRequest(url: pingURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData),
            clock: clock,
            frequency: .milliseconds(500)
        )
    }

    private var pingURL: URL {
        RMBTControlServer.shared.checkIpv4 ?? URL(string: RMBTConfig.shared.RMBT_CONTROL_SERVER_URL + "/ip")!
    }
}
