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

        @Test("WHEN RE01 without matching sequence THEN request stays pending")
        func whenRE01WithoutMatchingSequence_thenRequestStaysPending() async throws {
            let (sut, udp, token) = makeSUT()
            let auth = try await sut.initiatePingSession()
            #expect(auth == token)

            udp.onSend = { data in
                // simulate broadcast RE01 for unknown sequence followed by real response
                udp.nextResponse = makeResponse(protocol: "RE01", sequence: 0)
                let seq = decodeSequence(from: data)
                udp.nextResponse = makeResponse(protocol: "RR01", sequence: seq)
            }

            try await sut.sendPing(in: auth)
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

    @Suite("Concurrency Safeguards")
    struct ConcurrencySafeguards {
        @Test("WHEN multiple ping requests overlap THEN only one UDP receive is pending at a time")
        func whenMultiplePingRequestsOverlap_thenOnlySingleReceiveInFlight() async throws {
            let trackingUDP = TrackingUDPConnectionStub()
            let sessionInitiation = UDPPingSession.SessionInitiation(
                serverAddress: "example.org",
                serverPort: "444",
                token: "Z7kKKZqSYU/j7nSGbjoRLw==",
                ipVersion: .IPv4
            )
            let session = UDPPingSession(
                sessionInitiator: SessionInitiatorStub(sessionInitiation: sessionInitiation),
                udpConnection: trackingUDP,
                timeoutIntervalMs: 1000,
                now: { 0 }
            )
            let token = try await session.initiatePingSession()

            var sendTasks: [Task<Void, Error>] = []
            for _ in 0..<3 {
                sendTasks.append(Task {
                    try await session.sendPing(in: token)
                })
                await trackingUDP.waitForPendingReceives(count: sendTasks.count)
            }

            let concurrentReceives = await trackingUDP.maxConcurrentReceivingOperations()
            #expect(concurrentReceives == 1)

            await trackingUDP.resumeAllPendingReceivesAsSuccess()
            for task in sendTasks {
                try await task.value
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

    private let lock = NSLock()
    var onSend: ((Data) -> Void)?
    var capturedStartParameters: [StartParameters] = []

    var onReceive: (() -> Void)? {
        didSet {
            guard onReceive != nil else { return }
            let shouldInvoke = lock.withLock { !pendingReceives.isEmpty && queuedResponses.isEmpty }
            if shouldInvoke {
                onReceive?()
            }
        }
    }

    private var pendingReceives: [CheckedContinuation<Data, Error>] = []
    private var queuedResponses: [Result<Data, Error>] = []

    func start(host: String, port: String, ipVersion: IPVersion?) async throws(UDPConnectionError) {
        capturedStartParameters.append(.init(host: host, port: port, ipVersion: ipVersion))
    }
    func cancel() { }
    func send(data: Data) async throws { onSend?(data) }

    func receive() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            if let result = lock.withLock({ queuedResponses.isEmpty ? nil : queuedResponses.removeFirst() }) {
                resume(continuation, with: result)
            } else {
                lock.withLock { pendingReceives.append(continuation) }
                onReceive?()
            }
        }
    }

    var nextResponse: Data {
        get { fatalError("nextResponse getter should not be used in tests") }
        set { enqueue(.success(newValue)) }
    }

    func failNextReceive(with error: Error) {
        enqueue(.failure(error))
    }

    private func enqueue(_ result: Result<Data, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Data, Error>? in
            if pendingReceives.isEmpty {
                queuedResponses.append(result)
                return nil
            } else {
                return pendingReceives.removeFirst()
            }
        }

        if let continuation {
            resume(continuation, with: result)
        }
    }

    private func resume(_ continuation: CheckedContinuation<Data, Error>, with result: Result<Data, Error>) {
        switch result {
        case .success(let data):
            continuation.resume(returning: data)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private final class TrackingUDPConnectionStub: UDPConnectable {
    struct StartParameters: Equatable {
        let host: String
        let port: String
        let ipVersion: IPVersion?
    }

    private let lock = NSLock()
    private var receiveContinuations: [CheckedContinuation<Data, Error>] = []
    private var pendingSequences: [UInt32] = []
    private var currentReceiveCount = 0
    private var maxReceiveCount = 0
    private var _capturedStartParameters: [StartParameters] = []

    var capturedStartParameters: [StartParameters] {
        lock.withLock { _capturedStartParameters }
    }

    func start(host: String, port: String, ipVersion: IPVersion?) async throws(UDPConnectionError) {
        lock.withLock {
            _capturedStartParameters.append(.init(host: host, port: port, ipVersion: ipVersion))
        }
    }

    func cancel() { }

    func send(data: Data) async throws {
        let sequence = decodeSequence(from: data)
        lock.withLock {
            pendingSequences.append(sequence)
        }
    }

    func receive() async throws -> Data {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            lock.withLock {
                currentReceiveCount += 1
                if currentReceiveCount > maxReceiveCount {
                    maxReceiveCount = currentReceiveCount
                }
                receiveContinuations.append(continuation)
            }
        }
    }

    func waitForPendingReceives(count: Int) async {
        while true {
            let state = lock.withLock { (pendingSequences.count, receiveContinuations.isEmpty) }
            if state.0 >= count && !state.1 { break }
            await Task.yield()
        }
    }

    func resumeAllPendingReceivesAsSuccess() async {
        var remaining = lock.withLock { pendingSequences.count }
        while remaining > 0 {
            let item: (CheckedContinuation<Data, Error>, UInt32)? = lock.withLock {
                guard !receiveContinuations.isEmpty else { return nil }
                let continuation = receiveContinuations.removeFirst()
                let sequence = pendingSequences.isEmpty ? 0 : pendingSequences.removeFirst()
                currentReceiveCount = max(0, currentReceiveCount - 1)
                return (continuation, sequence)
            }
            guard let (continuation, sequence) = item else {
                await Task.yield()
                continue
            }
            let response = makeResponse(protocol: UDPPingSession.Const.responseProtocol, sequence: sequence)
            continuation.resume(returning: response)
            remaining -= 1
            await Task.yield()
        }
    }

    func maxConcurrentReceivingOperations() -> Int {
        lock.withLock { maxReceiveCount }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
