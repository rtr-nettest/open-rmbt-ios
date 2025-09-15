//
//  UDPPingSessionTests.swift
//  RMBTTests
//
//  Verifies RR01/RE01 handling as per RTR spec.
//

import Testing
import Foundation
@testable import RMBT

@Suite("UDPPingSession Tests")
struct UDPPingSessionTests {
    @Suite("Connection Start Tests")
    struct ConnectionStartTests {
        @Test("WHEN initiating session THEN starts UDP connection with expected host/port/ip version")
        func whenInitiatingSession_thenStartsConnectionWithExpectedHostPortAndIpVersion() async throws {
            let host = "example.org"
            let port = "444"
            let ipVersion: IPVersion? = .IPv4
            let token = "Z7kKKZqSYU/j7nSGbjoRLw=="

            let (sut, udp, returnedToken) = makeSUT(sessionInitiation: .init(
                serverAddress: host,
                serverPort: port,
                token: token,
                ipVersion: ipVersion
            ))

            let obtained = try await sut.initiatePingSession()
            #expect(obtained == returnedToken)

            #expect(udp.capturedStartParameters == [
                .init(host: host, port: port, ipVersion: ipVersion)
            ])
        }

        @Test("WHEN ipVersion is nil THEN starts UDP connection with nil ip version")
        func whenIpVersionIsNil_thenStartsConnectionWithNilIpVersion() async throws {
            let initiation = UDPPingSession.SessionInitiation(
                serverAddress: "ping.rtr.example",
                serverPort: "1919",
                token: "dummy-token",
                ipVersion: nil
            )
            let (sut, udp, token) = makeSUT(sessionInitiation: initiation)

            let returned = try await sut.initiatePingSession()
            #expect(returned == token)

            #expect(udp.capturedStartParameters == [
                .init(host: "ping.rtr.example", port: "1919", ipVersion: nil)
            ])
        }

        @Test("WHEN sending pings after initiation THEN start() is called exactly once")
        func whenSendingPingsAfterInitiation_thenStartCalledExactlyOnce() async throws {
            let (sut, udp, _) = makeSUT()

            _ = try await sut.initiatePingSession()
            #expect(udp.capturedStartParameters.count == 1)

            udp.onSend = { data in
                udp.nextResponse = makeResponse(protocol: "RR01", sequence: decodeSequence(from: data))
            }

            try await sut.sendPing(in: "Z7kKKZqSYU/j7nSGbjoRLw==")
            try await sut.sendPing(in: "Z7kKKZqSYU/j7nSGbjoRLw==")

            #expect(udp.capturedStartParameters.count == 1)
        }
    }
    @Suite("Protocol Encoding Tests")
    struct ProtocolEncodingTests {
        @Test("WHEN sending ping THEN payload contains RP01, sequence and token bytes")
        func whenSendingPing_thenPayloadContainsRP01SequenceAndTokenBytes() async throws {
            let (sut, udp, token) = makeSUT()

            var capturedRequest: Data?
            udp.onSend = { data in
                capturedRequest = data
                // Auto-reply with RR01 to allow sendPing to finish
                let seq = decodeSequence(from: data)
                udp.nextResponse = makeResponse(protocol: "RR01", sequence: seq)
            }

            let auth = try await sut.initiatePingSession()
            try await sut.sendPing(in: auth)

            let data = try #require(capturedRequest)

            #expect(String(decoding: data[0...3], as: UTF8.self) == "RP01")
            // Verify token bytes are present and correctly base64-decoded
            #expect(data.dropFirst(8) == Data(base64Encoded: token))
        }
    }

    @Suite("Response Handling Tests")
    struct ResponseHandlingTests {
        @Test("WHEN RE01 with seq=0 THEN throws needsReinitialization")
        func whenRE01WithSeq0_thenThrowsNeedsReinitialization() async throws {
            let (sut, udp, token) = makeSUT()

            let auth = try await sut.initiatePingSession()
            #expect(auth == token)
            udp.nextResponse = makeResponse(protocol: "RE01", sequence: 0)

            await #expect(throws: PingSendingError.needsReinitialization) {
                try await sut.sendPing(in: auth)
            }
        }

        @Test("WHEN RR01 matches sequence THEN succeeds")
        func whenRR01WithMatchingSeq_thenSucceeds() async throws {
            let (sut, udp, token) = makeSUT()
            let auth = try await sut.initiatePingSession()
            #expect(auth == token)

            udp.onSend = { data in
                udp.nextResponse = makeResponse(protocol: "RR01", sequence: decodeSequence(from: data))
            }

            try await sut.sendPing(in: auth)
        }

        @Test("WHEN RE01 matches sequence THEN throws needsReinitialization")
        func whenRE01WithMatchingSeq_thenThrowsNeedsReinitialization() async throws {
            let (sut, udp, token) = makeSUT()
            let auth = try await sut.initiatePingSession()
            #expect(auth == token)

            udp.onSend = { data in
                udp.nextResponse = makeResponse(protocol: "RE01", sequence: decodeSequence(from: data))
            }

            await #expect(throws: PingSendingError.needsReinitialization) {
                try await sut.sendPing(in: auth)
            }
        }
    }

    @Suite("Timeout Tests")
    struct TimeoutTests {
        @Test("WHEN pending ping exceeds timeout THEN it is cleaned up with timedOut error")
        func whenPendingPingTimesOut_thenIsCleanedUp() async throws {
            var nowNanos: UInt64 = 0
            let (session, udp, _) = makeSUT(timeoutIntervalMs: 100, now: { nowNanos })
            let token = try await session.initiatePingSession()

            await #expect(throws: PingSendingError.timedOut) {
                try await confirmation("Ping continuation registered and cleaned up", expectedCount: 1) { confirmation in
                    // Trigger timeout cleanup only after continuation is stored
                    // by hooking into receive() which is started after registration.
                    udp.onReceive = {
                        Task {
                            nowNanos = 200_000_000 // 200 ms after send and continuation registration
                            await session.cleanupExpiredPings()
                            confirmation.confirm()
                        }
                    }
                    try await session.sendPing(in: token)
                }
            }
        }
    }
}

// MARK: - Factory Methods

private func makeSUT(
    sessionInitiation: UDPPingSession.SessionInitiation = .init(
        serverAddress: "example.org",
        serverPort: "444",
        token: "Z7kKKZqSYU/j7nSGbjoRLw==",
        ipVersion: .IPv4
    ),
    timeoutIntervalMs: Int = 1000,
    now: @escaping () -> UInt64 = { 0 }
) -> (UDPPingSession, UDPConnectionStub, String) {
    let initiator = SessionInitiatorStub(sessionInitiation: sessionInitiation)
    let udp = UDPConnectionStub()
    let session = UDPPingSession(
        sessionInitiator: initiator,
        udpConnection: udp,
        timeoutIntervalMs: timeoutIntervalMs,
        now: now
    )
    return (session, udp, sessionInitiation.token)
}

private func makeResponse(protocol proto: String, sequence: UInt32) -> Data {
    var data = Data()
    data.append(proto.data(using: .ascii)!)
    data.append(withUnsafeBytes(of: sequence.bigEndian) { Data($0) })
    return data
}

private func decodeSequence(from request: Data) -> UInt32 {
    request[4...7].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
}


// MARK: - Test Doubles

private final class SessionInitiatorStub: UDPPingSession.SessionInitiating {
    let sessionInitiation: UDPPingSession.SessionInitiation
    init(sessionInitiation: UDPPingSession.SessionInitiation) {
        self.sessionInitiation = sessionInitiation
    }
    func initiate() async throws -> UDPPingSession.SessionInitiation { sessionInitiation }
}

private final class UDPConnectionStub: UDPConnectable {
    struct StartParameters: Equatable {
        let host: String
        let port: String
        let ipVersion: IPVersion?
    }

    var onSend: ((Data) -> Void)?
    var onReceive: (() -> Void)?
    var nextResponse: Data = Data()
    var capturedStartParameters: [StartParameters] = []

    func start(host: String, port: String, ipVersion: IPVersion?) async throws(UDPConnectionError) {
        capturedStartParameters.append(.init(host: host, port: port, ipVersion: ipVersion))
    }
    func cancel() { }
    func send(data: Data) async throws { onSend?(data) }
    func receive() async throws -> Data { onReceive?(); return nextResponse }
}
