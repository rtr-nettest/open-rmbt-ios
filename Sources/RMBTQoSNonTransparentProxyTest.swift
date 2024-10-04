//
//  RMBTQoSNonTransparentProxyTest.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 11.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import CocoaAsyncSocket

class RMBTQoSNonTransparentProxyTest: RMBTQoSCCTest, @unchecked Sendable {
    
    private var request: String?
    private var _result: String?
    private var port: UInt = 0
    private var sem = DispatchSemaphore(value: 0)
    
    override init?(with params: [String : Any]) {
        super.init(with: params)
        if let port = params["port"] as? String,
           let intPort = UInt(port) {
            self.port = intPort
        } else {
            assert(false, "Can't parse port")
        }
        request = params["request"] as? String
    }
    
    override var result: [String: Any] {
        return [
            "nontransproxy_objective_request": request ?? "",
            "nontransproxy_objective_port": port,
            "nontransproxy_objective_timeout": self.timeoutNanos,
            "nontransproxy_result_response": RMBTValueOrNull(_result),
            "nontransproxy_result": self.statusName() ?? ""
        ]
    }
    
    override func main() {
        assert(self.status == .unknown)
        assert(_result == nil)

        let response: String
        do {
            let cmd = String(format: "NTPTEST %lu", port)
            response = try self.send(command: cmd, readReply: true)
        }
        catch let error {
            Log.logger.debug("\(self) failed: \(error)")
            self.status = .error
            return
        }
        
        Log.logger.debug("Receive \(response)")

        if (!response.hasPrefix("OK")) {
            Log.logger.debug("\(self) failed: \(response)")
            self.status = .error
            return
        }
        
        
        let delegateQueue = DispatchQueue(label: "at.rmbt.qos.ntp.delegate")
        
        let socket = GCDAsyncSocket(delegate: self, delegateQueue: delegateQueue)
        
        do {
            try socket.connect(toHost: self.controlConnectionParams?.serverAddress ?? "", onPort: UInt16(port), withTimeout: Double(self.timeoutSeconds()))
        }
        catch let error {
            Log.logger.debug("\(self) error connecting to \(String(describing: self.controlConnectionParams?.serverAddress)): \(error)")
            self.status = .error
            return
        }
        
        let result = sem.wait(timeout: .now() + Double(self.timeoutNanos))
        if result == .timedOut {
            Log.logger.debug("\(self) timed out")
            self.status = .timeout
        } else {
            if (_result != nil) {
                self.status = .ok
            } else {
                self.status = .error
            }
        }
        
        socket.disconnect()
    }
    
    override var description: String {
        return String(format: "RMBTQoSNonTransparentProxyTest (uid=%@, cg=%lu, server=%@, request=%@, port=%lu)",
        self.uid,
        self.concurrencyGroup,
        self.controlConnectionParams ?? "",
        request ?? "",
        port
        )
    }
}

extension RMBTQoSNonTransparentProxyTest: GCDAsyncSocketDelegate {
    func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        sem.signal()
    }
    
    func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        sock.write(request?.appending("\n").data(using: .ascii), withTimeout: Double(self.timeoutSeconds()), tag: 0)
    }

    func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        sock.readData(to: "\n".data(using: .ascii), withTimeout: Double(self.timeoutSeconds()), tag: 1)
    }

    func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        let line = String(data: data, encoding: .ascii) ?? ""
        _result = RMBTHelpers.RMBTChomp(line)
        sem.signal()
    }
    
}
