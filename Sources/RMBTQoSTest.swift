//
//  RMBTQoSTest.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 09.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

enum RMBTQoSTestStatus: Int {
    case unknown
    case ok
    case error
    case timeout
    
    var name: String {
        switch self {
        case .unknown: return "UKNOWN"
        case .ok: return "OK"
        case .timeout: return "TIMEOUT"
        case .error: return "ERROR"
        }
    }
}

@objc class RMBTQoSTest: Operation, @unchecked Sendable {
    static let kDefaultTimeoutNanos: UInt64 = 10 * NSEC_PER_SEC
    
    @objc var progress: RMBTProgress = RMBTProgress(totalUnitCount: 100)
    
    @objc weak var group: RMBTQoSTestGroup?
    
    var status: RMBTQoSTestStatus = .unknown

    @objc private(set) var concurrencyGroup: UInt = 0
    @objc private(set) var uid: String = ""
    private(set) var timeoutNanos: UInt64 = 0
    
    @objc private(set) var result: [String: Any] = [:]
    @objc private(set) var durationNanos: Int64 = 0
    private var startedAtNanos: UInt64 = 0

    init?(with params: [String: Any]) {
        concurrencyGroup = params["concurrency_group"] as? UInt ?? 0
        
        guard let uid = params["qos_test_uid"] as? String,
              !uid.isEmpty
        else { return nil }
        
        self.uid = uid
            
        let timeoutStr = (params["timeout"] as? String) ?? String(RMBTQoSTest.kDefaultTimeoutNanos)
        
        timeoutNanos = strtoull(timeoutStr, nil, 10)
    }
    
    func timeoutSeconds() -> Int {
        return max(1, Int(timeoutNanos / NSEC_PER_SEC))
    }
    
    func statusName() -> String? {
        return self.status.name
    }
    
    override func start() {
        if (self.isCancelled) {
            Log.logger.debug("Test \(self) cancelled.")
        }
        
        assert(!self.isFinished)
        
        if (!self.isCancelled) { Log.logger.debug("Test \(self) started.") }
        
        startedAtNanos = RMBTHelpers.RMBTCurrentNanos()
        super.start()
        durationNanos = Int64(RMBTHelpers.RMBTCurrentNanos() - startedAtNanos)
        if (!self.isCancelled) { Log.logger.debug("Test \(self) finished.") }
    }
}
