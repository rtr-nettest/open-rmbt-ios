//
//  SendCoverageResultRequest.swift
//  RMBT
//
//  Created by Jiri Urbasek on 12/16/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import Foundation
import ObjectMapper

public class SendCoverageResultRequest: BasicRequest {
    final class CoverageFence: Mappable {
        final class Location: Mappable {
            private(set) var latitude: Double
            private(set) var longitude: Double

            init(latitude: Double, longitude: Double) {
                self.latitude = latitude
                self.longitude = longitude
            }

            required init?(map: Map) {
                fatalError("init(map:) has not been implemented")
            }

            func mapping(map: Map) {
                latitude        <- map["latitude"]
                longitude       <- map["longitude"]
            }
        }

        private(set) var timestamp: UInt64
        private(set) var location: Location
        private(set) var avgPingMilliseconds: Int?
        private(set) var technology: String?
        private(set) var technology_id: Int?

        init(area: LocationArea) {
            timestamp = UInt64(area.dateEntered.timeIntervalSince1970 * 1_000_000) // microseconds
            location = .init(
                latitude: area.startingLocation.coordinate.latitude,
                longitude: area.startingLocation.coordinate.longitude
            )
            avgPingMilliseconds = area.averagePing
            technology = area.technologies.last?.radioTechnologyCode
            technology_id = area.technologies.last?.radioTechnologyTypeID
        }

        required init?(map: Map) {
            fatalError("init(map:) has not been implemented")
        }

        func mapping(map: Map) {
            timestamp           <- map["timestamp_microseconds"]
            location            <- map["location"]
            avgPingMilliseconds <- map["avg_ping_ms"]
            technology          <- map["technology"]
            technology_id       <- map["technology_id"]
        }
    }

    var fences: [CoverageFence]
    var testUUID: String
    var clientUUID: String?

    public required init?(map: Map) {
        fatalError("init(map:) has not been implemented")
    }

    override public func mapping(map: Map) {
        super.mapping(map: map)

        fences <- map["fences"]
        testUUID <- map["test_uuid"]
        clientUUID <- map["client_uuid"]
    }

    init(areas: [LocationArea], testUUID: String) {
        fences = areas.map(CoverageFence.init)
        self.testUUID = testUUID
        super.init()
    }
}

class CoverageMeasurementSubmitResponse: BasicResponse {
//    var openTestUuid: String?
//    var testUuid: String?

    override func mapping(map: Map) {
        super.mapping(map: map)
//
//        openTestUuid <- map["open_test_uuid"]
//        testUuid <- map["test_uuid"]
    }
}

struct ControlServerCoverageResultsService: SendCoverageResultsService {
    enum Failure: Error {
        case missingTestUUID
    }

    let controlServer: RMBTControlServer
    let testUUID: () -> String?

    init(controlServer: RMBTControlServer, testUUID: @escaping @autoclosure () -> String?) {
        self.controlServer = controlServer
        self.testUUID = testUUID
    }

    func send(areas: [LocationArea]) async throws {
        guard let testUUID = self.testUUID() else {
            throw Failure.missingTestUUID
        }

        _ = try await withCheckedThrowingContinuation { continuation in
            controlServer.submitCoverageResult(.init(areas: areas, testUUID: testUUID)) { response in
                continuation.resume(returning: response)
            } error: { error in
                continuation.resume(throwing: error)
            }
        }
    }
}
