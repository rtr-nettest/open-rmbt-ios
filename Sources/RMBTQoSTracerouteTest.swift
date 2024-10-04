//
//  RMBTQoSTracerouteTest.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 10.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

@objc class RMBTQoSTracerouteTest: RMBTQoSTest, @unchecked Sendable {
    private let kDefaultMaxHops: UInt = 30
    private let kStartPort: UInt = 32768 + 666
    private let kTimeout: UInt64 = 2 // timeout for each try (-w)
    
    private var maxHops: UInt = 0
    private var host: String = ""
    private var _result: [[String: Any]]?
    
    private var masked = false
    private var timedOut = false
    private var maxHopsExceeded = false
    
    init?(with params: [String : Any], masked: Bool) {
        super.init(with: params)
        
        host = params["host"] as? String ?? ""
        maxHops = UInt((params["max_hops"] as? Int) ?? Int(kDefaultMaxHops))
        self.masked = masked
        progress = RMBTProgress(totalUnitCount: UInt64(maxHops))
    }
    
    override func main() {
        assert(!self.isCancelled)
        
        let startedAt = RMBTHelpers.RMBTCurrentNanos()
                
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)

        let hostCString = host.cString(using: .utf8) // .ascii?
        addr.sin_addr.s_addr = inet_addr(hostCString)

        if addr.sin_addr.s_addr == INADDR_NONE {
            guard let hostinfo = gethostbyname(hostCString) else {
                let errorString = String(cString: strerror(h_errno), encoding: .ascii)
                Log.logger.error("DNS resolution failed: \(String(describing: errorString))")
                return
            }

            memcpy(&addr.sin_addr, hostinfo.pointee.h_addr_list[0], Int(hostinfo.pointee.h_length))
        }
        
        let receiveSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard receiveSocket != -1 else {
            status = .error
            return
        }

        guard fcntl(receiveSocket, F_SETFL, O_NONBLOCK) != -1 else {
            status = .error
            close(receiveSocket)
            return
        }

        let sendSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP)
        guard sendSocket != -1 else {
            status = .error
            close(receiveSocket)
            return
        }

        // bind to thread-unique source port
        var bindAddr = sockaddr_in()
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_addr.s_addr = INADDR_ANY.bigEndian

        let tid = pthread_mach_thread_np(pthread_self())
        bindAddr.sin_port = UInt16((0xffff & tid) | 0x8000).bigEndian

        let bindResult = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1, {
                return bind(sendSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
            })
        }

        guard bindResult != -1 else {
            status = .error
            close(receiveSocket)
            close(sendSocket)
            return
        }

        var ttl = 1
        var ipAddr: in_addr_t = 0

        _result = []
        var hopResult: [String: Any]?

        repeat {
            addr.sin_port = UInt16(Int(kStartPort) + ttl - 1).bigEndian

            hopResult = traceWithSendSock(sendSocket, recvSock: receiveSocket, ttl: ttl, port: bindAddr.sin_port, sockAddr: addr, ipAddr: &ipAddr)
            if let hop = hopResult {
                _result?.append(hop)
                progress.completedUnitCount += 1
            }

            ttl += 1
            guard ttl <= maxHops else {
                Log.logger.warning("Traceroute reached max hops (\(ttl) > \(maxHops))")
                maxHopsExceeded = true
                break
            }

            guard RMBTHelpers.RMBTCurrentNanos() - startedAt <= timeoutNanos else {
                Log.logger.warning("Traceroute timed out after \(timeoutNanos)ns")
                timedOut = true
                break
            }

        } while hopResult != nil && !isCancelled && ipAddr != addr.sin_addr.s_addr

        close(sendSocket)
        close(receiveSocket)

        if hopResult == nil {
            _result = nil
        }
    }
    
    func traceWithSendSock(_ sendSock: Int32, recvSock: Int32, ttl: Int, port: in_port_t, sockAddr: sockaddr_in, ipAddr: inout in_addr_t) -> [String: Any]? {
        var mutableTttl = ttl
        var mutableAddr = sockAddr

        let t = setsockopt(sendSock, IPPROTO_IP, IP_TTL, &mutableTttl, socklen_t(MemoryLayout<Int>.size))
        guard t != -1 else {
            return nil
        }

        var storageAddr = sockaddr_in()
        var n = socklen_t(MemoryLayout<sockaddr>.size)
        var payload = CChar(ttl & 0xFF)

        let startTime = RMBTHelpers.RMBTCurrentNanos()

        let sendto_result = withUnsafePointer(to: &mutableAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1, {
                return sendto(sendSock, &payload, MemoryLayout<CChar>.size, 0, $0, socklen_t(MemoryLayout<sockaddr>.stride))
            })
        }

        guard sendto_result == MemoryLayout<CChar>.size else {
            return nil
        }

        while (RMBTHelpers.RMBTCurrentNanos() - startTime) < kTimeout * NSEC_PER_SEC {
            var tv = timeval()

            tv.tv_sec = __darwin_time_t(kTimeout)
            tv.tv_usec = 0

            var readfds = fd_set()
            fd_set.fdZero(&readfds)
            fd_set.fdSet(recvSock, set: &readfds)

            let ret = Darwin.select(recvSock + 1, &readfds, nil, nil, &tv)
            let hopDurationNs = RMBTHelpers.RMBTCurrentNanos() - startTime

            if ret < 0 {
                return nil
            } else if ret == 0 {
                break
            } else {
                guard fd_set.fdIsSet(recvSock, set: &readfds) else {
                    break
                }

                var buf = [Int8](repeating: 0, count: 512)

                let len = withUnsafeMutablePointer(to: &storageAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1, { (a: UnsafeMutablePointer<sockaddr>) in
                        return Darwin.recvfrom(recvSock, &buf, buf.count, 0, a, &n)
                    })
                }

                guard len >= 0 else {
                    return nil
                }

                guard let ipHeader: ip = (buf.withUnsafeBytes { bufPtr in
                    return bufPtr.baseAddress?.bindMemory(to: ip.self, capacity: 1).pointee
                }) else {
                    break
                }

                let hlen = Int32(ipHeader.ip_hl << 2)

                guard len >= hlen + ICMP_MINLEN else {
                   break
                }

                var ips = [Int8](repeating: 0, count: 16)

                _ = inet_ntop(AF_INET, &storageAddr.sin_addr.s_addr, &ips, socklen_t(ips.count)) // TODO: check return value?
                guard let icmpHeader: icmp = (buf.withUnsafeBytes { bufPtr in
                    return bufPtr.baseAddress?.advanced(by: Int(hlen)).bindMemory(to: icmp.self, capacity: 1).pointee
                }) else {
                    break
                }

                let icmpType = icmpHeader.icmp_type
                let icmpCode = icmpHeader.icmp_code

                if (icmpType == ICMP_TIMXCEED && icmpCode == ICMP_TIMXCEED_INTRANS) || icmpType == ICMP_UNREACH {
                    let icmpIpHeader = icmpHeader.icmp_dun.id_ip.idi_ip
                    let innerHlen = Int32(icmpIpHeader.ip_hl << 2)

                    if icmpIpHeader.ip_p == IPPROTO_UDP {
                        guard let udpHeader: udphdr = (buf.withUnsafeBytes { bufPtr in
                            // TODO: why +8?
                            return bufPtr.baseAddress?.advanced(by: Int(hlen + innerHlen) + 8).bindMemory(to: udphdr.self, capacity: 1).pointee
                        }) else {
                            break
                        }

                        let matching = udpHeader.uh_sport == port && udpHeader.uh_dport == UInt16(Int(kStartPort) + ttl - 1).bigEndian
                        if matching {
                            ipAddr = storageAddr.sin_addr.s_addr

                            guard let remoteAddress = String(cString: &ips, encoding: .utf8) else {
                                break
                            }
                            
                            let address = self.maskIp(address: remoteAddress)
                            
                            Log.logger.info("Adding hop (host=\"\(address)\", time=\(hopDurationNs))")
                            
                            return [
                                "host": address,
                                "time": hopDurationNs
                            ]
                        }
                    }
                }
            }
        }

        let hopDurationNs = RMBTHelpers.RMBTCurrentNanos() - startTime

        Log.logger.info("Adding hop (host=\"*\", time=\(hopDurationNs)")
        return [
            "host": "*",
            "time": hopDurationNs
        ]
    }
    
    func maskIp(address: String) -> String {
        var components = address.components(separatedBy: ".")
        if components.count == 4 {
            components[3] = "x"
            return components.joined(separator: ".")
        }
        
        return address
    }
    
    override var result: [String: Any] {
        var result: [String: Any] = [
            "traceroute_objective_host": host,
            "traceroute_objective_max_hops": maxHops,
            "traceroute_objective_timeout": self.timeoutNanos,
        ]

        if (maxHopsExceeded) {
            result["traceroute_result_status"] = "MAX_HOPS_EXCEEDED"
        } else if (timedOut) {
            result["traceroute_result_status"] = "TIMEOUT"
        } else {
            result["traceroute_result_status"] = "OK"
        }

        if (_result != nil && _result?.count ?? 0 > 0) {
            result["traceroute_result_details"] = _result
            result["traceroute_result_hops"] = _result?.count ?? 0
        } else {
            result["traceroute_result_status"] = "ERROR"
        }
        return result;
    }
    
    override var description: String {
        return String(format:"RMBTQosTracerouteTest (masked=%@, uid=%@, cg=%ld, %@ (TTL: %lu)",
                masked ? "Y" : "N",
                self.uid,
                self.concurrencyGroup,
                host,
                maxHops)
    }
    
}
