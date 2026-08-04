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
/// A connected UDP endpoint only accepts replies from the address the client
/// sent to, i.e. it is strict on the server source address.
final class NWUDPConnection: UDPConnectable {
    private var connection: NWConnection?

    /// Send outcomes reported by Network.framework. Without these, a run of failed pings cannot be attributed:
    /// "the datagrams left the device and nothing came back" and "the datagrams never went out" look identical.
    /// Mutated from the connection's queue, so guarded.
    private let sendOutcomesLock = NSLock()
    private var acceptedDatagrams = 0
    private var rejectedDatagrams = 0
    private var isSendFailing = false

    private static let sendSummaryInterval = 100

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

        // `.waiting` (e.g. no route yet) is not resumed here on purpose — the connection may still become ready.
        // The caller bounds this call instead, so the bridge must be cancellation-aware or that bound cannot work.
        let resumeOnce = OneShotContinuation<Void>()
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    resumeOnce.install(continuation)
                    guard !Task.isCancelled else {
                        resumeOnce.resume(throwing: CancellationError())
                        return
                    }
                    conn.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            conn.stateUpdateHandler = nil
                            Log.logger.info("NWUDPConnection: Ready over \(Self.describe(conn.currentPath))")
                            resumeOnce.resume(returning: ())
                        case .failed(let error):
                            conn.stateUpdateHandler = nil
                            resumeOnce.resume(throwing: error)
                        case .cancelled:
                            conn.stateUpdateHandler = nil
                            resumeOnce.resume(throwing: UDPConnectionError.connectionNotAvailable)
                        case .waiting(let error):
                            // `unsatisfiedReason` is what distinguishes "the user turned cellular off for this app"
                            // from "no service at all" — otherwise both look like an unexplained stall.
                            let reason = conn.currentPath?.unsatisfiedReason
                            Log.logger.info(
                                "NWUDPConnection: Connection waiting: \(error), unsatisfied reason: \(reason.map(String.init(describing:)) ?? "unknown")"
                            )
                        default:
                            break
                        }
                    }
                    conn.start(queue: .global())
                }
            } onCancel: {
                resumeOnce.resume(throwing: CancellationError())
                conn.cancel()
            }
        } catch {
            conn.stateUpdateHandler = nil
            conn.cancel()
            throw .connectionNotAvailable
        }

        connection = conn
    }

    func cancel() {
        connection?.cancel()
        connection = nil
    }

    /// Describes the interface a connection actually ended up on. The device-level network type says what iOS
    /// prefers overall; this says what this measurement is really using, which is the distinction #70 turned on.
    private static func describe(_ path: NWPath?) -> String {
        guard let path else { return "an unknown path" }

        var interfaces: [String] = []
        if path.usesInterfaceType(.cellular) { interfaces.append("cellular") }
        if path.usesInterfaceType(.wifi) { interfaces.append("wifi") }
        if path.usesInterfaceType(.wiredEthernet) { interfaces.append("ethernet") }
        if path.usesInterfaceType(.other) { interfaces.append("other/tunnel") }
        let interfaceDescription = interfaces.isEmpty ? "unknown interface" : interfaces.joined(separator: "+")

        var attributes: [String] = []
        if path.isExpensive { attributes.append("expensive") }
        if path.isConstrained { attributes.append("constrained") }
        let attributeDescription = attributes.isEmpty ? "" : " (\(attributes.joined(separator: ", ")))"

        return "\(interfaceDescription)\(attributeDescription), local endpoint \(path.localEndpoint?.debugDescription ?? "unknown")"
    }

    func send(data: Data) throws {
        guard let connection else {
            throw UDPConnectionError.connectionNotAvailable
        }
        // `.contentProcessed` rather than `.idempotent`: the completion is the only evidence that a datagram was
        // actually handed to the network stack. It cannot be surfaced as a `throw` (it arrives asynchronously,
        // after this call returned), so it is reported to the log instead.
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            self?.recordSendOutcome(error: error)
        })
    }

    private func recordSendOutcome(error: NWError?) {
        enum Outcome {
            case startedFailing(NWError)
            case recovered
            case summary(accepted: Int, rejected: Int)
        }

        var outcomes: [Outcome] = []
        sendOutcomesLock.lock()
        if let error {
            rejectedDatagrams += 1
            if !isSendFailing {
                isSendFailing = true
                outcomes.append(.startedFailing(error))
            }
        } else {
            acceptedDatagrams += 1
            if isSendFailing {
                isSendFailing = false
                outcomes.append(.recovered)
            }
        }
        if (acceptedDatagrams + rejectedDatagrams) % Self.sendSummaryInterval == 0 {
            outcomes.append(.summary(accepted: acceptedDatagrams, rejected: rejectedDatagrams))
        }
        sendOutcomesLock.unlock()

        // Only transitions and periodic totals are logged: at the 100 ms ping cadence, one line per datagram would
        // bury the field log it exists to make readable.
        for outcome in outcomes {
            switch outcome {
            case .startedFailing(let error):
                Log.logger.warning("NWUDPConnection: Datagrams are no longer leaving the device: \(error)")
            case .recovered:
                Log.logger.info("NWUDPConnection: Datagrams are leaving the device again")
            case .summary(let accepted, let rejected):
                Log.logger.info("NWUDPConnection: \(accepted) datagram(s) accepted by the network stack, \(rejected) rejected")
            }
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
                    continuation.resume(returning: data ?? Data())
                }
            }
        }
    }
}
