//
//  RMBTConfig.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 04.08.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import Foundation

/// default qos socket character encoding
let QOS_SOCKET_DEFAULT_CHARACTER_ENCODING: UInt = String.Encoding.utf8.rawValue

public let DEFAULT_LANGUAGE = "en"
public let PREFFERED_LANGUAGE = Bundle.main.preferredLocalizations.first ?? DEFAULT_LANGUAGE

public class RMBTConfig {
    public static let shared: RMBTConfig = {
        let config = RMBTConfig()
        LogConfig.initLoggingFramework()
        return config
    }()
    
    var RMBT_USE_MAIN_LANGUAGE: Bool { return false }
    var RMBT_MAIN_LANGUAGE: String { return "en" }
    
    let RMBT_DEFAULT_IS_CURRENT_COUNTRY: Bool = true
    
    var RMBT_CHECK_IPV4_URL: String {
        return "\(RMBT_IPV4_URL_HOST)\(RMBT_CONTROL_SERVER_PATH)/ip"
    }
    
    var RMBT_CONTROL_SERVER_URL: String {
        return "\(RMBT_URL_HOST)\(RMBT_CONTROL_SERVER_PATH)"
    }
    
    var RMBT_MAP_SERVER_URL: String { return "\(RMBT_URL_HOST)\(RMBT_MAP_SERVER_PATH)" }
    
    // Control server base URL used per default
    
    #if DEBUG
    // Control server base URL used per default
    
//    var RMBT_URL_HOST: String { return "https://dev3new.netztest.at" }
////    var RMBT_URL_HOST: String { return "https://rtr-api-dev.nettest.org" }
//    // Control server base URL used when user has enabled the "IPv4-Only" setting
//    var RMBT_IPV4_URL_HOST: String { return "https://dev.netztest.at" }
//    // Ditto for the (debug) "IPv6-Only" setting
//    var RMBT_IPV6_URL_HOST: String { return "https://dev.netztest.at" }
    
    
//    // Control server base URL used per default
//    var RMBT_URL_HOST: String { return "https://api-dev.nettest.org" }
//    // Control server base URL used when user has enabled the "IPv4-Only" setting
//    var RMBT_IPV4_URL_HOST: String { return "https://rtr-api-devv4.nettest.org" }
//    // Ditto for the (debug) "IPv6-Only" setting
//    var RMBT_IPV6_URL_HOST: String { return "https://rtr-api-devv6.nettest.org" }

    var RMBT_URL_HOST: String { return "https://c01.netztest.at" }
    // Control server base URL used when user has enabled the "IPv4-Only" setting
    var RMBT_IPV4_URL_HOST: String { return "https://c01v4.netztest.at" }
    // Ditto for the (debug) "IPv6-Only" setting
    var RMBT_IPV6_URL_HOST: String { return "https://c01v6.netztest.at" }
    
    #else
    // Control server base URL used per default
    var RMBT_URL_HOST: String { return "https://c01.netztest.at" }
    // Control server base URL used when user has enabled the "IPv4-Only" setting
    var RMBT_IPV4_URL_HOST: String { return "https://c01v4.netztest.at" }
    // Ditto for the (debug) "IPv6-Only" setting
    var RMBT_IPV6_URL_HOST: String { return "https://c01v6.netztest.at" }
    #endif
    
    var RMBT_CONTROL_SERVER_PATH: String { return "/RMBTControlServer" }
    var RMBT_MAP_SERVER_PATH: String { return "/RMBTMapServer" }
    
    //Colors
    let darkColor = UIColor.rmbt_color(withRGBHex: 0xFFFFFF)
    let tintColor = UIColor.rmbt_color(withRGBHex: 0x424242)
    
    let DEV_CODE = "any_code"
}
