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
    private var authToken: String?
    private var sequenceNumber: UInt32
    private let timeoutIntervalMs: Int
    private let now: () -> AbsoluteTimeNanos

    private var continuations: [UInt32: PingRequest] = [:]

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
        try await udpConnection.start(
            host: sessionInitiation.serverAddress,
            port: sessionInitiation.serverPort,
            ipVersion: sessionInitiation.ipVersion
        )
        return sessionInitiation.token
    }

    func sendPing(in authToken: PingSessionToken) async throws(PingSendingError) {
        cleanupExpiredPings()

        sequenceNumber &+= 1
        var message = Data()
        message.append(Const.requestProtocol.data(using: .ascii)!)
        message.append(withUnsafeBytes(of: sequenceNumber.bigEndian) { Data($0) })

        guard let tokenBytes = Data(base64Encoded: authToken) else {
            throw .needsReinitialization
        }
        message.append(tokenBytes)

        do {
            try await udpConnection.send(data: message)
        } catch {
            throw .networkIssue
        }

        do {
            try await withCheckedThrowingContinuation { continuation in
                self.continuations[self.sequenceNumber] = .init(sentAt: self.now(), continuation: continuation)
                Task {
                    let response = try await self.udpConnection.receive()
                    receivedPingResponse(response)
                }
            }
        } catch let error as PingSendingError {
            throw error
        } catch {
            throw .networkIssue
        }
    }

    private func receivedPingResponse(_ response: Data) {
        cleanupExpiredPings()

        guard response.count >= Const.responseLength else { return }

        let protocolName = String(decoding: response[0...3], as: UTF8.self)
        let sequenceNumber = response[4...7].withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }

        switch protocolName {
        case Const.responseErrorProtocol:
            if let sentRequest = continuations[sequenceNumber] {
                continuations[sequenceNumber] = nil
                sentRequest.continuation.resume(throwing: PingSendingError.needsReinitialization)
            } else {
                // Error without a matching sequence (e.g., seq=0x0) — treat as global reinit signal
                if !continuations.isEmpty {
                    let pending = continuations
                    continuations.removeAll()
                    pending.forEach {
                        $0.value.continuation.resume(throwing: PingSendingError.needsReinitialization)
                    }
                }
            }
        case Const.responseProtocol:
            guard let sentRequest = continuations[sequenceNumber] else { return }
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
}
