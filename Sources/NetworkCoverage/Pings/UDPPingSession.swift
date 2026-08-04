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

    struct SessionInitiation: Sendable {
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
    /// Incremented on every activation. A receive loop belonging to a superseded transport must not touch state
    /// owned by a newer one — its `receive()` can only unwind asynchronously, well after the new transport is up.
    private var transportEpoch = 0
    /// `activateSession` suspends while the transport restarts. The actor is re-entrant during that suspension, so
    /// sends queued for the session being replaced must not run against a transport that is mid-swap.
    private var isActivating = false

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

    /// Fetches the credentials of a new session. Deliberately does not touch `udpConnection`, so that an
    /// already running session keeps being able to send pings while this (potentially long) call is in flight.
    func prepareSession() async throws -> SessionInitiation {
        try await sessionInitiator.initiate()
    }

    /// Points the transport at the prepared session. This tears the previous connection down, so it is only
    /// ever run once the credentials it belongs to are already committed.
    func activateSession(_ session: SessionInitiation) async throws {
        Log.logger.info("UDPPingSession: Starting UDP connection to \(session.serverAddress):\(session.serverPort) (ipVersion: \(session.ipVersion?.description ?? "any"))")

        // Retire the previous transport's receive loop before the transport goes away. Its `receive()` unwinds
        // asynchronously (`NWUDPConnection`) or not at all (`AsyncSocketUDPConnection` never resumes a pending
        // receive on restart), so it must neither fail the next session's requests nor block a new loop from
        // starting by leaving `receiverTask` populated.
        transportEpoch += 1
        receiverTask?.cancel()
        receiverTask = nil
        isActivating = true
        defer { isActivating = false }

        // Requests still waiting on the previous transport can never be answered now.
        failPendingRequests(with: .networkIssue)

        try await udpConnection.start(
            host: session.serverAddress,
            port: session.serverPort,
            ipVersion: session.ipVersion
        )
        Log.logger.info("UDPPingSession: UDP connection started")
    }

    func sendPing(in session: SessionInitiation) async throws(PingSendingError) {
        // Fail fast rather than register a request against a transport that is being swapped: doing so would also
        // start a receive loop on the outgoing connection, which then either parks (blocking the replacement's loop
        // from ever starting) or fails the replacement session's requests when it unwinds.
        guard !isActivating else {
            Log.logger.debug("UDPPingSession: Dropping ping queued for a session whose transport is being replaced")
            throw .networkIssue
        }

        cleanupExpiredPings()

        let authToken = session.token
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
        let epoch = transportEpoch
        receiverTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveResponses(epoch: epoch)
        }
    }

    private func receiveResponses(epoch: Int) async {
        defer {
            // Only clear the shared handle if it still refers to this loop; a newer activation may already own it.
            if epoch == transportEpoch { receiverTask = nil }
        }
        while !Task.isCancelled {
            do {
                let response = try await udpConnection.receive()
                guard epoch == transportEpoch else { break }
                receivedPingResponse(response)
            } catch is CancellationError {
                break
            } catch {
                // A superseded transport's failure says nothing about the requests of the current one.
                guard epoch == transportEpoch else { break }
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
