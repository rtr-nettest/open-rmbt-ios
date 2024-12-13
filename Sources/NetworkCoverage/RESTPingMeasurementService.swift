//
//  RESTPingMeasurementService.swift
//  RMBT
//
//  Created by Jiri Urbasek on 12/12/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import Foundation

struct RESTPingMeasurementService {
    let clock: any Clock<Duration>
    let urlSession: URLSession

    func start() -> some PingsAsyncSequence {
        PingsSequence(
            urlSession: urlSession,
            request: URLRequest(url: URL(string: RMBTConfig.shared.RMBT_CONTROL_SERVER_URL + "/ip")!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData),
            clock: clock,
            frequency: .milliseconds(500)
        )
    }
}
