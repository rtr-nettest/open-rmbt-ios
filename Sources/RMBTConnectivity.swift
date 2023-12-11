//
//  RMBTConnectivity.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 21.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import CoreTelephony
import SystemConfiguration.CaptiveNetwork

enum RMBTNetworkType: Int {
    case unknown  = -1
    case none     = 0 // Used internally to denote no connection
    case browser  = 98
    case wifi     = 99
    case cellular = 105
}

enum RMBTConnectivityInterfaceInfoTraffic: UInt {
    case sent
    case received
    case total
}

struct RMBTConnectivityInterfaceInfo {
    var bytesReceived: UInt64
    var bytesSent: UInt64
}

class RMBTConnectivity: NSObject {
    private(set) var networkType: RMBTNetworkType = .none
    // Human readable description of the network type: Wi-Fi, Celullar
    var networkTypeDescription: String {
        switch networkType {
        case .none:
            return ""
        case .browser:
            return "Browser"
        case .wifi:
            return "WLAN"
        case .cellular:
            return self.cellularCodeDescription ?? "Cellular"
        case .unknown:
            return ""
        }
    }
    
    // Carrier name for cellular, SSID for Wi-Fi
    private(set) var networkName: String?

    // Timestamp at which connectivity was detected
    private(set) var timestamp: Date = Date()

    private(set) var cellularCode: Int?
    
    private(set) var bssid: String?
    
    private var cellularCodeDescription: String?
//    private var cellularCodeGenerationString: String?
    
    private var dualSim: Bool = false
    
    var networkTypeTechnology: RMBTNetworkTypeConstants.NetworkType? {
        if networkType == .cellular {
            guard let code = cellularCodeDescription else { return nil }
            return RMBTNetworkTypeConstants.cellularCodeDescriptionDictionary[code]
        } else if networkType == .wifi {
            return RMBTNetworkTypeConstants.NetworkType.wlan
        }else if networkType == .browser {
            return RMBTNetworkTypeConstants.NetworkType.browser
        }
        return nil
    }
    
    init(networkType: RMBTNetworkType) {
        self.networkType = networkType
        super.init()
        self.getNetworkDetails()
    }
    
    func testResultDictionary() -> [String: Any] {
        var result: [String: Any] = [:]
        

        let code = self.networkType.rawValue
        if (code > 0) {
            result["network_type"] = code
        }

        if (self.networkType == .wifi) {
            result["wifi_ssid"] = networkName
            result["wifi_bssid"] = bssid
        } else if (self.networkType == .cellular) {
            //TODO: Imrove this code. Sometimes iPhone 12 always send two dictionaries as dial sim. We take first where we have carrier name
            if (dualSim) {
                result["dual_sim"] = true
            }

            result["network_type"] = cellularCode
        }
        return result
    }

    func isEqual(to connectivity: RMBTConnectivity?) -> Bool {
        if (connectivity == self) { return true }
        guard let connectivity = connectivity else {
            return false
        }

        return ((connectivity.networkTypeDescription == self.networkTypeDescription &&
                 connectivity.dualSim && self.dualSim) ||
                (connectivity.networkTypeDescription == self.networkTypeDescription && connectivity.networkName == self.networkName))
    }

    // Gets byte counts from the network interface used for the connectivity.
    // Note that the count refers to number of bytes since device boot.
    func getInterfaceInfo() -> RMBTConnectivityInterfaceInfo {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        var stats: UnsafeMutablePointer<if_data>? = nil

        var bytesSent: UInt64 = 0
        var bytesReceived: UInt64 = 0
        
        var result = RMBTConnectivityInterfaceInfo(bytesReceived: bytesReceived, bytesSent: bytesSent)
        
        guard getifaddrs(&ifaddr) == 0 else { return result }
        
        while let ptr = ifaddr {
            let addr = ptr.pointee.ifa_addr.pointee
            
            guard let value = ptr.pointee.ifa_name else {
                ifaddr = ptr.pointee.ifa_next
                continue
            }
            
            guard let name = String(cString: value, encoding: .ascii),
                  addr.sa_family == UInt8(AF_LINK),
                  (name.hasPrefix("en") && self.networkType == .wifi) ||
                  (name.hasPrefix("pdp_ip") && self.networkType == .cellular)
            else {
                ifaddr = ptr.pointee.ifa_next
                continue
            }
            
            stats = unsafeBitCast(ptr.pointee.ifa_data, to: UnsafeMutablePointer<if_data>.self)
            if let stats = stats {
                bytesSent += UInt64(stats.pointee.ifi_obytes)
                bytesReceived += UInt64(stats.pointee.ifi_ibytes)
            }
            
            ifaddr = ptr.pointee.ifa_next
        }
        
        freeifaddrs(ifaddr)
        
        result.bytesSent = bytesSent
        result.bytesReceived = bytesReceived
        
        return result
    }

    static private func WRAPPED_DIFF(_ x: UInt64, _ y: UInt64) -> UInt64 {
        let maxInterfaceValue: UInt64 = 4294967295
        if y >= x {
            return y - x
        } else if (x <= maxInterfaceValue) {
            return (maxInterfaceValue - x) + y
        }
        return y
    }
    
    // Total (up+down) difference in bytes transferred between two readouts. If counter has wrapped returns 0.
    static func countTraffic(_ traffic: RMBTConnectivityInterfaceInfoTraffic, between info1: RMBTConnectivityInterfaceInfo, and info2: RMBTConnectivityInterfaceInfo) -> UInt64 {
        var result: UInt64 = 0
        if (traffic == .sent || traffic == .total) {
            result += WRAPPED_DIFF(info1.bytesSent, info2.bytesSent)
        }
        if (traffic == .received || traffic == .total) {
            result += WRAPPED_DIFF(info1.bytesReceived, info2.bytesReceived);
        }
        return result
    }
    
    fileprivate func updateCellularInfo() {
        let netinfo = CTTelephonyNetworkInfo()
        var radioAccessTechnology: String?
        
        if let dataIndetifier = netinfo.dataServiceIdentifier {
            radioAccessTechnology = netinfo.serviceCurrentRadioAccessTechnology?[dataIndetifier]
        }

        networkName = nil

        //Get access technology
        if let radioAccessTechnology = radioAccessTechnology {
            cellularCode = cellularCodeForCTValue(radioAccessTechnology)
            cellularCodeDescription = cellularCodeDescriptionForCTValue(radioAccessTechnology)
        }
    }
    
    private func getWiFiParameters() -> (ssid: String, bssid: String)? {
        if let interfaces = CNCopySupportedInterfaces() as? [CFString] {
            for interface in interfaces {
                if let interfaceData = CNCopyCurrentNetworkInfo(interface) as? [CFString: Any],
                let currentSSID = interfaceData[kCNNetworkInfoKeySSID] as? String,
                let currentBSSID = interfaceData[kCNNetworkInfoKeyBSSID] as? String {
                    return (ssid: currentSSID, bssid: RMBTReformatHexIdentifier(currentBSSID))
                }
            }
        }
        return nil
    }
    
    private func getNetworkDetails() {
        self.networkName = nil
        self.bssid = nil
        self.cellularCode = nil
        self.cellularCodeDescription = nil
        self.dualSim = false
        
        switch networkType {
        case .cellular: self.updateCellularInfo()
        case .wifi:
            // If WLAN, then show SSID as network name. Fetching SSID does not work on the simulator.
            if let wifiParams = getWiFiParameters() {
                networkName = wifiParams.ssid
                bssid = wifiParams.bssid
            }
        case .none: break
        default:
            assert(false, "Invalid network type \(networkType)")
        }
    }

    fileprivate func cellularCodeForCTValue(_ value: String?) -> Int? {
        guard let value = value else { return nil }

        return cellularCodeTable[value]
    }

    fileprivate var cellularCodeTable: [String: Int] {
        //https://specure.atlassian.net/wiki/spaces/NT/pages/144605185/Network+types
        var table = [
            CTRadioAccessTechnologyGPRS:         1,
            CTRadioAccessTechnologyEdge:         2,
            CTRadioAccessTechnologyWCDMA:        3,
            CTRadioAccessTechnologyCDMA1x:       4,
            CTRadioAccessTechnologyCDMAEVDORev0: 5,
            CTRadioAccessTechnologyCDMAEVDORevA: 6,
            CTRadioAccessTechnologyHSDPA:        8,
            CTRadioAccessTechnologyHSUPA:        9,
            CTRadioAccessTechnologyCDMAEVDORevB: 12,
            CTRadioAccessTechnologyLTE:          13,
            CTRadioAccessTechnologyeHRPD:        14
        ]

        table[CTRadioAccessTechnologyNRNSA] = 41
        table[CTRadioAccessTechnologyNR] = 20
        return table
    }

    fileprivate func cellularCodeDescriptionForCTValue(_ value: String!) -> String? {
        if value == nil {
            return nil
        }

        return cellularCodeDescriptionTable[value] ?? nil
    }

    fileprivate var cellularCodeDescriptionTable: [String: String] {
        var table = [
            CTRadioAccessTechnologyGPRS:            "2G/GSM",
            CTRadioAccessTechnologyEdge:            "2G/EDGE",
            CTRadioAccessTechnologyWCDMA:           "3G/UMTS",
            CTRadioAccessTechnologyCDMA1x:          "2G/CDMA",
            CTRadioAccessTechnologyCDMAEVDORev0:    "2G/EVDO_0",
            CTRadioAccessTechnologyCDMAEVDORevA:    "2G/EVDO_A",
            CTRadioAccessTechnologyHSDPA:           "3G/HSDPA",
            CTRadioAccessTechnologyHSUPA:           "3G/HSUPA",
            CTRadioAccessTechnologyCDMAEVDORevB:    "2G/EVDO_B",
            CTRadioAccessTechnologyLTE:             "4G/LTE",
            CTRadioAccessTechnologyeHRPD:           "2G/HRPD",
        ]

        table[CTRadioAccessTechnologyNRNSA] = "5G/NRNSA"
        table[CTRadioAccessTechnologyNR] = "5G/NR"
        
        return table
    }
}
