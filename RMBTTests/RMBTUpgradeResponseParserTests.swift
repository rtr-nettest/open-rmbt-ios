import Testing
@testable import RMBT

// Parsing of the measurement server's HTTP/1.1 `Upgrade: RMBT` handshake response (RFC 7230 §6.7).
// Regression cover for the bug where a `Strict-Transport-Security` (HSTS) header emitted after `Upgrade`
// made the handshake hang and the test collapse into an "Invalid state".
@Suite("Upgrade response parser")
struct RMBTUpgradeResponseParserTests {

    private func validate(_ block: String) throws {
        try RMBTUpgradeResponseParser.validateSwitchingProtocols(block)
    }

    @Test("WHEN the 101 response ends with the Upgrade header THEN it validates")
    func whenUpgradeIsLastHeader_thenValid() throws {
        try validate("HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: RMBT\r\n\r\n")
    }

    @Test("WHEN an HSTS header follows the Upgrade header THEN it still validates")
    func whenHSTSFollowsUpgrade_thenValid() throws {
        // The exact shape that used to hang: a conforming header injected by a proxy AFTER `Upgrade: RMBT`.
        try validate("HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: RMBT\r\nStrict-Transport-Security: max-age=31536000\r\n\r\n")
    }

    @Test("WHEN standard headers precede the Upgrade header THEN it validates")
    func whenHeadersPrecedeUpgrade_thenValid() throws {
        try validate("HTTP/1.1 101 Switching Protocols\r\nDate: Tue, 29 Sep 2026 12:47:18 GMT\r\nServer: nginx\r\nStrict-Transport-Security: max-age=31536000\r\nUpgrade: RMBT\r\nConnection: Upgrade\r\n\r\n")
    }

    @Test("WHEN header names use mixed case THEN they are matched case-insensitively")
    func whenMixedCaseHeaderNames_thenValid() throws {
        try validate("HTTP/1.1 101 Switching Protocols\r\ncOnNeCtIoN: Upgrade\r\nUPGRADE: rmbt\r\n\r\n")
    }

    @Test("WHEN Connection lists several tokens THEN upgrade is still detected")
    func whenConnectionHasMultipleTokens_thenValid() throws {
        try validate("HTTP/1.1 101 Switching Protocols\r\nConnection: keep-alive, Upgrade\r\nUpgrade: RMBT\r\n\r\n")
    }

    @Test("WHEN the terminating blank line is absent THEN it still validates")
    func whenNoTrailingBlankLine_thenValid() throws {
        try validate("HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: RMBT")
    }

    @Test("WHEN the status is not 101 THEN it reports the unexpected status")
    func whenNot101_thenUnexpectedStatus() {
        #expect(throws: RMBTUpgradeResponseParser.ParseError.unexpectedStatus(400)) {
            try validate("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
        }
    }

    @Test("WHEN a 101 response omits the Upgrade header THEN it is not treated as upgraded")
    func whenNoUpgradeHeader_thenNotUpgraded() {
        #expect(throws: RMBTUpgradeResponseParser.ParseError.notUpgraded) {
            try validate("HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\n\r\n")
        }
    }

    @Test("WHEN the status line is malformed THEN it reports a malformed status line")
    func whenMalformedStatusLine_thenMalformed() {
        #expect(throws: RMBTUpgradeResponseParser.ParseError.malformedStatusLine) {
            try validate("GARBAGE\r\nUpgrade: RMBT\r\n\r\n")
        }
    }
}
