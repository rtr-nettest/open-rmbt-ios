//
//  RMBTQoSUDPTest.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 10.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import CocoaAsyncSocket

enum RMBTQoSUDPPacketTag: Int {
    case outgoing = 0
    case incomingResponse
}

enum RMBTQoSUDPTestPacketFlag: Int {
    case oneDirection = 1
    case response = 2
    case awaitResponse = 3
}

class RMBTQoSUDPTest: RMBTQoSIPTest, @unchecked Sendable {
    static let kDefaultDelayNanos: Int64 = Int64(300 * NSEC_PER_MSEC)
    
    private var outPacketCount: UInt = 0
    private var inPacketCount: UInt = 0
    
    private var delayNanos: UInt64 = 0
    
    private var delayLastPacketSentAt: UInt64 = 0

    private var delayElapsedSem: DispatchSemaphore?
    
    private var receivedPacketSeqs: Set<UInt8> = []
    
    private var receivedServerCount: UInt = 0
    
    private var stopReceivingSem: DispatchSemaphore?
    
    override init?(with params: [String : Any]) {
        super.init(with: params)
        
        if let count = params["out_num_packets"] as? String,
           let intCount = UInt(count) {
            outPacketCount = intCount
        } else if let count = params["in_num_packets"] as? String,
           let intCount = UInt(count) {
            inPacketCount = intCount
        } else {
            assert(false, "Can't parse num packets")
        }

        let delayStr = String(format: "%@", params["delay"] != nil ? (params["delay"] as? NSNumber ?? NSNumber(value: RMBTQoSUDPTest.kDefaultDelayNanos)) : NSNumber(value: RMBTQoSUDPTest.kDefaultDelayNanos))
        
        delayNanos = strtoull(delayStr, nil, 10)

        if (outPacketCount > 0 && inPacketCount == 0) {
            self.direction = .out
        } else if (inPacketCount > 0 && outPacketCount == 0) {
            self.direction = .in
        }
    }
    
    override func ipMain(_ isOutgoing: Bool) {
        let port = isOutgoing ? self.outPort : self.inPort

        let packetCount = isOutgoing ? outPacketCount : inPacketCount

        receivedPacketSeqs = []

        let cmd = String(format:"UDPTEST %@ %lu %lu +ID%@", isOutgoing ? "OUT" : "IN",
                         port,
                         packetCount,
                         self.uid )
                         
        let response1: String
        
        do {
            response1 = try self.send(command: cmd, readReply: isOutgoing ? true : false)
        }
        catch let error {
            Log.logger.error("\(self) failed: \(error)")
            self.status = .error
            return
        }
        
        if isOutgoing && !response1.hasPrefix("OK") {
            Log.logger.error("\(self) failed: \(response1)")
            self.status = .error
            return
        }

        let delegateQueue = DispatchQueue(label: "at.rmbt.qos.udp.delegate")
        
        let udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: delegateQueue)
        
        do {
            if (isOutgoing) {
                try udpSocket.connect(toHost: self.controlConnectionParams?.serverAddress ?? "", onPort: UInt16(self.outPort))
            } else {
                try udpSocket.bind(toPort: UInt16(self.inPort))
            }
        }
        catch let error {
            Log.logger.error("\(self) error connecting/binding: \(error)")
            self.status = .error
            return
        }

        stopReceivingSem = DispatchSemaphore(value: 0)
        let stopReceivingSemTimeout = DispatchTime.now() + Double(self.timeoutSeconds())
        
        do {
            try udpSocket.beginReceiving()
        }
        catch let error {
            Log.logger.error("\(self) error beginReceiving: \(error)")
            self.status = .error
            return
        }

        if (isOutgoing) {
            delayElapsedSem = DispatchSemaphore(value: 0)

            for i in 0..<packetCount {
                delayLastPacketSentAt = RMBTHelpers.RMBTCurrentNanos()
                udpSocket.send(dataForOutgoingPacket(with: .awaitResponse, seq: Int8(i)), withTimeout: Double(self.timeoutNanos), tag: RMBTQoSUDPPacketTag.outgoing.rawValue)
                
                let result = delayElapsedSem?.wait(timeout: .now() + Double(self.timeoutSeconds()))
                if result == .timedOut {
                    Log.logger.error("\(self) timed out waiting for send delay!")
                    self.status = .timeout
                    break
                }
            }
        }

        let result = stopReceivingSem?.wait(timeout: stopReceivingSemTimeout)
        if result == .timedOut {
            Log.logger.error("\(self): receive timeout")
            self.status = .timeout
            return
        }
        
        udpSocket.closeAfterSending()

        let response2: String
        do {
            let cmd = String(format:"GET UDPRESULT %@ %lu +ID%@", isOutgoing ? "OUT" : "IN", port, self.uid)
            response2 = try self.send(command: cmd, readReply: true)
        }
        catch let error {
            Log.logger.error("\(self) error fetching udpresult: \(error)")
            self.status = .error
            return
        }

        if (!response2.hasPrefix("RCV")) {
            Log.logger.error("\(self) error fetching udpresult: \(response2)")
            self.status = .error
            return
        }

        let components = response2.components(separatedBy: " ")
        if components.count < 2 {
            Log.logger.error("\(self)couldn't parse RCV string: \(components)")
            self.status = .error
            return;
        } else {
            receivedServerCount = UInt(components[1]) ?? 0
        }

        if (self.status == .unknown) {
            self.status = .ok
        }
    }
    
    override var result: [String: Any] {
        var result: [String: Any] = [
            "udp_objective_delay": delayNanos,
            "udp_objective_timeout": self.timeoutNanos
        ]

        // Server doesn't parse UDP tests with "error"/"timeout" result as failed, relying on packet count comparison instead,
        // so let's send zeroes:
        //if (self.status == RMBTQoSTestStatusOk) {
        let isOutgoing = self.direction == .out
        let packetCount = isOutgoing ? outPacketCount : inPacketCount

        let receivedClientCount = receivedPacketSeqs.count
        let lostPackets = Int(packetCount) - receivedClientCount

        let plr = String(format: "%lu", RMBTHelpers.RMBTPercent(lostPackets, Int(packetCount)))

        if isOutgoing {
            result["udp_objective_out_port"] = self.outPort
            result["udp_objective_out_num_packets"] = packetCount
            result["udp_result_out_num_packets"] = receivedServerCount
            result["udp_result_out_response_num_packets"] = receivedClientCount
            result["udp_result_out_packet_loss_rate"] = plr
        } else {
            result["udp_objective_in_port"] = self.inPort
            result["udp_objective_in_num_packets"] = packetCount
            result["udp_result_in_num_packets"] = receivedClientCount
            result["udp_result_in_response_num_packets"] = receivedServerCount
            result["udp_result_in_packet_loss_rate"] = plr
        }
        //}

        return result;
    }
    
    override var description: String {
        return String(format:"RMBTQoSUDPTest (uid=%@, cg=%ld, server=%@, delay=%@, out=%@, in=%@)",
                self.uid,
                self.concurrencyGroup,
                self.controlConnectionParams ?? "",
                RMBTHelpers.RMBTSecondsString(with: Int64(delayNanos)),
                self.outPort > 0 ? String(format:"%ld/%ld", self.outPort, outPacketCount) : "-",
                self.inPort > 0 ? String(format:"%ld/%ld", self.inPort, inPacketCount) : "-"
        )
    }
    
    func dataForOutgoingPacket(with packetFlag: RMBTQoSUDPTestPacketFlag, seq: Int8) -> Data {
        var data = Data()
        
        // Flag (1 byte)
        var flag: UInt8 = UInt8(packetFlag.rawValue)
        data.append(&flag, count: 1)

        // Packet number (1 byte)
        var _seq: UInt8 = UInt8(seq)
        data.append(&_seq, count: 1)

        // UUID
        let uuidData = (self.uuidFromToken() ?? "").data(using: .ascii) ?? Data()
        assert(uuidData.count == 36)
        data.append(uuidData)

        // Timestamp
        let timestampData = String(RMBTHelpers.RMBTTimestamp(with: Date())).data(using: .ascii) ?? Data()
        data.append(timestampData)

        return data
    }

}

extension RMBTQoSUDPTest: GCDAsyncUdpSocketDelegate {
    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        var flag: UInt8 = 0
        (data as NSData).getBytes(&flag, length: MemoryLayout<UInt8>.size)

        var seq: UInt8 = 0
        (data as NSData).getBytes(&seq, range: NSRange(location: 1, length: 1))
        
        if receivedPacketSeqs.contains(seq) {
            Log.logger.error("\(self) received duplicate packet!")
            self.status = .error
            stopReceivingSem?.signal()
        } else {
            receivedPacketSeqs.insert(seq)
            if (self.direction == .in) {
                assert(flag == 3)
                
                sock.send(dataForOutgoingPacket(with: .response, seq: Int8(seq)), toAddress: address, withTimeout: TimeInterval(self.timeoutNanos), tag: RMBTQoSUDPPacketTag.incomingResponse.rawValue)
                
                if (receivedPacketSeqs.count == inPacketCount) {
                    // Allow for the last confirmation packet to reach the server:
                    sock.delegateQueue()?.asyncAfter(deadline: .now() + Double(delayNanos), execute: {
                        self.stopReceivingSem?.signal()
                    })
                }
            } else {
                assert(flag == 2)
                if receivedPacketSeqs.count == outPacketCount {
                    stopReceivingSem?.signal()
                }
            }
        }
    }
    
    func udpSocket(_ sock: GCDAsyncUdpSocket, didSendDataWithTag tag: Int) {
        if tag == RMBTQoSUDPPacketTag.outgoing.rawValue {
            let elapsed = RMBTHelpers.RMBTCurrentNanos() - delayLastPacketSentAt
            let delay = elapsed > delayNanos ? 0 : delayNanos - elapsed
            //RMBTLog(@"%@ waiting %ld ns for delay", self, delay);
            let signal: RMBTBlock = {
                self.delayElapsedSem?.signal()
            }
            if (delay > 0) {
                sock.delegateQueue()?.asyncAfter(deadline: .now() + Double(delay / NSEC_PER_SEC), execute: {
                    signal()
                })
            } else {
                signal()
            }
        }
    }
}
