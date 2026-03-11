//
//  AsyncSocketUDPConnectionTests.swift
//  RMBTTests
//
//  Integration tests for AsyncSocketUDPConnection verifying error recovery
//  behavior for transient send failures and intentional cancellation.
//

import Testing
import Foundation
@testable import RMBT

@Suite("AsyncSocketUDPConnection")
struct AsyncSocketUDPConnectionTests {

    @Suite("transient send failure recovery")
    struct TransientSendFailureRecovery {

        /// Proves the sticky-transportError bug fix: after `didNotSendData` fires
        /// (DNS failure on `.invalid` TLD per RFC 2606), subsequent `send()` calls
        /// must still succeed because the socket itself is still alive.
        @Test("WHEN send fails due to DNS error THEN subsequent sends still succeed")
        func whenSendFailsDueToDNSError_thenSubsequentSendsStillSucceed() async throws {
            let sut = makeSUT()

            // Start binds to an ephemeral local port — always succeeds.
            // Host is stored for per-send DNS resolution (unconnected socket).
            try await sut.start(host: "test.invalid", port: "12345", ipVersion: nil)

            // First send — fire-and-forget at socket level, triggers async DNS lookup.
            try sut.send(data: Data([0x01]))

            // receive() blocks until the delegate callback (didNotSendData) fires
            // with the DNS resolution error and resumes the pending receive.
            await #expect(throws: (any Error).self) {
                _ = try await sut.receive()
            }

            // Key assertion: a second send must NOT throw.
            // With the bug, transportError is sticky and this throws.
            #expect(throws: Never.self) {
                try sut.send(data: Data([0x02]))
            }

            sut.cancel()
        }
    }

    @Suite("intentional cancellation")
    struct IntentionalCancellation {

        /// Verifies that explicit cancel() is a permanent shutdown — sends must
        /// fail and no auto-reconnect should be attempted.
        @Test("WHEN cancelled THEN sends fail permanently")
        func whenCancelled_thenSendsFailPermanently() async throws {
            let sut = makeSUT()

            try await sut.start(host: "127.0.0.1", port: "12345", ipVersion: .IPv4)

            sut.cancel()

            // Give the async cancel a moment to execute on delegateQueue.
            try await Task.sleep(for: .milliseconds(50))

            // Send should fail because cancel is an intentional shutdown.
            #expect(throws: (any Error).self) {
                try sut.send(data: Data([0x01]))
            }
        }
    }
}

// MARK: - makeSUT & Factories

private func makeSUT() -> AsyncSocketUDPConnection {
    AsyncSocketUDPConnection()
}
