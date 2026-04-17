//
//  SendCoverageResultRequestTests.swift
//  RMBTTests
//

import Testing
import CoreLocation
import CoreTelephony
@testable import RMBT

@Suite("SendCoverageResultRequest encoding")
struct SendCoverageResultRequestTests {

    // MARK: - Technology encoding

    @Test("WHEN fence has known technology THEN encodes technology and technology_id from lookup")
    func whenFenceHasKnownTechnology_thenEncodesTechnologyAndId() throws {
        let json = try encodedFence(from: makeFence(technology: CTRadioAccessTechnologyLTE))

        #expect(json["technology"] as? String == "4G/LTE")
        #expect(json["technology_id"] as? Int == 13)
    }

    @Test("WHEN fence has no technology THEN encodes NONE with id 1000")
    func whenFenceHasNoTechnology_thenEncodesNoneWith1000() throws {
        let json = try encodedFence(from: makeFence(technology: nil))

        #expect(json["technology"] as? String == SendCoverageResultRequest.CoverageFence.noNetworkTechnology)
        #expect(json["technology_id"] as? Int == SendCoverageResultRequest.CoverageFence.noNetworkTechnologyID)
    }

    @Test("WHEN fence has unrecognized technology THEN technology and technology_id are nil")
    func whenFenceHasUnrecognizedTechnology_thenFieldsAreNil() throws {
        let json = try encodedFence(from: makeFence(technology: "LTE"))

        #expect(json["technology"] == nil)
        #expect(json["technology_id"] == nil)
    }

    // MARK: - Location and timing encoding

    @Test("WHEN building request THEN encodes radius and location extras")
    func whenBuildingRequest_thenEncodesRadiusAndLocationExtras() throws {
        let startDate = Date(timeIntervalSinceReferenceDate: 0)
        let fence = makeFence(
            lat: 48.2082, lon: 16.3738,
            altitude: 123, horizontalAccuracy: 7, verticalAccuracy: 5,
            course: 42, speed: 1.5,
            dateEntered: startDate,
            technology: CTRadioAccessTechnologyLTE,
            pings: [PingResult(result: .interval(.milliseconds(50)), timestamp: startDate)],
            radiusMeters: 25,
            exitedAt: startDate.addingTimeInterval(2)
        )

        let json = try encodedFence(from: fence, coverageStartDate: startDate)

        #expect(json["radius"] as? Int == 25)
        #expect(json["offset_ms"] as? Int == 0)
        #expect(json["duration_ms"] as? Int == 2000)

        let location = try #require(json["location"] as? [String: Any])
        #expect(location["latitude"] as? Double == 48.2082)
        #expect(location["longitude"] as? Double == 16.3738)
        #expect(location["accuracy"] as? Double == 7)
        #expect(location["altitude"] as? Double == 123)
        #expect(location["heading"] as? Double == 42)
        #expect(location["speed"] as? Double == 1.5)
    }
}

// MARK: - Helpers

private func encodedFence(
    from fence: Fence,
    coverageStartDate: Date = Date(timeIntervalSinceReferenceDate: 0),
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> [String: Any] {
    let request = SendCoverageResultRequest(
        fences: [fence],
        testUUID: UUID().uuidString,
        coverageStartDate: coverageStartDate
    )
    let fences = try #require(
        request.toJSON()["fences"] as? [[String: Any]],
        sourceLocation: sourceLocation
    )
    return try #require(fences.first, sourceLocation: sourceLocation)
}
