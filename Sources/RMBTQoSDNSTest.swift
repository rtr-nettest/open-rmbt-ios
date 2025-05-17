//
//  RMBTQoSDNSTest.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 10.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

@objc class RMBTQoSDNSTest: RMBTQoSTest, @unchecked Sendable {

    private var resolver: String?
    private var resultResolver: String?
    private var host: String = ""
    private var record: String = ""
    private var rcode: String?
    
    private var timedOut: Bool = false
    
    var entries: [[String: Any]]?

    private var timeoutSeconds: Int32 {
        return Int32(max(1, self.timeoutNanos / NSEC_PER_SEC))
    }
    
    override init?(with params: [String : Any]) {
        super.init(with: params)
        
        host = params["host"] as? String ?? ""
        resolver = params["resolver"] as? String
        record = params["record"] as? String ?? ""
    }
    
    override func cancel() {
        super.cancel()
    }
    
    override func main() {
        assert(!self.isCancelled)
        
        let startTime = RMBTHelpers.RMBTCurrentNanos()
        
        let t = self.queryType()
        if (t == ns_t_invalid) {
            Log.logger.error("..unknown record type \(record), won't run")
            return
        }
        
        var res = __res_9_state()
        guard res_9_ninit(&res) == 0 else {
            return
        }
        
        res.retry = 1
        res.retrans = Int32(self.timeoutSeconds())
        
        if let resolver = self.resolver {
            // Custom DNS server
            var addr = in_addr()
            inet_aton(resolver, &addr)
            
            res.nsaddr_list.0.sin_addr = addr
            res.nsaddr_list.0.sin_family = sa_family_t(AF_INET) // TODO: support ipv6 name servers
            res.nsaddr_list.0.sin_port = in_port_t(NS_DEFAULTPORT).bigEndian // TODO: support other dns server port
            res.nscount = 1
        }
        
        if (self.isCancelled) { return }
        
        entries = []
        
        var answer = [CUnsignedChar](repeating: 0, count: Int(NS_PACKETSZ))
        
        let len: CInt = res_9_nquery(&res, host, Int32(ns_c_in.rawValue), Int32(t.rawValue), &answer, Int32(answer.count))

        if (len == -1) {
            if (h_errno == HOST_NOT_FOUND) {
                rcode = "NXDOMAIN";
            } else if (h_errno == TRY_AGAIN) {
                let nanoSecondsAfterStart = RMBTHelpers.RMBTCurrentNanos() - startTime
                if (nanoSecondsAfterStart < UInt64(self.timeoutSeconds()) * NSEC_PER_SEC) {
                    rcode = "TRY_AGAIN"
                } else {
                    timedOut = true
                }
            } else if (h_errno == NO_DATA) {
                rcode = "NO_DATA"
            }
        } else {
            var handle = __ns_msg()
            res_9_ns_initparse(answer, len, &handle)

            let rcode = res_9_ns_msg_getflag(handle, Int32(ns_f_rcode.rawValue))
            if let rcodeCStr = res_9_p_rcode(rcode), let rcodeSwiftString = String(cString: rcodeCStr, encoding: .ascii) {
                self.rcode = rcodeSwiftString
            } else {
                self.rcode = "UNKNOWN" // or ERROR?
            }
            
            let answerCount = handle._counts.1
            if(answerCount > 0) {
                var rr = __ns_rr()
                
                for i in 0..<answerCount {
                    if (self.isCancelled) { break }

                    if(res_9_ns_parserr(&handle, ns_s_an, Int32(i), &rr) == 0) {
                        let ttl: UInt32 = rr.ttl
                        var result: [String: Any] = [ "dns_result_ttl": ttl ]

                        let uint32_rr_type = UInt32(rr.type)
                        
                        if uint32_rr_type == ns_t_a.rawValue {
                            var buf = [Int8](repeating: 0, count: Int(INET_ADDRSTRLEN + 1))
                            if inet_ntop(AF_INET, rr.rdata, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                                result["dns_result_address"] = String(cString: buf, encoding: .ascii)
                            }
                        } else if uint32_rr_type == ns_t_aaaa.rawValue {
                            var buf = [Int8](repeating: 0, count: Int(INET6_ADDRSTRLEN + 1))
                            if inet_ntop(AF_INET6, rr.rdata, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil {
                                result["dns_result_address"] = String(cString: buf, encoding: .ascii)
                            }
                        } else if uint32_rr_type == ns_t_mx.rawValue || uint32_rr_type == ns_t_cname.rawValue {
                            var buf = [Int8](repeating: 0, count: Int(NS_MAXDNAME))

                            if res_9_ns_name_uncompress(handle._msg, handle._eom, rr.rdata, &buf, buf.count) != -1 {
                                result["dns_result_address"] = String(cString: buf, encoding: .ascii)

                                if uint32_rr_type == ns_t_mx.rawValue {
                                    result["dns_result_priority"] = res_9_ns_get16(rr.rdata)
                                }
                            }
                        }

                        entries?.append(result)
                    }
                }
            }
        }
        
        res_9_ndestroy(&res)
    }
    
    func queryType() -> ns_type {
        if (record == "A") {
            return ns_t_a
        } else if (record == "AAAA"){
            return ns_t_aaaa
        } else if (record == "MX") {
            return ns_t_mx
        } else if (record == "CNAME") {
            return ns_t_cname
        } else {
            return ns_t_invalid
        }
    }
    
    override var result: [String: Any] {
        var result: [String: Any] = [
            "dns_objective_resolver": resolver ?? resultResolver ?? "Standard",
            "dns_objective_dns_record": record,
            "dns_objective_host": host,
            "dns_objective_timeout": self.timeoutNanos
        ]
        
        if (timedOut) {
            result["dns_result_info"] = "TIMEOUT"
        } else if (entries == nil) {
            result["dns_result_info"] = "ERROR"
        } else {
            result["dns_result_status"] = rcode != nil ? rcode : "UNKNOWN"
            result["dns_result_info"] = "OK"
            result["dns_result_entries_found"] = entries?.count ?? 0
            result["dns_result_entries"] = entries ?? NSNull()

        }

        return result
    }
    
    override var description: String {
        return String(format:"RMBTQoSDNSTest (uid=%@, cg=%ld, %@ %@@%@)",
                    self.uid,
                    self.concurrencyGroup,
                    record,
                    host,
                    resolver ?? "-")
    }
}
