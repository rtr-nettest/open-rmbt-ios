//
//  RMBTQoSTestGroup.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 11.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit


@objc class RMBTQoSTestGroup: NSObject {

    @objc private(set) var key: String
    @objc private(set) var localizedDescription: String
    
    private var initializer: (_ p: [String: Any]) -> RMBTQoSTest?
    
    @objc(groupForKey:localizedDescription:)
    static func group(for key: String, description: String) -> Self? {
        let initializer: (_ p: [String: Any]) -> RMBTQoSTest?

        // DNS test disabled fro now since current code not compatible with iOS 18.4+
//        if key == "dns" {
//            initializer = { p in
//                return RMBTQoSDNSTest(with: p)
//            }
//        } else
        if key == "http_proxy" {
            initializer = { p in
                return RMBTQoSHTTPTest(with: p)
            }
        } else if key == "traceroute" {
            initializer = { p in
                return RMBTQoSTracerouteTest(with: p, masked: false)
            }
        } else if key == "traceroute_masked" {
            initializer = { p in
                return RMBTQoSTracerouteTest(with: p, masked: true)
            }
        } else if key == "website" {
            initializer = { p in
                return RMBTQoSWebTest(with: p)
            }
        } else if key == "udp" {
            initializer = { p in
                return RMBTQoSUDPTest(with: p)
            }
        } else if key == "tcp" {
            initializer = { p in
                return RMBTQoSTCPTest(with: p)
            }
        } else if key == "non_transparent_proxy" {
            initializer = { p in
                return RMBTQoSNonTransparentProxyTest(with: p)
            }
        } else {
            Log.logger.error("Unknown QoS group: \(key)")
            return nil
        }
        
        return RMBTQoSTestGroup(with: key, description: description, initializer: initializer) as? Self
    }
    
    @objc(testWithParams:)
    func test(with params: [String: Any]) -> RMBTQoSTest? {
        let t = initializer(params)
        t?.group = self
        return t
    }

    init(with key: String, description: String, initializer: @escaping (_ p: [String: Any]) -> RMBTQoSTest?) {
        self.key = key
        self.localizedDescription = description
        self.initializer = initializer
    }
    
    override var description: String {
        return String(format: "RMBTQoSTestGroup (key=\(String(describing: key)))")
    }
}
