//
//  RMBTTestConnection.swift
//  RMBT
//
//  Copyright © 2026 appscape gmbh. All rights reserved.
//

import Foundation
import Network

/// Delegate callbacks for `RMBTTestConnection`. All callbacks are delivered on the `delegateQueue` supplied at init,
/// mirroring the threading contract `RMBTTestWorker` previously relied on with `GCDAsyncSocket`.
protocol RMBTTestConnectionDelegate: AnyObject {
    /// TCP (and, when requested, TLS) handshake completed. `negotiatedEncryption` is nil for plaintext connections.
    func testConnectionDidBecomeReady(_ connection: RMBTTestConnection, localIp: String?, serverIp: String?, negotiatedEncryption: String?)
    /// Delivers the bytes for a `read(toDelimiter:…)` (delimiter included) or `readAvailable(…)` request.
    func testConnection(_ connection: RMBTTestConnection, didRead data: Data, tag: Int)
    /// A `write(_:tag:)` completed (data handed to the transport).
    func testConnection(_ connection: RMBTTestConnection, didWriteTag tag: Int)
    /// The connection closed: `error == nil` for a clean/intentional close, non-nil for a failure or timeout.
    func testConnection(_ connection: RMBTTestConnection, didDisconnectWithError error: Error?)
}

enum RMBTTestConnectionError: LocalizedError {
    case timeout
    case closed
    case invalidEndpoint

    var errorDescription: String? {
        switch self {
        case .timeout:         return "Measurement connection timed out"
        case .closed:          return "Measurement connection was closed"
        case .invalidEndpoint: return "Measurement server endpoint is invalid"
        }
    }
}

/// TLS-capable byte-stream connection to the measurement (test) server, backed by `NWConnection`.
///
/// This replaces `GCDAsyncSocket` for the speed-test worker. `GCDAsyncSocket` secures its socket with the deprecated
/// SecureTransport stack, which caps at TLS 1.2, so TLS 1.3-only servers rejected the handshake with
/// `errSSLPeerProtocolVersion` (-9836) and the test failed. `NWConnection` negotiates TLS 1.2 **and** 1.3 (the same
/// fix already applied to `RMBTQoSControlConnection`).
///
/// It reproduces the subset of `GCDAsyncSocket` semantics the worker uses:
///  * tagged writes with a completion callback,
///  * read-until-delimiter (delimiter included) and read-whatever-is-available, one outstanding read at a time,
///  * per-operation timeouts,
///  * "accept any certificate" trust evaluation (the legacy behaviour), and
///  * an explicit, intentional `disconnect()` that reports a clean (nil-error) close.
final class RMBTTestConnection: @unchecked Sendable {

    weak var delegate: RMBTTestConnectionDelegate?

    /// All `NWConnection` I/O and internal state run on this private serial queue (one per connection, so parallel
    /// test threads stay parallel). Delegate callbacks are hopped onto `delegateQueue`.
    private let ioQueue = DispatchQueue(label: "at.rmbt.test.connection")
    private let delegateQueue: DispatchQueue

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var encryption = false

    private(set) var isConnected = false
    private var didBecomeReady = false
    private var intentionalDisconnect = false
    private var didDeliverDisconnect = false

    private enum PendingRead {
        case none
        case delimiter(Data, Int)
        case available(Int)
    }
    private var pendingRead: PendingRead = .none

    private var connectTimeout: DispatchWorkItem?
    private var readTimeout: DispatchWorkItem?
    private var writeTimeout: DispatchWorkItem?

    /// Upper bound per receive; `minimumIncompleteLength: 1` means a receive returns as soon as any bytes are
    /// available, so this only caps how much a single callback can carry (kept large to favour download throughput).
    private static let receiveMaxLength = 1 << 20

    init(delegate: RMBTTestConnectionDelegate, delegateQueue: DispatchQueue) {
        self.delegate = delegate
        self.delegateQueue = delegateQueue
    }

    // MARK: - Public API (safe to call from any queue; each hops onto ioQueue)

    func connect(host: String, port: UInt16, encryption: Bool, timeout: TimeInterval) {
        ioQueue.async { [weak self] in
            self?.performConnect(host: host, port: port, encryption: encryption, timeout: timeout)
        }
    }

    func read(toDelimiter delimiter: Data, tag: Int, timeout: TimeInterval) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            self.pendingRead = .delimiter(delimiter, tag)
            self.startReadTimeout(timeout)
            self.serviceRead()
        }
    }

    func readAvailable(tag: Int, timeout: TimeInterval) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            self.pendingRead = .available(tag)
            self.startReadTimeout(timeout)
            self.serviceRead()
        }
    }

    func write(_ data: Data, tag: Int, timeout: TimeInterval) {
        ioQueue.async { [weak self] in
            self?.performWrite(data, tag: tag, timeout: timeout)
        }
    }

    func disconnect() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            self.intentionalDisconnect = true
            self.teardown()
            self.deliverDisconnect(error: nil)
        }
    }

    // MARK: - Connection lifecycle (ioQueue)

    private func performConnect(host: String, port: UInt16, encryption: Bool, timeout: TimeInterval) {
        // Reset all per-connection state: the worker reuses a single RMBTTestConnection instance for the download
        // phase and then again for the upload phase, so a stale `didBecomeReady`/`didDeliverDisconnect` from the
        // previous connection must not leak into this one — otherwise the `.ready` callback is guarded out and the
        // (re)connect hangs until it times out.
        teardown()
        didBecomeReady = false
        intentionalDisconnect = false
        didDeliverDisconnect = false
        pendingRead = .none
        self.encryption = encryption
        receiveBuffer.removeAll(keepingCapacity: true)

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            deliverDisconnect(error: RMBTTestConnectionError.invalidEndpoint)
            return
        }

        let parameters: NWParameters
        if encryption {
            let tlsOptions = NWProtocolTLS.Options()
            let securityOptions = tlsOptions.securityProtocolOptions
            // Allow TLS 1.2 through TLS 1.3 (default maximum) — the whole point of this migration.
            sec_protocol_options_set_min_tls_protocol_version(securityOptions, .TLSv12)
            // Preserve the legacy behaviour of accepting the measurement server certificate without validation.
            sec_protocol_options_set_verify_block(securityOptions, { _, _, complete in
                complete(true)
            }, ioQueue)
            parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        } else {
            parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] newState in
            self?.handleConnectionState(newState)
        }
        startConnectTimeout(timeout)
        connection.start(queue: ioQueue)
    }

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            guard !didBecomeReady else { return }
            didBecomeReady = true
            isConnected = true
            cancelConnectTimeout()
            let (localIp, serverIp) = endpointIPs()
            let negotiated = encryption ? negotiatedEncryptionString() : nil
            deliver { $0.testConnectionDidBecomeReady(self, localIp: localIp, serverIp: serverIp, negotiatedEncryption: negotiated) }
        case .failed(let error):
            isConnected = false
            deliverDisconnect(error: error)
        case .waiting(let error):
            // Network.framework keeps retrying transient failures; the connect timeout bounds the wait.
            Log.logger.debug("RMBTTestConnection waiting: \(error)")
        case .cancelled:
            isConnected = false
            if !intentionalDisconnect {
                deliverDisconnect(error: RMBTTestConnectionError.closed)
            }
        default:
            break
        }
    }

    private func teardown() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        isConnected = false
        cancelAllTimeouts()
    }

    // MARK: - Reading (ioQueue)

    private func serviceRead() {
        if satisfyPendingReadFromBuffer() { return }
        guard let connection = connection else {
            deliverDisconnect(error: RMBTTestConnectionError.closed)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.receiveMaxLength) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                self.deliverDisconnect(error: error)
                return
            }
            if let data = data, !data.isEmpty {
                self.receiveBuffer.append(data)
            }
            if self.satisfyPendingReadFromBuffer() { return }
            if isComplete {
                self.deliverDisconnect(error: RMBTTestConnectionError.closed)
                return
            }
            self.serviceRead()
        }
    }

    /// Tries to fulfil the pending read from the buffered bytes. Returns true when there was nothing to do or the
    /// read was fulfilled; false when more bytes are needed.
    private func satisfyPendingReadFromBuffer() -> Bool {
        switch pendingRead {
        case .none:
            return true
        case .delimiter(let delimiter, let tag):
            guard let range = receiveBuffer.range(of: delimiter) else { return false }
            let end = range.upperBound
            let out = receiveBuffer.subdata(in: receiveBuffer.startIndex..<end)
            receiveBuffer.removeSubrange(receiveBuffer.startIndex..<end)
            pendingRead = .none
            cancelReadTimeout()
            deliver { $0.testConnection(self, didRead: out, tag: tag) }
            return true
        case .available(let tag):
            guard !receiveBuffer.isEmpty else { return false }
            let out = receiveBuffer
            receiveBuffer.removeAll(keepingCapacity: true)
            pendingRead = .none
            cancelReadTimeout()
            deliver { $0.testConnection(self, didRead: out, tag: tag) }
            return true
        }
    }

    // MARK: - Writing (ioQueue)

    private func performWrite(_ data: Data, tag: Int, timeout: TimeInterval) {
        guard let connection = connection else {
            deliverDisconnect(error: RMBTTestConnectionError.closed)
            return
        }
        startWriteTimeout(timeout)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            self.cancelWriteTimeout()
            if let error = error {
                self.deliverDisconnect(error: error)
                return
            }
            self.deliver { $0.testConnection(self, didWriteTag: tag) }
        })
    }

    // MARK: - Delivery helpers (ioQueue -> delegateQueue)

    private func deliver(_ body: @escaping (RMBTTestConnectionDelegate) -> Void) {
        delegateQueue.async { [weak self] in
            guard let self = self, let delegate = self.delegate else { return }
            body(delegate)
        }
    }

    private func deliverDisconnect(error: Error?) {
        if didDeliverDisconnect { return }
        didDeliverDisconnect = true
        cancelAllTimeouts()
        isConnected = false
        deliver { $0.testConnection(self, didDisconnectWithError: error) }
    }

    // MARK: - Endpoint / TLS introspection (ioQueue)

    private func endpointIPs() -> (String?, String?) {
        guard let path = connection?.currentPath else { return (nil, nil) }
        return (host(from: path.localEndpoint), host(from: path.remoteEndpoint))
    }

    private func host(from endpoint: NWEndpoint?) -> String? {
        guard let endpoint = endpoint else { return nil }
        if case let .hostPort(host, _) = endpoint {
            switch host {
            case .ipv4(let address): return "\(address)"
            case .ipv6(let address): return "\(address)"
            case .name(let name, _): return name
            @unknown default:        return "\(host)"
            }
        }
        return "\(endpoint)"
    }

    private func negotiatedEncryptionString() -> String? {
        guard let metadata = connection?.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            return nil
        }
        let secMetadata = metadata.securityProtocolMetadata
        let version = sec_protocol_metadata_get_negotiated_tls_protocol_version(secMetadata)
        let ciphersuite = sec_protocol_metadata_get_negotiated_tls_ciphersuite(secMetadata)
        return "\(Self.protocolName(version)) (\(String(format: "%X", ciphersuite.rawValue)))"
    }

    private static func protocolName(_ version: tls_protocol_version_t) -> String {
        switch version {
        case .TLSv10:  return "TLSv1"
        case .TLSv11:  return "TLSv1.1"
        case .TLSv12:  return "TLSv1.2"
        case .TLSv13:  return "TLSv1.3"
        case .DTLSv10: return "DTLSv1"
        case .DTLSv12: return "DTLSv1.2"
        @unknown default: return "TLS"
        }
    }

    // MARK: - Timeouts (ioQueue)

    private func startConnectTimeout(_ timeout: TimeInterval) {
        connectTimeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Log.logger.error("RMBTTestConnection: connect timed out after \(timeout)s")
            self.teardown()
            self.deliverDisconnect(error: RMBTTestConnectionError.timeout)
        }
        connectTimeout = item
        ioQueue.asyncAfter(deadline: .now() + timeout, execute: item)
    }

    private func startReadTimeout(_ timeout: TimeInterval) {
        readTimeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Log.logger.error("RMBTTestConnection: read timed out after \(timeout)s")
            self.teardown()
            self.deliverDisconnect(error: RMBTTestConnectionError.timeout)
        }
        readTimeout = item
        ioQueue.asyncAfter(deadline: .now() + timeout, execute: item)
    }

    private func startWriteTimeout(_ timeout: TimeInterval) {
        writeTimeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Log.logger.error("RMBTTestConnection: write timed out after \(timeout)s")
            self.teardown()
            self.deliverDisconnect(error: RMBTTestConnectionError.timeout)
        }
        writeTimeout = item
        ioQueue.asyncAfter(deadline: .now() + timeout, execute: item)
    }

    private func cancelConnectTimeout() { connectTimeout?.cancel(); connectTimeout = nil }
    private func cancelReadTimeout() { readTimeout?.cancel(); readTimeout = nil }
    private func cancelWriteTimeout() { writeTimeout?.cancel(); writeTimeout = nil }

    private func cancelAllTimeouts() {
        cancelConnectTimeout()
        cancelReadTimeout()
        cancelWriteTimeout()
    }
}
