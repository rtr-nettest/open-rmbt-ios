//
//  RMBTUpgradeResponseParser.swift
//  RMBT
//
//  Copyright © 2026 appscape gmbh. All rights reserved.
//

import Foundation

/// Parses and validates the measurement server's HTTP/1.1 `Upgrade` handshake response.
///
/// For HTTP-style test servers the client sends an `Upgrade: RMBT` request and the server answers with an
/// HTTP `101 Switching Protocols` response before switching to the raw RMBT protocol. Per RFC 7230:
///
///   * the header block is terminated by an empty line (CRLFCRLF);
///   * header field names are case-insensitive and may appear in any order;
///   * intermediaries (e.g. reverse proxies) may inject additional standard header fields such as
///     `Strict-Transport-Security` (HSTS), `Date`, `Server`, etc.
///
/// The previous implementation read the socket only up to the fixed byte sequence `Upgrade: RMBT\r\n\r\n`, which
/// silently assumed `Upgrade` was the *last* header. Any conforming header emitted after it (HSTS being the observed
/// case on some servers) meant that delimiter never appeared, so the read hung until the socket timed out and the
/// test collapsed into an "Invalid state". This parser instead treats the response as a proper HTTP message.
enum RMBTUpgradeResponseParser {

    enum ParseError: Error, Equatable {
        /// The status line was missing or not a recognisable `HTTP/x.y <code> ...` line.
        case malformedStatusLine
        /// The response completed but the status code was not `101 Switching Protocols`.
        case unexpectedStatus(Int)
        /// The `101` response did not advertise the RMBT protocol upgrade (`Connection`/`Upgrade` fields).
        case notUpgraded
    }

    /// The header block read from the socket, up to and including the terminating blank line.
    /// Exposed so both the worker and the socket read use the exact same, RFC-defined delimiter.
    static let headerTerminator = "\r\n\r\n"

    /// Validates a complete HTTP header block describing a successful upgrade to the RMBT protocol.
    ///
    /// - Parameter headerBlock: the raw response bytes decoded as text (status line + header fields; the trailing
    ///   blank line is optional and ignored).
    /// - Throws: `ParseError` when the response is not a `101 Switching Protocols` upgrading to `RMBT`.
    static func validateSwitchingProtocols(_ headerBlock: String) throws {
        // Normalise CRLF (and tolerate bare LF) then split into lines.
        let lines = headerBlock
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        guard let statusLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw ParseError.malformedStatusLine
        }

        // Status line: "HTTP/<version> <status-code> <reason-phrase>"
        let statusFields = statusLine
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard statusFields.count >= 2,
              statusFields[0].uppercased().hasPrefix("HTTP/"),
              let statusCode = Int(statusFields[1]) else {
            throw ParseError.malformedStatusLine
        }
        guard statusCode == 101 else {
            throw ParseError.unexpectedStatus(statusCode)
        }

        // Collect header fields. Names are case-insensitive (RFC 7230 §3.2); a field value may itself contain
        // colons (e.g. Strict-Transport-Security has none, but Date does), so only split on the first colon.
        var fields: [String: String] = [:]
        for line in lines.dropFirst() where line.contains(":") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            fields[name] = value
        }

        // RFC 7230 §6.7: a successful upgrade echoes `Connection: upgrade` and `Upgrade: <protocol>`.
        // Both fields are comma-separated token lists and case-insensitive.
        let connectionTokens = (fields["connection"] ?? "").lowercased()
        let upgradeTokens = (fields["upgrade"] ?? "").lowercased()
        guard connectionTokens.contains("upgrade"), upgradeTokens.contains("rmbt") else {
            throw ParseError.notUpgraded
        }
    }
}
