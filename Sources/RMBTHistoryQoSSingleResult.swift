//
//  RMBTHistoryQoSSingleResult.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 11.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

@objc class RMBTHistoryQoSSingleResult: NSObject {

    // Test summary, e.g. @"Target: ebay.de \nEntry: A\nResolver: Standard"
    @objc private(set) var summary: String?
    
    // Details of the executed test
    @objc private(set) var details: String?
    @objc private(set) var isSuccessful: Bool = false
    
    @objc private(set) var uid: NSNumber = NSNumber()
    @objc var statusDetails: String?
    
    @objc(initWithResponse:)
    init(with response: [String: Any]) {
        let failed = response["failure_count"] as? Int ?? 0
        let succeeded = response["success_count"] as? Int ?? 0
        
        isSuccessful = (failed == 0 && succeeded > 0)
        summary = response["test_summary"] as? String
        details = response["test_desc"] as? String
        uid = response["uid"] as? NSNumber ?? NSNumber()
    }
    
    func statusIcon() -> UIImage? {
        return UIImage(named: self.isSuccessful ? "traffic_lights_green" : "traffic_lights_red")
    }
    
}
