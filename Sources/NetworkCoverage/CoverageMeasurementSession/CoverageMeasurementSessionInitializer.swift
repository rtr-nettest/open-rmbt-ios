//
//  CoverageMeasurementSessionInitializer.swift
//  RMBT
//
//  Created by Jiri Urbasek on 24.02.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation

class CoverageMeasurementSessionInitializer {
    struct SessionCredentials {
        struct UDPPingCredentails {
            let pingToken: String
            let pingHost: String
            let pingPort: String
        }
        let testID: String
        let loopID: String?
        let udpPing: UDPPingCredentails
    }

    private let now: () -> Date
    private let controlServer: RMBTControlServer
    private(set) var lastTestUUID: String?
    private(set) var lastTestStartDate: Date?

    var isInitialized: Bool {
        lastTestUUID != nil && lastTestStartDate != nil
    }

    init(now: @escaping () -> Date, controlServer: RMBTControlServer) {
        self.now = now
        self.controlServer = controlServer
    }

    func startNewSession(loopID: String? = nil) async throws -> SessionCredentials {
        // before staring new session, try to resend failed-to-be-sent coverage test results, if any
        try? await NetworkCoverageFactory().persistedFencesSender.resendPersistentAreas()

        let response = try await withCheckedThrowingContinuation { continuation in
            controlServer.getCoverageRequest(
                CoverageRequestRequest(time: Int(now().timeIntervalSince1970 * 1000), measurementType: "dedicated")) { response in
                    continuation.resume(returning: response)
                } error: { error in
                    continuation.resume(throwing: error)
                }
        }
        lastTestUUID = response.testUUID
        lastTestStartDate = now()

        return SessionCredentials(
            testID: response.testUUID,
            loopID: nil,
            udpPing: .init(
                pingToken: response.pingToken,
                pingHost: response.pingHost,
                pingPort: response.pingPort
            )
        )
    }
}


import ObjectMapper

class CoverageRequestRequest: BasicRequest {
    var time: Int
    var measurementType: String
    var clientUUID: String?

    init(time: Int, measurementType: String) {
        self.time = time
        self.measurementType = measurementType
        super.init()
    }

    required init?(map: Map) {
        fatalError("init(map:) has not been implemented")
    }

    override func mapping(map: Map) {
        super.mapping(map: map)

        clientUUID <- map["client_uuid"]
        time <- map["time"]
        measurementType <- map["measurement_type_flag"]
    }
}

class SignalRequestResponse: BasicResponse {
    var testUUID: String = ""
    var pingToken: String = ""
    var pingHost: String = ""
    var pingPort: String = ""

    override func mapping(map: Map) {
        super.mapping(map: map)

        testUUID <- map["test_uuid"]
        pingToken <- map["ping_token"]
        pingHost <- map["ping_host"]
        pingPort <- map["ping_port"]
    }
}
