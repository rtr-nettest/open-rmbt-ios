//
//  SendCoverageResultRequest.swift
//  RMBT
//
//  Created by Jiri Urbasek on 12/16/24.
//  Copyright 2024 appscape gmbh. All rights reserved.
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
        private(set) var offsetMiliseconds: Int
        private(set) var durationMiliseconds: Int?
        private(set) var technology: String?
        private(set) var technology_id: Int?

        init(fence: Fence, coverageStartDate: Date) {
            timestamp = UInt64(fence.dateEntered.timeIntervalSince1970 * 1_000_000) // microseconds
            location = .init(
                latitude: fence.startingLocation.coordinate.latitude,
                longitude: fence.startingLocation.coordinate.longitude
            )
            avgPingMilliseconds = fence.averagePing

            offsetMiliseconds = Int(fence.dateEntered.timeIntervalSince(coverageStartDate) * 1000)

            if let dateExited = fence.dateExited {
                durationMiliseconds = Int(dateExited.timeIntervalSince(fence.dateEntered) * 1000)
            } else {
                durationMiliseconds = nil
            }

            technology = fence.technologies.last?.radioTechnologyCode
            technology_id = fence.technologies.last?.radioTechnologyTypeID
        }

        required init?(map: Map) {
            fatalError("init(map:) has not been implemented")
        }

        func mapping(map: Map) {
            timestamp           <- map["timestamp_microseconds"]
            location            <- map["location"]
            avgPingMilliseconds <- map["avg_ping_ms"]
            offsetMiliseconds   <- map["offset_ms"]
            durationMiliseconds <- map["duration_ms"]
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

    init(fences: [Fence], testUUID: String, coverageStartDate: Date) {
        self.fences = fences.map { CoverageFence(fence: $0, coverageStartDate: coverageStartDate) }
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
        case missingStartDate
    }

    let controlServer: RMBTControlServer
    let testUUID: () -> String?
    let startDate: () -> Date?

    init(
        controlServer: RMBTControlServer,
        testUUID: @escaping @Sendable @autoclosure () -> String?,
        startDate: @escaping @Sendable @autoclosure () -> Date?
    ) {
        self.controlServer = controlServer
        self.testUUID = testUUID
        self.startDate = startDate
    }

    func send(fences: [Fence]) async throws {
        guard let testUUID = self.testUUID() else {
            throw Failure.missingTestUUID
        }

        guard let coverageStartDate = self.startDate() else {
            throw Failure.missingStartDate
        }

        _ = try await withCheckedThrowingContinuation { continuation in
            controlServer.submitCoverageResult(
                .init(fences: fences, testUUID: testUUID, coverageStartDate: coverageStartDate),
                acceptableStatusCodes: NetworkCoverageFactory.acceptableSubmitResultsRequestStatusCodes
            ) { response in
                continuation.resume(returning: response)
            } error: { error in
                continuation.resume(throwing: error)
            }
        }
    }
}
