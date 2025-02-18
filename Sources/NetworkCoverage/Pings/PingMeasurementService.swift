//
//  PingMeasurementService.swift
//  RMBT
//
//  Created by Jiri Urbasek on 12/12/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import Foundation
import Network

struct PingMeasurementService {
    let clock: any Clock<Duration>

    func pings() -> PingsSequence {
        PingsSequence(
            //pingSender: HTTPPingSender(pingURL: pingURL, urlSession: .init(configuration: .ephemeral)),
            pingSender: UDPPingSession(
                sessionInitiator: MockSessionInitiator(),
                createUDPClient: {
                    UDPClient(host: .init($0.serverAddress), port: NWEndpoint.Port(rawValue: $0.serverPort) ?? 444)
                },
                timeoutIntervalMs: 1000,
                now: RMBTHelpers.RMBTCurrentNanos
            ),
            clock: clock,
            frequency: .milliseconds(500)
        )
    }

    private var pingURL: URL {
        RMBTControlServer.shared.checkIpv4 ?? URL(string: RMBTConfig.shared.RMBT_CONTROL_SERVER_URL + "/ip")!
    }
}


struct MockSessionInitiator: UDPPingSession.SessionInitiating {
    func initiate() async throws -> UDPPingSession.SessionInitiation {
        .init(
            serverAddress: "udp.netztest.at",
            serverPort: 444,
            token: "Z7S/rtvUtKGneuuznK9EfQ=="
        )
    }
}

extension UDPPingSession: PingsSequence.PingSending {}
