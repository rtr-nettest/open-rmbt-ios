//
//  UDPPingSession.swift
//  RMBT
//
//  Created by Jiri Urbasek on 18.02.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation

///
/// This type encapsulates commlunication rules against RTR UDP ping server
///
actor UDPPingSession {
    typealias PingSessionToken = String

    protocol SessionInitiating {
        func initiate() async throws -> SessionInitiation
    }

    struct SessionInitiation {
        let serverAddress: String
        let serverPort: String
        let token: PingSessionToken
        let ipVersion: IPVersion?
    }

    typealias AbsoluteTimeNanos = UInt64

    struct PingRequest {
        let sentAt: AbsoluteTimeNanos
        let continuation: CheckedContinuation<Void, any Error>
    }

    enum Const {
        static let requestProtocol = "RP01"
        static let responseProtocol = "RR01"
        static let responseErrorProtocol = "RE01"
        static let responseLength = 8
    }

    private let sessionInitiator: any SessionInitiating

    private var udpConnection: any UDPConnectable
    private var sequenceNumber: UInt32
    private let timeoutIntervalMs: Int
    private let now: () -> AbsoluteTimeNanos

    private var continuations: [UInt32: PingRequest] = [:]
    private var receiverTask: Task<Void, Never>?

    init(
        sessionInitiator: any SessionInitiating,
        udpConnection: any UDPConnectable,
        timeoutIntervalMs: Int,
        now: @escaping () -> AbsoluteTimeNanos // TODO: replace with Clock.Instant
    ) {
        self.sessionInitiator = sessionInitiator
        self.udpConnection = udpConnection
        self.sequenceNumber = UInt32.random(in: 0..<UInt32.max)
        self.timeoutIntervalMs = timeoutIntervalMs
        self.now = now
    }

    func initiatePingSession() async throws -> PingSessionToken {
        let sessionInitiation = try await sessionInitiator.initiate()
        Log.logger.info("UDPPingSession: Starting UDP connection to \(sessionInitiation.serverAddress):\(sessionInitiation.serverPort) (ipVersion: \(sessionInitiation.ipVersion?.description ?? "any"))")
        try await udpConnection.start(
            host: sessionInitiation.serverAddress,
            port: sessionInitiation.serverPort,
            ipVersion: sessionInitiation.ipVersion
        )
        Log.logger.info("UDPPingSession: UDP connection started")
        return sessionInitiation.token
    }

    func sendPing(in authToken: PingSessionToken) async throws(PingSendingError) {
        cleanupExpiredPings()

        sequenceNumber &+= 1
        let currentSequence = sequenceNumber
        let message = try makePingMessage(sequence: currentSequence, authToken: authToken)

        Log.logger.debug("UDPPingSession: Sending ping with sequence number \(currentSequence), auth token \(authToken.prefix(4))...\(authToken.suffix(4))")

        try await awaitPingResponse(sequence: currentSequence, message: message)
    }

    // MARK: - Private helpers

    private func makePingMessage(sequence: UInt32, authToken: PingSessionToken) throws(PingSendingError) -> Data {
        var message = Data()
        message.append(Const.requestProtocol.data(using: .ascii)!)
        message.append(withUnsafeBytes(of: sequence.bigEndian) { Data($0) })

        guard let tokenBytes = Data(base64Encoded: authToken) else {
            throw .needsReinitialization
        }
        message.append(tokenBytes)
        return message
    }

    private func awaitPingResponse(sequence: UInt32, message: Data) async throws(PingSendingError) {
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.continuations[sequence] = .init(sentAt: self.now(), continuation: continuation)
                    self.startReceiveLoopIfNeeded()

                    do {
                        try self.udpConnection.send(data: message)
                    } catch {
                        self.continuations[sequence] = nil
                        Log.logger.warning("UDPPingSession: Send failed with error: \(error)")
                        continuation.resume(throwing: PingSendingError.networkIssue)
                    }
                }
            } onCancel: {
                Task { await self.cancelContinuation(sequence: sequence, error: CancellationError()) }
            }
        } catch let error as PingSendingError {
            throw error
        } catch {
            throw .networkIssue
        }
    }

    private func startReceiveLoopIfNeeded() {
        guard receiverTask == nil else { return }
        receiverTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveResponses()
        }
    }

    private func receiveResponses() async {
        defer { receiverTask = nil }
        while !Task.isCancelled {
            do {
                let response = try await udpConnection.receive()
                receivedPingResponse(response)
            } catch is CancellationError {
                break
            } catch {
                Log.logger.warning("UDPPingSession: Receive loop failed with error: \(error), failing \(continuations.count) pending request(s)")
                failPendingRequests(with: .networkIssue)
                break
            }
        }
    }

    private func failPendingRequests(with error: PingSendingError) {
        guard !continuations.isEmpty else { return }
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.value.continuation.resume(throwing: error) }
    }

    private func cancelContinuation(sequence: UInt32, error: Error) async {
        if let request = continuations.removeValue(forKey: sequence) {
            request.continuation.resume(throwing: error)
        }
    }

    private func receivedPingResponse(_ response: Data) {
        cleanupExpiredPings()

        guard response.count >= Const.responseLength else { return }

        let protocolName = String(decoding: response[0...3], as: UTF8.self)
        let sequenceNumber = response[4...7].withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }

        Log.logger.debug("UDPPingSession: Received \(protocolName) response for sequence \(sequenceNumber).")

        switch protocolName {
        case Const.responseErrorProtocol:
            guard let sentRequest = continuations[sequenceNumber] else {
                Log.logger.debug("UDPPingSession: Ignoring \(protocolName) response for unknown sequence \(sequenceNumber).")
                return
            }
            continuations[sequenceNumber] = nil
            sentRequest.continuation.resume(throwing: PingSendingError.needsReinitialization)
        case Const.responseProtocol:
            guard let sentRequest = continuations[sequenceNumber] else {
                Log.logger.debug("UDPPingSession: Ignoring \(protocolName) response for unknown sequence \(sequenceNumber).")
                return
            }
            continuations[sequenceNumber] = nil
            sentRequest.continuation.resume()
        default:
            return
        }
    }

    func cleanupExpiredPings() {
        // Walk through `continuations` and resume timed out requests with `.timedOut`.
        let nowNanos = now()
        let timeoutNanos = UInt64(max(0, timeoutIntervalMs)) * 1_000_000
        if timeoutNanos == 0 { return }

        if !continuations.isEmpty {
            for (seq, request) in continuations {
                if nowNanos &- request.sentAt >= timeoutNanos {
                    continuations[seq] = nil
                    request.continuation.resume(throwing: PingSendingError.timedOut)
                }
            }
        }
    }

    nonisolated deinit {
        // These accesses are safe: at deinit time no other code can reference
        // this actor, so there is no data race. Swift 5 mode allows it with a warning.
        Log.logger.info("UDPPingSession: Deinit, cancelling \(continuations.count) pending request(s)")
        failPendingRequests(with: .networkIssue)
        udpConnection.cancel()
        receiverTask?.cancel()
    }
}
