import Testing
@testable import RMBT

// Validation for the developer "Custom Map Server" hostname field: looks-like-a-hostname check
// (non-empty, contains a dot, no whitespace or commas). Invalid input is discarded and the override disabled.
@Suite("Map server hostname validation")
struct MapServerHostnameValidationTests {

    @Test("WHEN the hostname looks valid THEN it is accepted")
    func validHostnames() {
        #expect(RMBTSettingsViewController.isValidServerHostname("map.example.org"))
        #expect(RMBTSettingsViewController.isValidServerHostname("m-cloud.netztest.at"))
        #expect(RMBTSettingsViewController.isValidServerHostname("a.b"))
    }

    @Test("WHEN the hostname is empty THEN it is rejected")
    func emptyRejected() {
        #expect(!RMBTSettingsViewController.isValidServerHostname(""))
    }

    @Test("WHEN the hostname has no dot THEN it is rejected")
    func noDotRejected() {
        #expect(!RMBTSettingsViewController.isValidServerHostname("localhost"))
    }

    @Test("WHEN the hostname contains whitespace THEN it is rejected")
    func whitespaceRejected() {
        #expect(!RMBTSettingsViewController.isValidServerHostname("map example.org"))
        #expect(!RMBTSettingsViewController.isValidServerHostname("map\t.org"))
    }

    @Test("WHEN the hostname contains a comma THEN it is rejected")
    func commaRejected() {
        #expect(!RMBTSettingsViewController.isValidServerHostname("a.b,c.d"))
    }
}
