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
    private let requestProtocol = "RP01"
    private let responseProtocol = "RR01"
    private let responseErrorProtocol = "RE01"
    private let responseLength = 8

    init(
        sessionInitiator: any SessionInitiating,
        udpConnection: any UDPConnectable,
        timeoutIntervalMs: Int,
        now: @escaping () -> AbsoluteTimeNanos
    ) {
        self.sessionInitiator = sessionInitiator
        self.udpConnection = udpConnection
        self.sequenceNumber = UInt32.random(in: 0..<UInt32.max)
        self.timeoutIntervalMs = timeoutIntervalMs
        self.now = now
    }

    func initiatePingSession() async throws -> PingSessionToken {
        let sessionInitiation = try await sessionInitiator.initiate()
        try await udpConnection.start(host: sessionInitiation.serverAddress, port: sessionInitiation.serverPort)
        return sessionInitiation.token
    }

    func sendPing(in authToken: PingSessionToken) async throws(PingSendingError) {
        cleanupExpiredPings()

        sequenceNumber &+= 1
        var message = Data()
        message.append(requestProtocol.data(using: .ascii)!)
        message.append(withUnsafeBytes(of: sequenceNumber.bigEndian) { Data($0) })
        message.append(Data(base64Encoded: authToken)!)

        do {
            try await udpConnection.send(data: message)
        } catch {
            throw .networkIssue
        }

        do {
            try await withCheckedThrowingContinuation { continuation in
                self.continuations[self.sequenceNumber] = .init(sentAt: self.now(), continuation: continuation)
                Task {
                    receivedPingResponse(try await udpConnection.receive())
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

        guard
            protocolName == Const.responseProtocol || protocolName == Const.responseErrorProtocol,
            let sentRequest = continuations[sequenceNumber] else {
            return
        }
        continuations[sequenceNumber] = nil

        if protocolName == Const.responseErrorProtocol {
            sentRequest.continuation.resume(throwing: PingSendingError.needsReinitialization)
        } else {
            sentRequest.continuation.resume()
        }
    }

    func cleanupExpiredPings() {
        // walk through `continuations`, use now() to check for request wich are timed out
    }
}
