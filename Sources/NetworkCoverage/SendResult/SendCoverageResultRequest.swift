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
            private(set) var latitude: Decimal
            private(set) var longitude: Decimal
            private(set) var accuracy: Decimal?
            private(set) var altitude: Decimal?
            private(set) var bearing: Decimal?
            private(set) var speed: Decimal?

            init(latitude: Decimal, longitude: Decimal, accuracy: Decimal?, altitude: Decimal?, bearing: Decimal?, speed: Decimal?) {
                self.latitude = latitude
                self.longitude = longitude
                self.accuracy = accuracy
                self.altitude = altitude
                self.bearing = bearing
                self.speed = speed
            }

            required init?(map: Map) {
                fatalError("init(map:) has not been implemented")
            }

            func mapping(map: Map) {
                latitude        <- map["latitude"]
                longitude       <- map["longitude"]
                accuracy        <- map["accuracy"]
                altitude        <- map["altitude"]
                bearing         <- map["bearing"]
                speed           <- map["speed"]
            }
        }

        private(set) var timestamp: UInt64
        private(set) var location: Location
        private(set) var avgPingMilliseconds: Int?
        private(set) var offsetMiliseconds: Int
        private(set) var durationMiliseconds: Int?
        static let noNetworkTechnology = "NONE"
        static let noNetworkTechnologyID = 1000

        private(set) var technology: String?
        private(set) var technology_id: Int?
        private(set) var radius: Int

        init(fence: Fence, coverageStartDate: Date) {
            timestamp = UInt64(fence.dateEntered.timeIntervalSince1970 * 1_000_000) // microseconds
            let loc = fence.startingLocation
            location = .init(
                latitude: loc.coordinate.latitude.exactDecimal,
                longitude: loc.coordinate.longitude.exactDecimal,
                accuracy: loc.horizontalAccuracy > 0 ? Decimal(loc.horizontalAccuracy).roundedToDecimalPlaces(1) : nil,
                altitude: loc.verticalAccuracy >= 0 ? Decimal(loc.altitude).roundedToDecimalPlaces(1) : nil,
                bearing: loc.course >= 0 ? Decimal(loc.course).roundedToDecimalPlaces(1) : nil,
                speed: loc.speed >= 0 ? Decimal(loc.speed).roundedToDecimalPlaces(1) : nil
            )
            avgPingMilliseconds = fence.averagePing

            offsetMiliseconds = Int(fence.dateEntered.timeIntervalSince(coverageStartDate) * 1000)

            if let dateExited = fence.dateExited {
                durationMiliseconds = Int(dateExited.timeIntervalSince(fence.dateEntered) * 1000)
            } else {
                durationMiliseconds = nil
            }

            if let lastTechnology = fence.technologies.last {
                technology = lastTechnology.radioTechnologyCode
                technology_id = lastTechnology.radioTechnologyTypeID
            } else {
                technology = Self.noNetworkTechnology
                technology_id = Self.noNetworkTechnologyID
            }
            radius = Int(fence.radiusMeters)
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
            radius            <- map["radius"]
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

private extension Decimal {
    func roundedToDecimalPlaces(_ places: Int) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, places, .plain)
        return result
    }
}

private extension Double {
    // Routes through the shortest round-trippable string so the encoded JSON keeps full
    // precision without the floating-point tail (e.g. 48.2082, not 48.208199999999998).
    // `Decimal(self)` would instead introduce its own long, lossy tail for such values.
    var exactDecimal: Decimal { Decimal(string: String(self)) ?? Decimal(self) }
}
