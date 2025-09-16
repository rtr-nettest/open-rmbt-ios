//
//  SendCoverageResultRequestTests.swift
//  RMBTTests
//

import Testing
import CoreLocation
@testable import RMBT

@Suite("SendCoverageResultRequest encoding")
struct SendCoverageResultRequestTests {
    @Test("WHEN building request THEN encodes radius_m and location extras")
    func whenBuildingRequest_thenEncodesRadiusAndLocation() throws {
        let startDate = Date(timeIntervalSinceReferenceDate: 0)
        let loc = CLLocation(
            coordinate: .init(latitude: 48.2082, longitude: 16.3738),
            altitude: 123,
            horizontalAccuracy: 7,
            verticalAccuracy: 5,
            course: 42,
            speed: 1.5,
            timestamp: startDate
        )
        var fence = Fence(
            startingLocation: loc,
            dateEntered: startDate,
            technology: "LTE",
            pings: [PingResult(result: .interval(.milliseconds(50)), timestamp: startDate)],
            radiusMeters: 25
        )
        fence.exit(at: startDate.addingTimeInterval(2))

        let request = SendCoverageResultRequest(fences: [fence], testUUID: "TEST-UUID", coverageStartDate: startDate)
        let json = request.toJSON()

        let fences = try #require(json["fences"] as? [[String: Any]])
        let f0 = try #require(fences.first)
        // Radius meters
        #expect(f0["radius_m"] as? Int == 25)
        // Offset/duration
        #expect(f0["offset_ms"] as? Int == 0)
        #expect(f0["duration_ms"] as? Int == 2000)
        // Location structure
        let location = try #require(f0["location"] as? [String: Any])
        #expect(location["latitude"] as? Double == 48.2082)
        #expect(location["longitude"] as? Double == 16.3738)
        #expect(location["accuracy"] as? Double == 7)
        #expect(location["altitude"] as? Double == 123)
        #expect(location["heading"] as? Double == 42)
        #expect(location["speed"] as? Double == 1.5)
    }
}

