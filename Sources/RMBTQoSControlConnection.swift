//
//  RMBTQoSControlConnection.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 18.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import Foundation
import Network

// We use long to be compatible with the historical tag datatype.
enum RMBTQoSControlConnectionState: Int {
    case disconnected
    case disconnecting
    case connecting
    case authenticating
    case authenticated
}

enum RMBTQoSControlConnectionError: LocalizedError {
    case timeout
    case connectionClosed
    case invalidEndpoint
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .timeout:          return "QoS control connection timed out"
        case .connectionClosed: return "QoS control connection was closed"
        case .invalidEndpoint:  return "QoS control server endpoint is invalid"
        case .encodingFailed:   return "Failed to encode QoS control command"
        }
    }
}

/// Line-oriented, TLS-secured control connection to the QoS server.
///
/// Historically this used `GCDAsyncSocket.startTLS`, which is backed by the deprecated
/// SecureTransport stack and caps at TLS 1.2. Modern QoS servers negotiate TLS 1.3, so the
/// handshake failed and every control-connection based test (TCP, UDP, non-transparent proxy)
/// errored out. This implementation uses `NWConnection`, which negotiates TLS 1.2 **and** 1.3.
class RMBTQoSControlConnection: NSObject, @unchecked Sendable {
    private(set) var token: String

    private let params: RMBTQoSControlConnectionParams

    /// All connection state and Network.framework callbacks run on this serial queue.
    private let connectionQueue = DispatchQueue(label: "at.rmbt.qos.control.connection")
    /// Serializes commands: suspended while a command is in flight, resumed when it completes.
    private let commandsQueue = DispatchQueue(label: "at.rmbt.qos.control.commands")

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var timeoutWorkItem: DispatchWorkItem?

    private var currentCommand: String?
    private var currentCommandSuccess: RMBTSuccessBlock?
    private var currentCommandError: RMBTErrorBlock?
    private var currentReadReply = false

    private var state: RMBTQoSControlConnectionState = .disconnected

    private static let receiveChunkSize = 65536

    init(with params: RMBTQoSControlConnectionParams, token: String) {
        self.token = token
        self.params = params
    }

    // MARK: - Public API

    func sendCommand(_ line: String, readReply: Bool, success: @escaping RMBTSuccessBlock, error: @escaping RMBTErrorBlock) {
        commandsQueue.async { [weak self] in
            guard let self = self else { return }
            // Block the next command until this one completes (resumed in `done`).
            self.commandsQueue.suspend()

            self.connectionQueue.async {
                self.currentCommand = line
                self.currentReadReply = readReply
                self.currentCommandSuccess = success
                self.currentCommandError = error

                if self.state == .disconnected {
                    self.connect()
                } else {
                    // Connection is already authenticated: reuse it.
                    self.transmit()
                }
            }
        }
    }

    func close() {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            self.state = .disconnecting
            self.teardownConnection()
            self.state = .disconnected
            // Unblock any caller still waiting on an in-flight command.
            self.failCurrentCommand(with: RMBTQoSControlConnectionError.connectionClosed)
        }
    }

    // MARK: - Connection lifecycle (connectionQueue)

    private func connect() {
        state = .connecting
        receiveBuffer.removeAll(keepingCapacity: true)

        guard let port = NWEndpoint.Port(rawValue: UInt16(params.port)) else {
            abort(with: RMBTQoSControlConnectionError.invalidEndpoint)
            return
        }
        let host = NWEndpoint.Host(params.serverAddress)

        let tlsOptions = NWProtocolTLS.Options()
        let securityOptions = tlsOptions.securityProtocolOptions
        // Allow TLS 1.2 through TLS 1.3 (the default maximum), fixing the SecureTransport 1.2 ceiling.
        sec_protocol_options_set_min_tls_protocol_version(securityOptions, .TLSv12)
        // Preserve the legacy behaviour of accepting the QoS server certificate without validation.
        sec_protocol_options_set_verify_block(securityOptions, { _, _, complete in
            complete(true)
        }, connectionQueue)

        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: host, port: port, using: parameters)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] newState in
            self?.handleConnectionState(newState)
        }

        startTimeout()
        connection.start(queue: connectionQueue)
    }

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            // TCP + TLS handshake complete.
            state = .authenticating
            startAuthentication()
        case .failed(let error):
            Log.logger.error("QoS control connection failed: \(error)")
            abort(with: error)
        case .waiting(let error):
            // Network.framework keeps retrying; our per-step timeout bounds the wait.
            Log.logger.debug("QoS control connection waiting: \(error)")
        case .cancelled:
            state = .disconnected
            // Reached only for cancellations not initiated by `teardownConnection`
            // (which detaches this handler first); make sure no caller is left waiting.
            failCurrentCommand(with: RMBTQoSControlConnectionError.connectionClosed)
        default:
            break
        }
    }

    private func teardownConnection() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll(keepingCapacity: true)
    }

    private func abort(with error: Error) {
        teardownConnection()
        state = .disconnected
        failCurrentCommand(with: error)
    }

    // MARK: - Authentication handshake (connectionQueue)

    private func startAuthentication() {
        // Sequence mirrors the original protocol: greeting, accept, TOKEN, token-reply, accept.
        readLineOrFail { conn, _ in
            conn.readLineOrFail { conn, _ in
                conn.writeLineOrFail("TOKEN \(conn.token)") { conn in
                    conn.readLineOrFail { conn, _ in
                        conn.readLineOrFail { conn, _ in
                            conn.state = .authenticated
                            conn.transmit()
                        }
                    }
                }
            }
        }
    }

    private func transmit() {
        guard let command = currentCommand else { return }
        let readReply = currentReadReply

        writeLineOrFail(command) { conn in
            if readReply {
                conn.readLineOrFail { conn, line in
                    conn.done(with: line, error: nil)
                }
            } else {
                conn.done(with: nil, error: nil)
            }
        }
    }

    private func done(with result: String?, error: Error?) {
        cancelTimeout()
        guard currentCommand != nil else { return }

        let success = currentCommandSuccess
        let failure = currentCommandError
        currentCommandSuccess = nil
        currentCommandError = nil
        currentCommand = nil

        if let error = error {
            failure?(error, nil)
        } else {
            success?(result)
        }

        commandsQueue.resume()
    }

    private func failCurrentCommand(with error: Error) {
        guard currentCommand != nil else { return }
        done(with: nil, error: error)
    }

    // MARK: - Line I/O (connectionQueue)

    /// Reads a single `\n`-terminated line (delimiter included, matching the previous
    /// `GCDAsyncSocket.readData(to:)` semantics) or fails the current command.
    private func readLineOrFail(_ completion: @escaping (_ connection: RMBTQoSControlConnection, _ line: String) -> Void) {
        startTimeout()
        readLine { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let line):
                completion(self, line)
            case .failure(let error):
                self.abort(with: error)
            }
        }
    }

    private func writeLineOrFail(_ line: String, _ completion: @escaping (_ connection: RMBTQoSControlConnection) -> Void) {
        startTimeout()
        writeLine(line) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.abort(with: error)
            } else {
                completion(self)
            }
        }
    }

    private func readLine(completion: @escaping (Result<String, Error>) -> Void) {
        if let line = extractLine() {
            completion(.success(line))
            return
        }
        guard let connection = connection else {
            completion(.failure(RMBTQoSControlConnectionError.connectionClosed))
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.receiveChunkSize) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            if let data = data, !data.isEmpty {
                self.receiveBuffer.append(data)
            }
            if let line = self.extractLine() {
                completion(.success(line))
            } else if isComplete {
                completion(.failure(RMBTQoSControlConnectionError.connectionClosed))
            } else {
                self.readLine(completion: completion)
            }
        }
    }

    private func writeLine(_ line: String, completion: @escaping (Error?) -> Void) {
        guard let connection = connection else {
            completion(RMBTQoSControlConnectionError.connectionClosed)
            return
        }
        guard let data = (line + "\n").data(using: .ascii) else {
            completion(RMBTQoSControlConnectionError.encodingFailed)
            return
        }
        connection.send(content: data, completion: .contentProcessed { error in
            completion(error)
        })
    }

    /// Extracts the first `\n`-terminated line from the receive buffer, delimiter included.
    private func extractLine() -> String? {
        guard let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) else { return nil }
        let endIndex = receiveBuffer.index(after: newlineIndex)
        let lineData = receiveBuffer.subdata(in: receiveBuffer.startIndex..<endIndex)
        receiveBuffer.removeSubrange(receiveBuffer.startIndex..<endIndex)
        return String(data: lineData, encoding: .ascii)
    }

    // MARK: - Timeout (connectionQueue)

    private func startTimeout() {
        cancelTimeout()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Log.logger.error("QoS control connection timed out")
            self.abort(with: RMBTQoSControlConnectionError.timeout)
        }
        timeoutWorkItem = item
        connectionQueue.asyncAfter(deadline: .now() + RMBTConfig.RMBT_QOS_CC_TIMEOUT_S, execute: item)
    }

    private func cancelTimeout() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }
}
