import Testing
import ObjectMapper
@testable import RMBT

// User story: docs/user-stories/network-coverage/settings-driven-availability.md
@Suite("SettingsResponse signal_measurement_available")
struct SettingsResponseSignalMeasurementTests {

    private func parse(_ settingsJSON: [String: Any]) -> SettingsResponse.Settings? {
        Mapper<SettingsResponse.Settings>().map(JSON: settingsJSON)
    }

    @Test("when_flagIsTrue_then_availabilityIsTrue")
    func when_flagTrue_then_true() {
        #expect(parse(["signal_measurement_available": true])?.signalMeasurementAvailable == true)
    }

    @Test("when_flagIsFalse_then_availabilityIsFalse")
    func when_flagFalse_then_false() {
        #expect(parse(["signal_measurement_available": false])?.signalMeasurementAvailable == false)
    }

    @Test("when_keyIsAbsent_then_availabilityIsNil")
    func when_keyAbsent_then_nil() {
        #expect(parse([:])?.signalMeasurementAvailable == nil)
    }

    @Test("when_valueIsNull_then_availabilityIsNil")
    func when_valueNull_then_nil() {
        #expect(parse(["signal_measurement_available": NSNull()])?.signalMeasurementAvailable == nil)
    }

    // The backend contract is a JSON boolean, but accept string encodings defensively so a
    // stringified "true"/"false" still drives the flag rather than silently leaving it unset.
    @Test(
        "when_flagIsBooleanString_then_availabilityMatches",
        arguments: [("true", true), ("false", false), ("1", true), ("0", false)]
    )
    func when_booleanString_then_matches(value: String, expected: Bool) {
        #expect(parse(["signal_measurement_available": value])?.signalMeasurementAvailable == expected)
    }

    @Test("when_valueIsUnrecognizedString_then_availabilityIsNil")
    func when_unrecognizedString_then_nil() {
        #expect(parse(["signal_measurement_available": "maybe"])?.signalMeasurementAvailable == nil)
    }

    // End-to-end: the real server nests the flag inside settings[0], exactly the path the
    // control-server handler reads (`response.settings?.first?.signalMeasurementAvailable`).
    @Test("when_fullResponseNestsFlag_then_parsedFromFirstSettings")
    func when_fullResponse_then_parsedFromFirstSettings() {
        let json: [String: Any] = [
            "settings": [
                [
                    "uuid": "59c64ee3-5163-4228-82f6-f556577bc61c",
                    "signal_measurement_available": false,
                    "urls": ["url_share": "https://netztest.at/share/"],
                ]
            ]
        ]
        let response = Mapper<SettingsResponse>().map(JSON: json)
        #expect(response?.settings?.first?.signalMeasurementAvailable == false)
    }
}
