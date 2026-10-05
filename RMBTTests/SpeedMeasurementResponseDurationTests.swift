import Testing
import ObjectMapper
@testable import RMBT

@Suite("SpeedMeasurementResponse test_duration")
struct SpeedMeasurementResponseDurationTests {

    private func testParams(duration: Any?) -> RMBTTestParams? {
        var json: [String: Any] = [
            "test_server_address": "server.example",
            "test_server_port": 443,
            "test_numthreads": "3",
            "test_wait": 0
        ]
        if let duration { json["test_duration"] = duration }
        guard let response = Mapper<SpeedMeasurementResponse_Old>().map(JSON: json) else { return nil }
        return RMBTTestParams(with: response.toJSON())
    }

    @Test("when_durationIsNumber_then_testDurationMatches")
    func when_number_then_matches() {
        #expect(testParams(duration: 10)?.testDuration == 10)
        #expect(testParams(duration: 10.5)?.testDuration == 10.5)
    }

    @Test("when_durationIsNumericString_then_testDurationMatches")
    func when_numericString_then_matches() {
        #expect(testParams(duration: "10")?.testDuration == 10)
        #expect(testParams(duration: "7.5")?.testDuration == 7.5)
    }

    @Test("when_durationIsMissing_then_defaultsToSevenSeconds")
    func when_missing_then_default() {
        #expect(testParams(duration: nil)?.testDuration == 7)
    }

    @Test("when_durationIsNotNumeric_then_defaultsToSevenSeconds")
    func when_nonNumeric_then_default() {
        #expect(testParams(duration: "abc")?.testDuration == 7)
    }
}
