//
//  Log.swift
//  RMBTClient
//
//  Created by Sergey Glushchenko on 4/4/18.
//

import XCGLogger

@objc public class Log: NSObject {
    public static let logger = XCGLogger.init(identifier: "RMBTClient", includeDefaultDestinations: false)
    
    @objc static func log(_ string: String) {
        logger.debug(string)
    }
}
