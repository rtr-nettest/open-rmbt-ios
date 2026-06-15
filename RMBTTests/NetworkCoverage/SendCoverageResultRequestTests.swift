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
        #expect((location["latitude"] as? NSNumber)?.doubleValue == 48.2082)
        #expect((location["longitude"] as? NSNumber)?.doubleValue == 16.3738)
        #expect((location["accuracy"] as? NSNumber)?.doubleValue == 7)
        #expect((location["altitude"] as? NSNumber)?.doubleValue == 123)
        #expect((location["bearing"] as? NSNumber)?.doubleValue == 42)
        #expect((location["speed"] as? NSNumber)?.doubleValue == 1.5)
    }

    @Test("WHEN coordinates have full GPS precision THEN encodes them losslessly without a floating-point tail")
    func whenCoordinatesHaveFullPrecision_thenEncodesLosslessly() throws {
        let json = try encodedFence(from: makeFence(lat: 48.20820123456789, lon: 16.373812345678))
        let location = try #require(json["location"] as? [String: Any])

        let serialized = try #require(String(
            data: JSONSerialization.data(withJSONObject: location),
            encoding: .utf8
        ))
        #expect(serialized.contains("\"latitude\":48.20820123456789"))
        #expect(serialized.contains("\"longitude\":16.373812345678"))
        #expect(!serialized.contains("99999"))
    }

    @Test("WHEN altitude, speed and bearing have excessive precision THEN rounds each to 1 decimal place")
    func whenMetricsHaveExcessivePrecision_thenRoundsEachToOneDecimal() throws {
        let json = try encodedFence(from: makeFence(
            altitude: 287.65432198, verticalAccuracy: 5, course: 42.98765, speed: 1.523423
        ))
        let location = try #require(json["location"] as? [String: Any])

        #expect((location["altitude"] as? NSNumber)?.decimalValue == Decimal(string: "287.7"))
        #expect((location["bearing"] as? NSNumber)?.decimalValue == Decimal(string: "43"))
        #expect((location["speed"] as? NSNumber)?.decimalValue == Decimal(string: "1.5"))
    }

    @Test("WHEN location course is the device bearing THEN encodes it under the bearing key")
    func whenLocationHasCourse_thenEncodesUnderBearingKey() throws {
        let json = try encodedFence(from: makeFence(course: 137))

        let location = try #require(json["location"] as? [String: Any])
        #expect((location["bearing"] as? NSNumber)?.doubleValue == 137)
        #expect(location["heading"] == nil)
    }

    @Test("WHEN accuracy has excessive precision THEN encodes a clean 1-decimal number without a floating-point tail")
    func whenAccuracyHasExcessivePrecision_thenEncodesCleanOneDecimal() throws {
        let json = try encodedFence(from: makeFence(horizontalAccuracy: 9.1425325252252362))
        let location = try #require(json["location"] as? [String: Any])

        #expect((location["accuracy"] as? NSNumber)?.decimalValue == Decimal(string: "9.1"))

        let serialized = try #require(String(
            data: JSONSerialization.data(withJSONObject: location),
            encoding: .utf8
        ))
        #expect(serialized.contains("\"accuracy\":9.1"))
        #expect(!serialized.contains("9.0999"))
    }

    @Test("WHEN location has no valid accuracy THEN omits accuracy rather than reporting zero")
    func whenLocationHasNoValidAccuracy_thenOmitsAccuracy() throws {
        let json = try encodedFence(from: makeFence(horizontalAccuracy: 0))

        let location = try #require(json["location"] as? [String: Any])
        #expect(location["accuracy"] == nil)
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
