//
//  RMBTQoSTCPTest.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 10.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import CocoaAsyncSocket

class RMBTQoSTCPTest: RMBTQoSIPTest, @unchecked Sendable {

    private var doneSem: DispatchSemaphore?
    private var response: String?
    
    override init?(with params: [String : Any]) {
        super.init(with: params)
            
        if (self.outPort > 0 && self.inPort == 0) {
            self.direction = .out
        } else if (self.inPort > 0 && self.outPort == 0) {
            self.direction = .in
        }
    }
    
    override var result: [String: Any] {
        var result: [String: Any] = ["tcp_objective_timeout": self.timeoutNanos]
        let outgoing = self.direction == .out

        if (outgoing) {
            result["tcp_result_out_response"] = RMBTValueOrNull(response)
            result["tcp_objective_out_port"] = self.outPort
            result["tcp_result_out"] = self.statusName()
        } else {
            result["tcp_result_in_response"] = RMBTValueOrNull(response)
            result["tcp_objective_in_port"] = self.inPort
            result["tcp_result_in"] = self.statusName()
        }

        return result
    }
    
    override func ipMain(_ isOutgoing: Bool) {
        let port = isOutgoing ? self.outPort : self.inPort

        let cmd = String(format: "TCPTEST %@ %lu +ID%@", isOutgoing ? "OUT" : "IN",
                         port,
                         self.uid)
        
        let response1: String
        do {
            response1 = try self.send(command: cmd, readReply: isOutgoing ? true : false)
        }
        catch let error {
            Log.logger.error("\(self) failed:\(error)")
            self.status = .error
            return
        }
        
        if (isOutgoing && !response1.hasPrefix("OK")) {
            Log.logger.error("\(self) failed:error/\(response1)")
            self.status = .error;
            return;
        }

        let delegateQueue = DispatchQueue(label: "at.rmbt.qos.tcp.delegate")
        let socket = GCDAsyncSocket(delegate: self, delegateQueue: delegateQueue)

        do {
            if (isOutgoing) {
                try socket.connect(toHost: self.controlConnectionParams?.serverAddress ?? "", onPort: UInt16(port), withTimeout: TimeInterval(self.timeoutSeconds()))
            } else {
                try socket.accept(onPort: UInt16(port))
            }
        }
        catch let error {
            Log.logger.error("\(self) error connecting/binding:\(error)")
            self.status = .error
            return
        }

        self.doneSem = DispatchSemaphore(value: 0)
        
        let result = self.doneSem?.wait(timeout: .now() + Double(self.timeoutNanos))
        if result == .timedOut {
            self.status = .timeout
        } else {
            self.status = .ok
        }
        
        socket.delegate = nil
        socket.disconnect()
    }
    
    override var description: String {
        return String(format: "RMBTQoSTCPTest (uid=%@, cg=%ld, server=%@, out_port=%ld, in_port=%ld)",
                      self.uid,
                      self.concurrencyGroup,
                      self.controlConnectionParams ?? "",
                      self.outPort,
                      self.inPort
        )
    }
}

extension RMBTQoSTCPTest: GCDAsyncSocketDelegate {
    func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        assert(self.direction == .out)
        sock.write("PING\n".data(using: .ascii), withTimeout: TimeInterval(self.timeoutSeconds()), tag: 0)
    }
    
    func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        newSocket.readData(to: "\n".data(using: .ascii), withTimeout: TimeInterval(self.timeoutSeconds()), tag: 0)
    }

    func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        doneSem?.signal()
    }

    func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        sock.readData(to: "\n".data(using: .ascii), withTimeout: TimeInterval(self.timeoutSeconds()), tag: 0)
    }
    
    func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        if let line = String(data: data, encoding: .ascii) {
            assert(tag == 0)
            response = RMBTHelpers.RMBTChomp(line)
        }
        sock.disconnect()
    }
}
