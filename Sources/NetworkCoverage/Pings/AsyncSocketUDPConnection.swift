//
//  AsyncSocketUDPConnection.swift
//  RMBT
//
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation
import CocoaAsyncSocket

/// Unconnected UDP transport using `GCDAsyncUdpSocket`.
///
/// This is the default transport for Network Coverage pings. It binds to an
/// ephemeral local port and sends each datagram with an explicit destination,
/// so replies from any server source address are accepted. This fixes IPv6
/// scenarios where the server responds from a different address than the one
/// the client originally targeted.
///
/// All mutable state is confined to `delegateQueue`. The class is marked
/// `@unchecked Sendable` because Swift concurrency cannot verify serial-queue
/// isolation.
final class AsyncSocketUDPConnection: NSObject, UDPConnectable, @unchecked Sendable {
    private let delegateQueue = DispatchQueue(label: "at.rmbt.coverage.udp.delegate")

    private var socket: GCDAsyncUdpSocket?
    private var host: String?
    private var port: UInt16?
    private var ipVersion: IPVersion?

    private var pendingReceive: CheckedContinuation<Data, any Error>?
    private var receivedDataQueue: [Data] = []
    /// Permanent error — set only by `cancel()` or when reconnect fails.
    /// Poisons all subsequent send/receive calls until `start()` is called again.
    private var transportError: (any Error)?
    /// Transient error from a single failed send (e.g. DNS resolution failure).
    /// Delivered to the next `receive()` call, then cleared. Does NOT block
    /// future sends — the socket is still alive.
    private var transientSendError: (any Error)?

    // MARK: - UDPConnectable

    func start(host: String, port: String, ipVersion: IPVersion?) async throws(UDPConnectionError) {
        guard let portNumber = UInt16(port) else {
            throw .invalidHostOrPort
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                delegateQueue.async { [self] in
                    // Tear down any previous socket. Setting delegate to nil
                    // before close prevents stale callbacks from the old socket
                    // arriving after the new one is installed.
                    socket?.setDelegate(nil)
                    socket?.close()
                    socket = nil

                    self.host = host
                    self.port = portNumber
                    self.ipVersion = ipVersion
                    transportError = nil
                    transientSendError = nil
                    receivedDataQueue.removeAll()

                    guard let sock = createAndBindSocket() else {
                        continuation.resume(throwing: UDPConnectionError.connectionNotAvailable)
                        return
                    }

                    socket = sock
                    Log.logger.info("Bound to local port \(sock.localPort()), destination \(host):\(portNumber), ipVersion: \(ipVersion?.description ?? "any")")
                    continuation.resume()
                }
            }
        } catch {
            throw .connectionNotAvailable
        }
    }

    func cancel() {
        // Synchronous dispatch ensures cancel takes effect before the caller
        // proceeds, avoiding race windows with subsequent send/receive calls.
        // Safe to call from any queue except delegateQueue.
        delegateQueue.async { [self] in
            Log.logger.info("Cancelling transport to \(host ?? "nil"):\(port.map(String.init) ?? "nil")")
            socket?.setDelegate(nil)
            socket?.close()
            socket = nil
            // Nil host/port/ipVersion to prevent auto-reconnect — cancel is
            // an intentional shutdown, not a recoverable failure.
            host = nil
            port = nil
            ipVersion = nil
            transportError = UDPConnectionError.connectionNotAvailable

            if let pending = pendingReceive {
                pendingReceive = nil
                pending.resume(throwing: UDPConnectionError.connectionNotAvailable)
            }
        }
    }

    func send(data: Data) throws {
        // Must not be called from delegateQueue — sync dispatch would deadlock.
        dispatchPrecondition(condition: .notOnQueue(delegateQueue))

        var sendError: (any Error)?
        delegateQueue.sync { [self] in
            guard let host, let port else {
                sendError = UDPConnectionError.connectionNotAvailable
                return
            }
            if let transportError {
                sendError = transportError
                return
            }
            // Auto-reconnect if the socket was closed by the OS (e.g. flight
            // mode). bind+beginReceiving are local operations that succeed even
            // offline; actual delivery is validated asynchronously via delegates.
            if socket == nil, !reconnectIfNeeded() {
                sendError = transportError ?? UDPConnectionError.connectionNotAvailable
                return
            }
            // Note: transientSendError is NOT checked here. A previous per-send
            // failure (e.g. DNS) must not block future sends — the socket is
            // still alive and the next send may target a different/resolved host.
            socket?.send(data, toHost: host, port: port, withTimeout: -1, tag: 0)
        }
        if let sendError { throw sendError }
    }

    func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            delegateQueue.async { [self] in
                if let error = transportError {
                    continuation.resume(throwing: error)
                    return
                }
                if let error = transientSendError {
                    transientSendError = nil
                    continuation.resume(throwing: error)
                    return
                }
                if !receivedDataQueue.isEmpty {
                    let data = receivedDataQueue.removeFirst()
                    continuation.resume(returning: data)
                    return
                }
                pendingReceive = continuation
            }
        }
    }

    // MARK: - Socket creation

    /// Creates, configures, binds and starts receiving on a new socket.
    /// Must be called on `delegateQueue`. Returns `nil` on failure.
    private func createAndBindSocket() -> GCDAsyncUdpSocket? {
        let sock = GCDAsyncUdpSocket(delegate: self, delegateQueue: delegateQueue)
        do {
            switch ipVersion {
            case .IPv4:
                sock.setIPv4Enabled(true)
                sock.setIPv6Enabled(false)
            case .IPv6:
                sock.setIPv4Enabled(false)
                sock.setIPv6Enabled(true)
            case nil:
                sock.setIPv4Enabled(true)
                sock.setIPv6Enabled(true)
            }
            try sock.bind(toPort: 0)
            try sock.beginReceiving()
            return sock
        } catch {
            sock.close()
            return nil
        }
    }

    // MARK: - Auto-reconnect

    /// Creates a fresh socket with the same host/port/ipVersion after the
    /// previous one was closed by the OS. Must be called on `delegateQueue`.
    /// Returns `true` if the socket is now usable. Does NOT set
    /// `transportError` on failure — the next `send()` will retry.
    @discardableResult
    private func reconnectIfNeeded() -> Bool {
        guard socket == nil, let host, let port else { return socket != nil }

        guard let sock = createAndBindSocket() else {
            Log.logger.warning("Reconnect to \(host):\(port) failed, will retry on next send")
            return false
        }

        socket = sock
        transportError = nil
        transientSendError = nil
        Log.logger.info("Reconnected, bound to local port \(sock.localPort()), destination \(host):\(port), ipVersion: \(ipVersion?.description ?? "any")")
        return true
    }
}

// MARK: - GCDAsyncUdpSocketDelegate

extension AsyncSocketUDPConnection: GCDAsyncUdpSocketDelegate {
    func udpSocket(
        _ sock: GCDAsyncUdpSocket,
        didReceive data: Data,
        fromAddress address: Data,
        withFilterContext filterContext: Any?
    ) {
        guard sock === socket else { return }

        // Accept replies from any source address — response matching is done
        // at the protocol layer in UDPPingSession.
        if let pending = pendingReceive {
            pendingReceive = nil
            pending.resume(returning: data)
        } else {
            receivedDataQueue.append(data)
        }
    }

    func udpSocket(_ sock: GCDAsyncUdpSocket, didNotSendDataWithTag tag: Int, dueToError error: (any Error)?) {
        guard sock === socket else { return }

        let resolvedError = error ?? UDPConnectionError.connectionNotAvailable
        Log.logger.warning("didNotSendData error: \(resolvedError)")

        // Transient: deliver to the pending receive if one exists, otherwise
        // buffer for the next receive() call. Do NOT set transportError — the
        // socket is still alive and future sends should be allowed.
        if let pending = pendingReceive {
            pendingReceive = nil
            pending.resume(throwing: resolvedError)
        } else {
            transientSendError = resolvedError
        }
    }

    func udpSocketDidClose(_ sock: GCDAsyncUdpSocket, withError error: (any Error)?) {
        guard sock === socket else { return }

        let closeError = error ?? UDPConnectionError.connectionNotAvailable
        Log.logger.warning("Socket closed, error: \(closeError). Will auto-reconnect on next send.")

        // Discard the dead socket but keep host/port/ipVersion so the next
        // send() can transparently create a fresh socket (auto-reconnect).
        // Do NOT set transportError — the connection is recoverable.
        socket?.setDelegate(nil)
        socket = nil
        receivedDataQueue.removeAll()
        transientSendError = nil

        if let pending = pendingReceive {
            pendingReceive = nil
            pending.resume(throwing: closeError)
        }
    }
}
