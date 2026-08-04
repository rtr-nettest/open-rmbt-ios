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

            let (sut, udp, expectedSession) = makeSUT(sessionInitiation: .init(
                serverAddress: host,
                serverPort: port,
                token: token,
                ipVersion: ipVersion
            ))

            let obtained = try await sut.startSession()
            #expect(obtained.token == expectedSession.token)

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
            let (sut, udp, expectedSession) = makeSUT(sessionInitiation: initiation)

            let returned = try await sut.startSession()
            #expect(returned.token == expectedSession.token)

            #expect(udp.capturedStartParameters == [
                .init(host: "ping.rtr.example", port: "1919", ipVersion: nil)
            ])
        }

        @Test("WHEN sending pings after initiation THEN start() is called exactly once")
        func whenSendingPingsAfterInitiation_thenStartCalledExactlyOnce() async throws {
            let (sut, udp, _) = makeSUT()

            let session = try await sut.startSession()
            #expect(udp.capturedStartParameters.count == 1)

            udp.onSend = { data in
                udp.nextResponse = makeResponse(protocol: "RR01", sequence: decodeSequence(from: data))
            }

            try await sut.sendPing(in: session)
            try await sut.sendPing(in: session)

            #expect(udp.capturedStartParameters.count == 1)
        }

        @Test("WHEN session initiator fails THEN preparing a session propagates the error")
        func whenSessionInitiatorFails_thenPreparingSessionPropagatesError() async throws {
            let (sut, _, _) = makeSUT(initiateError: makeError())

            await #expect(throws: (any Error).self) {
                try await sut.startSession()
            }
        }

        @Test("WHEN UDP connection start fails THEN activating the session propagates the error")
        func whenUDPConnectionStartFails_thenActivatingSessionPropagatesError() async throws {
            let (sut, udp, _) = makeSUT()
            udp.startError = .connectionNotAvailable

            await #expect(throws: (any Error).self) {
                try await sut.startSession()
            }
        }

        @Test("WHEN preparing a session THEN the transport is left untouched")
        func whenPreparingSession_thenTransportIsNotTouched() async throws {
            let (sut, udp, _) = makeSUT()

            _ = try await sut.prepareSession()

            // The previous session must stay able to send while a replacement is being fetched.
            #expect(udp.capturedStartParameters.isEmpty)
            #expect(udp.cancelCallCount == 0)
        }

        @Test("WHEN a session is activated THEN pings still pending on the previous transport fail")
        func whenSessionIsActivated_thenPingsPendingOnPreviousTransportFail() async throws {
            let (sut, udp, _) = makeSUT()
            let session = try await sut.startSession()

            let sendStarted = Signal()
            udp.onSend = { _ in sendStarted.send() }
            let pendingPing = Task { try await sut.sendPing(in: session) }
            await sendStarted.wait()

            try await sut.activateSession(session)

            await #expect(throws: PingSendingError.networkIssue) {
                try await pendingPing.value
            }
        }
    }

    @Suite("Protocol Encoding Tests")
    struct ProtocolEncodingTests {
        @Test("WHEN sending ping THEN payload contains RP01, sequence and token bytes")
        func whenSendingPing_thenPayloadContainsRP01SequenceAndTokenBytes() async throws {
            let (sut, udp, expectedSession) = makeSUT()

            var capturedRequest: Data?
            udp.onSend = { data in
                capturedRequest = data
                let seq = decodeSequence(from: data)
                udp.nextResponse = makeResponse(protocol: "RR01", sequence: seq)
            }

            let session = try await sut.startSession()
            try await sut.sendPing(in: session)

            let data = try #require(capturedRequest)

            #expect(String(decoding: data[0...3], as: UTF8.self) == "RP01")
            #expect(data.dropFirst(8) == Data(base64Encoded: expectedSession.token))
        }

        @Test("WHEN sending multiple pings THEN each uses an incrementing sequence number")
        func whenSendingMultiplePings_thenEachUsesIncrementingSequenceNumber() async throws {
            let (sut, udp, _) = makeSUT()
            let session = try await sut.startSession()

            var capturedSequences: [UInt32] = []
            udp.onSend = { data in
                let seq = decodeSequence(from: data)
                capturedSequences.append(seq)
                udp.nextResponse = makeResponse(protocol: "RR01", sequence: seq)
            }

            try await sut.sendPing(in: session)
            try await sut.sendPing(in: session)
            try await sut.sendPing(in: session)

            #expect(capturedSequences.count == 3)
            #expect(Set(capturedSequences).count == 3)
            #expect(capturedSequences[1] == capturedSequences[0] &+ 1)
            #expect(capturedSequences[2] == capturedSequences[1] &+ 1)
        }
    }

    @Suite("Response Handling Tests")
    struct ResponseHandlingTests {
        @Test("WHEN RR01 matches sequence THEN succeeds")
        func whenRR01WithMatchingSeq_thenSucceeds() async throws {
            let (sut, udp, expectedSession) = makeSUT()
            let session = try await sut.startSession()
            #expect(session.token == expectedSession.token)

            udp.onSend = { data in
                udp.nextResponse = makeResponse(protocol: "RR01", sequence: decodeSequence(from: data))
            }

            try await sut.sendPing(in: session)
        }

        @Test("WHEN RE01 matches sequence THEN throws needsReinitialization")
        func whenRE01WithMatchingSeq_thenThrowsNeedsReinitialization() async throws {
            let (sut, udp, _) = makeSUT()
            let session = try await sut.startSession()

            udp.onSend = { data in
                udp.nextResponse = makeResponse(protocol: "RE01", sequence: decodeSequence(from: data))
            }

            await #expect(throws: PingSendingError.needsReinitialization) {
                try await sut.sendPing(in: session)
            }
        }

        @Test("WHEN RE01 without matching sequence THEN request stays pending and valid response succeeds")
        func whenRE01WithoutMatchingSequence_thenRequestStaysPending() async throws {
            let (sut, udp, _) = makeSUT()
            let session = try await sut.startSession()

            udp.onSend = { data in
                let seq = decodeSequence(from: data)
                // Broadcast RE01 for unknown sequence — should be ignored
                udp.nextResponse = makeResponse(protocol: "RE01", sequence: 0)
                // Then deliver the valid response
                udp.nextResponse = makeResponse(protocol: "RR01", sequence: seq)
            }

            try await sut.sendPing(in: session)
        }

        @Test("WHEN token is invalid base64 THEN sendPing throws needsReinitialization")
        func whenTokenIsInvalidBase64_thenSendPingThrowsNeedsReinitialization() async throws {
            let (sut, _, _) = makeSUT()
            _ = try await sut.startSession()

            let sessionWithInvalidToken = makeSessionInitiation(token: "not-valid-base64!!!")
            await #expect(throws: PingSendingError.needsReinitialization) {
                try await sut.sendPing(in: sessionWithInvalidToken)
            }
        }

        @Test("WHEN response is shorter than 8 bytes THEN it is ignored and valid response succeeds")
        func whenResponseShorterThan8Bytes_thenIgnoredAndValidResponseSucceeds() async throws {
            let (sut, udp, _) = makeSUT()
            let session = try await sut.startSession()

            udp.onSend = { data in
                let seq = decodeSequence(from: data)
                let tooShortResponse = Data([0x52, 0x52, 0x30, 0x31]) // "RR01" but only 4 bytes
                udp.nextResponse = tooShortResponse
                udp.nextResponse = makeResponse(protocol: "RR01", sequence: seq)
            }

            try await sut.sendPing(in: session)
        }

        @Test("WHEN response has unknown protocol THEN it is ignored and valid response succeeds")
        func whenResponseHasUnknownProtocol_thenIgnoredAndValidResponseSucceeds() async throws {
            let (sut, udp, _) = makeSUT()
            let session = try await sut.startSession()

            udp.onSend = { data in
                let seq = decodeSequence(from: data)
                udp.nextResponse = makeResponse(protocol: "XX99", sequence: seq)
                udp.nextResponse = makeResponse(protocol: "RR01", sequence: seq)
            }

            try await sut.sendPing(in: session)
        }
    }

    @Suite("Timeout Tests")
    struct TimeoutTests {
        @Test("WHEN pending ping exceeds timeout THEN it is cleaned up with timedOut error")
        func whenPendingPingTimesOut_thenIsCleanedUp() async throws {
            var nowNanos: UInt64 = 0
            let (sut, udp, _) = makeSUT(timeoutIntervalMs: 100, now: { nowNanos })
            let session = try await sut.startSession()

            await #expect(throws: PingSendingError.timedOut) {
                try await confirmation("Ping continuation registered and cleaned up", expectedCount: 1) { confirmation in
                    udp.onSend = { _ in
                        Task {
                            nowNanos = 200_000_000 // 200 ms after registration
                            await sut.cleanupExpiredPings()
                            confirmation.confirm()
                        }
                    }
                    try await sut.sendPing(in: session)
                }
            }
        }
    }

    @Suite("Send Failure Tests")
    struct SendFailureTests {
        @Test("WHEN transport send fails THEN sendPing throws networkIssue")
        func whenTransportSendFails_thenSendPingThrowsNetworkIssue() async throws {
            let (sut, udp, _) = makeSUT()
            let session = try await sut.startSession()

            udp.sendError = UDPConnectionError.connectionNotAvailable

            await #expect(throws: PingSendingError.networkIssue) {
                try await sut.sendPing(in: session)
            }
        }

        @Test("WHEN transport send fails THEN failed sequence is removed from pending requests")
        func whenTransportSendFails_thenFailedSequenceIsRemovedFromPendingRequests() async throws {
            let (sut, udp, _) = makeSUT()
            let session = try await sut.startSession()

            var capturedSequence: UInt32?
            udp.sendError = UDPConnectionError.connectionNotAvailable
            udp.onSend = { data in
                capturedSequence = decodeSequence(from: data)
            }

            // First ping fails
            await #expect(throws: PingSendingError.networkIssue) {
                try await sut.sendPing(in: session)
            }

            // Now allow sends, and send a late RR01 for the failed sequence —
            // it should be ignored, and a new ping should succeed.
            udp.sendError = nil
            udp.onSend = { data in
                // First, deliver a late response for the failed sequence
                if let failedSeq = capturedSequence {
                    udp.nextResponse = makeResponse(protocol: "RR01", sequence: failedSeq)
                }
                // Then deliver the correct response for this new ping
                let seq = decodeSequence(from: data)
                udp.nextResponse = makeResponse(protocol: "RR01", sequence: seq)
            }
            try await sut.sendPing(in: session)
        }

        @Test("WHEN receive loop fails THEN pending pings fail with networkIssue")
        func whenReceiveLoopFails_thenPendingPingsFailWithNetworkIssue() async throws {
            let (sut, udp, _) = makeSUT()
            let session = try await sut.startSession()

            udp.onSend = { _ in
                udp.failNextReceive(with: makeError())
            }

            await #expect(throws: PingSendingError.networkIssue) {
                try await sut.sendPing(in: session)
            }
        }
    }

    @Suite("Lifecycle Tests")
    struct LifecycleTests {
        @Test("WHEN session is deinitialized THEN cancel is called on transport")
        func whenSessionDeinitialized_thenCancelIsCalledOnTransport() async throws {
            let udp = UDPConnectionStub()
            var sut: UDPPingSession? = UDPPingSession(
                sessionInitiator: SessionInitiatorStub(sessionInitiation: .init(
                    serverAddress: "example.org",
                    serverPort: "444",
                    token: "Z7kKKZqSYU/j7nSGbjoRLw==",
                    ipVersion: .IPv4
                )),
                udpConnection: udp,
                timeoutIntervalMs: 1000,
                now: { 0 }
            )
            _ = try await sut!.startSession()

            #expect(udp.cancelCallCount == 0)
            sut = nil

            #expect(udp.cancelCallCount == 1)
        }
    }

    @Suite("Concurrency Safeguards")
    struct ConcurrencySafeguards {
        @Test("WHEN multiple ping requests overlap THEN only one UDP receive is pending at a time")
        func whenMultiplePingRequestsOverlap_thenOnlySingleReceiveInFlight() async throws {
            let (sut, trackingUDP, _) = makeSUTWithTracking()
            let session = try await sut.startSession()

            var sendTasks: [Task<Void, Error>] = []
            for _ in 0..<3 {
                sendTasks.append(Task {
                    try await sut.sendPing(in: session)
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

// MARK: - makeSUT & Factories

private func makeSUT(
    sessionInitiation: UDPPingSession.SessionInitiation = .init(
        serverAddress: "example.org",
        serverPort: "444",
        token: "Z7kKKZqSYU/j7nSGbjoRLw==",
        ipVersion: .IPv4
    ),
    initiateError: (any Error)? = nil,
    timeoutIntervalMs: Int = 1000,
    now: @escaping () -> UInt64 = { 0 }
) -> (UDPPingSession, UDPConnectionStub, UDPPingSession.SessionInitiation) {
    let initiator = SessionInitiatorStub(sessionInitiation: sessionInitiation, error: initiateError)
    let udp = UDPConnectionStub()
    let sut = UDPPingSession(
        sessionInitiator: initiator,
        udpConnection: udp,
        timeoutIntervalMs: timeoutIntervalMs,
        now: now
    )
    return (sut, udp, sessionInitiation)
}

private func makeSUTWithTracking(
    sessionInitiation: UDPPingSession.SessionInitiation = .init(
        serverAddress: "example.org",
        serverPort: "444",
        token: "Z7kKKZqSYU/j7nSGbjoRLw==",
        ipVersion: .IPv4
    ),
    timeoutIntervalMs: Int = 1000,
    now: @escaping () -> UInt64 = { 0 }
) -> (UDPPingSession, TrackingUDPConnectionStub, UDPPingSession.SessionInitiation) {
    let initiator = SessionInitiatorStub(sessionInitiation: sessionInitiation)
    let udp = TrackingUDPConnectionStub()
    let sut = UDPPingSession(
        sessionInitiator: initiator,
        udpConnection: udp,
        timeoutIntervalMs: timeoutIntervalMs,
        now: now
    )
    return (sut, udp, sessionInitiation)
}

private func makeSessionInitiation(
    serverAddress: String = "example.org",
    serverPort: String = "444",
    token: String = "Z7kKKZqSYU/j7nSGbjoRLw==",
    ipVersion: IPVersion? = .IPv4
) -> UDPPingSession.SessionInitiation {
    .init(serverAddress: serverAddress, serverPort: serverPort, token: token, ipVersion: ipVersion)
}

/// Brings a session up through both phases, which is what the ping loop does for a fresh session.
private extension UDPPingSession {
    func startSession() async throws -> SessionInitiation {
        let session = try await prepareSession()
        try await activateSession(session)
        return session
    }
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

private func makeError(
    domain: String = "test",
    code: Int = Int.random(in: 1...9999)
) -> NSError {
    NSError(domain: domain, code: code)
}


// MARK: - Test Doubles

/// One-shot signal used to await a step that happens inside a synchronous transport callback.
private final class Signal: @unchecked Sendable {
    private let lock = NSLock()
    private var isSent = false

    func send() {
        lock.lock()
        defer { lock.unlock() }
        isSent = true
    }

    func wait() async {
        while true {
            let isSent = lock.withLock { self.isSent }
            if isSent { return }
            await Task.yield()
        }
    }
}

private final class SessionInitiatorStub: UDPPingSession.SessionInitiating {
    let sessionInitiation: UDPPingSession.SessionInitiation
    let error: (any Error)?

    init(
        sessionInitiation: UDPPingSession.SessionInitiation,
        error: (any Error)? = nil
    ) {
        self.sessionInitiation = sessionInitiation
        self.error = error
    }

    func initiate() async throws -> UDPPingSession.SessionInitiation {
        if let error { throw error }
        return sessionInitiation
    }
}

private final class UDPConnectionStub: UDPConnectable {
    struct StartParameters: Equatable {
        let host: String
        let port: String
        let ipVersion: IPVersion?
    }

    private let lock = NSLock()
    var onSend: ((Data) -> Void)?
    var sendError: (any Error)?
    var startError: UDPConnectionError?
    var capturedStartParameters: [StartParameters] = []
    private(set) var cancelCallCount = 0

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
        if let startError { throw startError }
    }
    func cancel() {
        cancelCallCount += 1
    }
    func send(data: Data) throws {
        onSend?(data)
        if let sendError { throw sendError }
    }

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
    private var _cancelCallCount = 0

    var capturedStartParameters: [StartParameters] {
        lock.withLock { _capturedStartParameters }
    }

    var cancelCallCount: Int {
        lock.withLock { _cancelCallCount }
    }

    func start(host: String, port: String, ipVersion: IPVersion?) async throws(UDPConnectionError) {
        lock.withLock {
            _capturedStartParameters.append(.init(host: host, port: port, ipVersion: ipVersion))
        }
    }

    func cancel() {
        lock.withLock { _cancelCallCount += 1 }
    }

    func send(data: Data) throws {
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
