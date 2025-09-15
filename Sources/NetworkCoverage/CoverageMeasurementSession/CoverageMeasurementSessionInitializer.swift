//
//  CoverageMeasurementSessionInitializer.swift
//  RMBT
//
//  Created by Jiri Urbasek on 24.02.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation

enum IPVersion {
    case IPv4
    case IPv6
}

protocol CoverageAPIService {
    func getCoverageRequest(
        _ request: CoverageRequestRequest,
        loopUUID: String?,
        success: @escaping (_ response: SignalRequestResponse) -> (),
        error failure: @escaping ErrorCallback
    )
}

extension RMBTControlServer: CoverageAPIService {}

class CoverageMeasurementSessionInitializer {
    struct SessionCredentials {
        struct UDPPingCredentails {
            let pingToken: String
            let pingHost: String
            let pingPort: String
            let ipVersion: IPVersion?
        }
        let testID: String
        let loopID: String?
        let udpPing: UDPPingCredentails
    }

    private let now: () -> Date
    private let coverageAPIService: any CoverageAPIService
    private(set) var lastTestUUID: String?
    private(set) var lastTestStartDate: Date?
    private(set) var maxCoverageSessionDuration: TimeInterval?
    private(set) var maxCoverageMeasurementDuration: TimeInterval?

    var isInitialized: Bool {
        lastTestUUID != nil && lastTestStartDate != nil
    }

    init(now: @escaping () -> Date, coverageAPIService: some CoverageAPIService) {
        self.now = now
        self.coverageAPIService = coverageAPIService
    }

    func startNewSession(loopID: String? = nil) async throws -> SessionCredentials {
        // before staring new session, try to resend failed-to-be-sent coverage test results, if any
        try? await NetworkCoverageFactory().persistedFencesSender.resendPersistentAreas()

        let response = try await withCheckedThrowingContinuation { continuation in
            coverageAPIService.getCoverageRequest(
                CoverageRequestRequest(time: Int(now().timeIntervalSince1970 * 1000), measurementType: "dedicated"),
                loopUUID: loopID
            ) { response in
                    continuation.resume(returning: response)
                } error: { error in
                    continuation.resume(throwing: error)
                }
        }
        lastTestUUID = response.testUUID
        lastTestStartDate = now()
        if let maxSessionSec = response.maxCoverageSessionSeconds {
            maxCoverageSessionDuration = TimeInterval(maxSessionSec)
        }
        if let maxMeasurementSec = response.maxCoverageMeasurementSeconds {
            maxCoverageMeasurementDuration = TimeInterval(maxMeasurementSec)
        }
        let ipVersion: IPVersion? = switch response.ipVersion {
        case 4: .IPv4
        case 6: .IPv6
        default: nil
        }

        return SessionCredentials(
            testID: response.testUUID,
            loopID: nil,
            udpPing: .init(
                pingToken: response.pingToken,
                pingHost: response.pingHost,
                pingPort: response.pingPort,
                ipVersion: ipVersion
            )
        )
    }
}

import ObjectMapper

class CoverageRequestRequest: BasicRequest {
    var time: Int
    var measurementType: String
    var clientUUID: String?
    var loopUUID: String?

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
        loopUUID <- map["loop_uuid"]
    }
}

class SignalRequestResponse: BasicResponse {
    var testUUID: String = ""
    var pingToken: String = ""
    var pingHost: String = ""
    var pingPort: String = ""
    var ipVersion: Int?
    var maxCoverageSessionSeconds: Int?
    var maxCoverageMeasurementSeconds: Int?

    override func mapping(map: Map) {
        super.mapping(map: map)

        testUUID <- map["test_uuid"]
        pingToken <- map["ping_token"]
        pingHost <- map["ping_host"]
        pingPort <- map["ping_port"]
        ipVersion <- map["ip_version"]
        maxCoverageSessionSeconds <- map["max_coverage_session_seconds"]
        maxCoverageMeasurementSeconds <- map["max_coverage_measurement_seconds"]
    }
}
