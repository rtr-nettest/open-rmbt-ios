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

        init(area: LocationArea) {
            timestamp = UInt64(area.time.timeIntervalSince1970)
            location = .init(
                latitude: area.startingLocation.coordinate.latitude,
                longitude: area.startingLocation.coordinate.longitude
            )
            avgPingMilliseconds = area.averagePing
            technology = area.technologies.last
        }

        required init?(map: Map) {
            fatalError("init(map:) has not been implemented")
        }

        func mapping(map: Map) {
            timestamp           <- map["timestamp"]
            location            <- map["location"]
            avgPingMilliseconds <- map["avg_ping_ms"]
            technology          <- map["technology"]
        }
    }

    var fences: [CoverageFence]

    public required init?(map: Map) {
        fatalError("init(map:) has not been implemented")
    }

    override public func mapping(map: Map) {
        super.mapping(map: map)

        fences <- map["fences"]
    }

    init(areas: [LocationArea]) {
        fences = areas.map(CoverageFence.init)
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

extension RMBTControlServer: SendCoverageResultsService {
    func send(areas: [LocationArea]) async throws {
        _ = try await withCheckedThrowingContinuation { continuation in
            submitCoverageResult(.init(areas: areas)) { response in
                continuation.resume(returning: response)
            } error: { error in
                continuation.resume(throwing: error)
            }
        }
    }
}
