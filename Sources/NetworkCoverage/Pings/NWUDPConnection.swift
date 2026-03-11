//
//  NWUDPConnection.swift
//  RMBT
//
//  Created by Jiri Urbasek on 18.02.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation
import Network

/// Connected UDP transport using `NWConnection` from Network.framework.
///
/// Retained for comparison and debugging. Not the default transport for
/// Network Coverage pings because a connected UDP endpoint drops replies
/// arriving from a different server IPv6 address than the original destination.
final class NWUDPConnection: UDPConnectable {
    private var connection: NWConnection?

    func start(host: String, port: String, ipVersion: IPVersion?) async throws(UDPConnectionError) {
        connection?.cancel()

        let params = NWParameters.udp
        let ip = params.defaultProtocolStack.internetProtocol! as! NWProtocolIP.Options

        switch ipVersion {
        case .none:
            ip.version = .any
        case .some(.IPv4):
            ip.version = .v4
        case .some(.IPv6):
            ip.version = .v6
        }

        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(port) else {
            throw .invalidHostOrPort
        }

        let conn = NWConnection(host: nwHost, port: nwPort, using: params)

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                conn.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        conn.stateUpdateHandler = nil
                        continuation.resume()
                    case .failed(let error):
                        conn.stateUpdateHandler = nil
                        continuation.resume(throwing: error)
                    case .cancelled:
                        conn.stateUpdateHandler = nil
                        continuation.resume(throwing: UDPConnectionError.connectionNotAvailable)
                    default:
                        break
                    }
                }
                conn.start(queue: .global())
            }
        } catch {
            throw .connectionNotAvailable
        }

        connection = conn
    }

    func cancel() {
        connection?.cancel()
        connection = nil
    }

    func send(data: Data) throws {
        guard let connection else {
            throw UDPConnectionError.connectionNotAvailable
        }
        connection.send(content: data, completion: .idempotent)
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
                    continuation.resume(returning: data ?? Data())
                }
            }
        }
    }
}
