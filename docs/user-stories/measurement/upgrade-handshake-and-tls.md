## Measurement connection: HTTP upgrade handshake and TLS

```gherkin
Feature: Connecting to the measurement server (HTTP upgrade + TLS 1.2/1.3)

  As a user,
  I want speed tests to work against modern measurement servers,
  so that servers behind reverse proxies (extra headers) or requiring TLS 1.3
  don't make my test fail.

  HTTP-style test servers answer the client's "Upgrade: RMBT" request with an
  HTTP 101 Switching Protocols response, then switch to the RMBT protocol.

  # --- Upgrade handshake (RFC-conformant) ---------------------------------

  Scenario: Accept a 101 whose Upgrade header is last
    Given the server replies "HTTP/1.1 101 ... Connection: Upgrade, Upgrade: RMBT"
    Then the handshake succeeds and the test proceeds

  Scenario: Accept extra/standard headers in any order (e.g. HSTS)
    Given the 101 response has Strict-Transport-Security (or other headers) after "Upgrade: RMBT"
    Then the handshake still succeeds
    # Regression: previously the client read only up to the fixed bytes
    # "Upgrade: RMBT\r\n\r\n", so a header after Upgrade made the read hang until
    # timeout and the test collapsed into an "Invalid state".

  Scenario: Header names are matched case-insensitively
    Given the 101 response uses mixed-case header names
    Then the handshake still succeeds

  Scenario: A non-101 or malformed response fails the handshake cleanly
    Given the server replies with a non-101 status (or an unparseable status line)
    Then the handshake fails (no hang) and the worker reports failure

  # --- TLS ----------------------------------------------------------------

  Scenario Outline: Encrypted servers negotiate TLS 1.2 and 1.3
    Given an encrypted test server that requires <tls>
    When the measurement connects
    Then the TLS handshake succeeds
    # Previously the socket used SecureTransport (TLS 1.2 max), so a TLS 1.3-only
    # server failed with errSSLPeerProtocolVersion (-9836).

    Examples:
      | tls      |
      | TLS 1.2  |
      | TLS 1.3  |
```

## Notes

- The upgrade response is parsed by `RMBTUpgradeResponseParser.validateSwitchingProtocols`:
  reads to the RFC 7230 end-of-headers marker, status line must be 101, header fields are
  case-insensitive and any order. The worker is tolerant — it proceeds on any 101 and only
  aborts on a non-101 / unparseable status.
- TLS is provided by `RMBTTestConnection` (Network.framework `NWConnection`), which
  negotiates TLS 1.2 and 1.3, replacing `GCDAsyncSocket`/SecureTransport. The same instance
  is reused for the download and upload phases (state is reset on each connect).
- Connection setup is logged (host/port/encryption, negotiated cipher, disconnect error) so
  failures are diagnosable instead of surfacing only as a downstream "Invalid state".

## References
- Sources/RMBTUpgradeResponseParser.swift
- Sources/RMBTTestConnection.swift (NWConnection, TLS 1.2/1.3, reuse reset)
- Sources/RMBTTestWorker.swift (handshake flow, connection delegate, logging)
- RMBTTests/RMBTUpgradeResponseParserTests.swift
```
