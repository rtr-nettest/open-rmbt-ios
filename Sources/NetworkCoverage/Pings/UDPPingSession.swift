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
    protocol SessionInitiating {
        func initiate() async throws -> SessionInitiation
    }

    struct SessionInitiation {
        let serverAddress: String
        let serverPort: UInt16
        let token: String
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
    private let createUDPClient: (SessionInitiation) -> UDPClient

    private var udpClient: UDPClient?
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
        createUDPClient: @escaping (SessionInitiation) -> UDPClient,
        timeoutIntervalMs: Int,
        now: @escaping () -> AbsoluteTimeNanos
    ) {
        self.sessionInitiator = sessionInitiator
        self.createUDPClient = createUDPClient
        self.sequenceNumber = UInt32.random(in: 0..<UInt32.max)
        self.timeoutIntervalMs = timeoutIntervalMs
        self.now = now
    }
    
    func sendPing() async throws {
        let udpClient: UDPClient
        let authToken: String

        if let savedUdpClient = self.udpClient, let savedAuthToken = self.authToken {
            udpClient = savedUdpClient
            authToken = savedAuthToken
        } else {
            let sessionInitiation = try await sessionInitiator.initiate()
            udpClient = createUDPClient(sessionInitiation)
            authToken = sessionInitiation.token
            udpClient.onReceivedData = { [weak self] data in
                Task { await self?.receivedPingResponse(data) }
            }
            self.udpClient = udpClient
            self.authToken = authToken
        }

        cleanupExpiredPings()

        try await withCheckedThrowingContinuation { continuation in
            sequenceNumber &+= 1

            var message = Data()
            message.append(requestProtocol.data(using: .ascii)!)
            message.append(withUnsafeBytes(of: sequenceNumber.bigEndian) { Data($0) })
            message.append(Data(base64Encoded: authToken)!)

            udpClient.send(message) {
                switch $0 {
                case .success:
                    self.continuations[self.sequenceNumber] = .init(sentAt: self.now(), continuation: continuation)

                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(self.timeoutIntervalMs)) {
                        if let continuation = self.continuations[self.sequenceNumber] {
                            self.continuations[self.sequenceNumber]?.continuation.resume(throwing: URLError(.timedOut))
                            self.continuations[self.sequenceNumber] = nil
                        }
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
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
        sentRequest.continuation.resume()
    }

    func cleanupExpiredPings() {
        // walk through `continuations`, use now() to check for request wich are timed out
    }
}
