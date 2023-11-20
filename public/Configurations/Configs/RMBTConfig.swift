//
//  RMBTConfig.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 04.08.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

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


    var RMBT_URL_HOST: String { return "https://example.com" }
    // Control server base URL used when user has enabled the "IPv4-Only" setting
    var RMBT_IPV4_URL_HOST: String { return "https://example.com" }
    // Ditto for the (debug) "IPv6-Only" setting
    var RMBT_IPV6_URL_HOST: String { return "https://example.com" }

    var RMBT_CONTROL_SERVER_PATH: String { return "/RMBTControlServer" }
    var RMBT_MAP_SERVER_PATH: String { return "/RMBTMapServer" }

    //Colors
    static let darkColor = UIColor.rmbt_color(withRGBHex: 0xFFFFFF)
    static let tintColor = UIColor.rmbt_color(withRGBHex: 0x424242)
    
    static let ACTIVATE_DEV_CODE = "88888888"
    static let DEACTIVATE_DEV_CODE = "00000000"
    
    static let RMBT_TEST_LOOPMODE_MIN_COUNT = 1
    static let RMBT_TEST_LOOPMODE_DEFAULT_COUNT = 10
    static let RMBT_TEST_LOOPMODE_MAX_COUNT = 100

    // Loop mode will stop automatically after this many seconds:
    static let RMBT_TEST_LOOPMODE_MAX_DURATION_S = (48*60*60) // 48 hours

    // Minimum/maximum number of minutes that user can choose to wait before next test is started:
    static let RMBT_TEST_LOOPMODE_MIN_DELAY_MINS = 5
    static let RMBT_TEST_LOOPMODE_DEFAULT_DELAY_MINS = 10
    static let RMBT_TEST_LOOPMODE_MAX_DELAY_MINS = (24 * 60) // one day

    // ... meters user locations must change before next test is started:
    static let RMBT_TEST_LOOPMODE_MIN_MOVEMENT_M = 50
    static let RMBT_TEST_LOOPMODE_DEFAULT_MOVEMENT_M = 250
    static let RMBT_TEST_LOOPMODE_MAX_MOVEMENT_M = 10000
    
    // Note: $lang will be replaced by "de" is device language is german, or "en" in any other case:
    static let RMBT_PROJECT_URL = "https://example.com/"
    static let RMBT_PROJECT_EMAIL = "mail@example.com"
    static let RMBT_PRIVACY_TOS_URL = "https://example.com/$lang/tc_ios.html"
    static let RMBT_ABOUT_URL = "https://example.com/$lang/"

    // Note: stats url can can be replaced with the /settings response from control server
    static let RMBT_STATS_URL = "https://example.com/$lang/Statistik#noMMenu"

    static let RMBT_HELP_URL = "https://example.com/redirect/$lang/help"

    static let RMBT_REPO_URL = "https://github.com/rtr-nettest/open-rmbt-ios"
    static let RMBT_DEVELOPER_URL = "https://example.com/"
    static let RMBT_DEVELOPER_NAME = "your name"

    // Current TOS version. Bump to force displaying TOS to users again.
    static let RMBT_TOS_VERSION = 6
    
    
    static let RMBT_MAP_AUTO_TRESHOLD_ZOOM = 12
    
    
    // Timeout for connecting and reading responses back from QoS control server
    static let RMBT_QOS_CC_TIMEOUT_S = 5.0
    static let RMBT_TEST_SOCKET_TIMEOUT_S = 30.0
    
    // The getaddrinfo() used by GCDAsync socket will fail immediately if the hostname of the test server
    // is not in the DNS cache. To work around this, in case of this particular error we will retry couple
    // of times before giving up:
    static let RMBT_TEST_HOST_LOOKUP_RETRIES = 1 // How many times to retry
    static let RMBT_TEST_HOST_LOOKUP_WAIT_S = 0.2 // How long to wait before next retry
    
    // In case of slow upload, we finalize the test even if this many seconds still haven't been received:
    static let RMBT_TEST_UPLOAD_MAX_DISCARD_S = 1.0

    // Minimum number of seconds to wait after sending last chunk, before starting to discard.
    static let RMBT_TEST_UPLOAD_MIN_WAIT_S = 0.25

    // Maximum number of seconds to wait for server reports after last chunk has been sent.
    // After this interval we will close the socket and finish the test on first report received.
    static let RMBT_TEST_UPLOAD_MAX_WAIT_S = 3

    // Measure and submit speed during test in these intervals
    static let RMBT_TEST_SAMPLING_RESOLUTION_MS = 100
    
    static let RMBT_TEST_PRETEST_MIN_CHUNKS_FOR_MULTITHREADED_TEST = 4
    static let RMBT_TEST_PRETEST_DURATION_S = 2.0
    static let RMBT_TEST_PING_COUNT = 10
}
