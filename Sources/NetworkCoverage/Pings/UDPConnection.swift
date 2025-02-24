//
//  UDPConnection.swift
//  RMBT
//
//  Created by Jiri Urbasek on 18.02.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation
import Network

enum UDPConnectionError: Error {
    case invalidHostOrPort
    case connectionNotAvailable

}

protocol UDPConnectable {
    func start(host: String, port: String) async throws(UDPConnectionError)
    func cancel()
    func send(data: Data) async throws
    func receive() async throws -> Data
}

final class UDPConnection: UDPConnectable {
    private var connection: NWConnection?

    func start(host: String, port: String) async throws(UDPConnectionError) {
        let params = NWParameters.udp
//        params.allowLocalEndpointReuse = true
//        params.includePeerToPeer = true
        let host = NWEndpoint.Host(host)
        guard let aPort = NWEndpoint.Port(port) else {
            throw .invalidHostOrPort
        }

        connection = NWConnection(host: host, port: aPort, using: params)
        connection?.start(queue: .global())
    }

    func cancel() {
        connection?.cancel()
    }

    func send(data: Data) async throws {
        guard let connection else {
            throw UDPConnectionError.connectionNotAvailable
        }
        return try await withCheckedThrowingContinuation { continuation in
#if DEBUG
            print("UDP: sending: \(String(decoding: data, as: UTF8.self))")
#endif
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: Void())
                }
            })
        }
    }

    func receive() async throws -> Data {
        guard let connection else {
            throw UDPConnectionError.connectionNotAvailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receiveMessage { data, context, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
#if DEBUG
                    print("UDP: received: \(String(decoding: data ?? Data(), as: UTF8.self))")
#endif
                    continuation.resume(returning: data ?? Data())
                }
            }
        }
    }
}
