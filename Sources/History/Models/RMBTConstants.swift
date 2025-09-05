//
//  RMBTConstants.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 05.09.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

final class RMBTNetworkTypeConstants {

    enum NetworkType {
        case unknown
        case browser
        case type2G
        case type3G
        case type4G
        case type5G
        case type5GNSA
        case type5GAvailable
        case wlan
        case lan
        case bluetooth
        
        var icon: UIImage? {
            switch self {
            case .unknown: return UIImage(named: "ic_marker_empty")
            case .browser: return UIImage(named: "ic_marker_browser")
            case .type2G: return UIImage(named: "2g_neutral")
            case .type3G: return UIImage(named: "3g_neutral")
            case .type4G: return UIImage(named: "4g_neutral")
            case .type5G: return UIImage(named: "5g_neutral")
            case .type5GNSA: return UIImage(named: "5g_neutral")
            case .type5GAvailable: return UIImage(named: "5g_neutral")
            case .wlan: return UIImage(named: "wifi_neutral")
            default: return nil
            }
        }
        
        var technologyIcon: UIImage? {
            switch self {
            case .unknown: return nil
            case .browser: return nil
            case .type2G: return UIImage(named: "2g_icon")
            case .type3G: return UIImage(named: "3g_icon")
            case .type4G: return UIImage(named: "4g_icon")
            case .type5G: return UIImage(named: "5g_icon")
            case .type5GNSA: return UIImage(named: "5g_icon")
            case .type5GAvailable: return UIImage(named: "5g_icon")
            case .wlan: return nil
            default: return nil
            }
        }
    }
    
    static var networkTypeDictionary: [String: NetworkType] = [
        "2G": .type2G,
        "2G (GSM)": .type2G,
        "2G (EDGE)": .type2G,
        "3G (UMTS)": .type2G,
        "2G (CDMA)": .type2G,
        "2G (EVDO_0)": .type2G,
        "2G (EVDO_A)": .type2G,
        "2G (1xRTT)": .type2G,
        "3G": .type3G,
        "3G (HSDPA)": .type3G,
        "3G (HSUPA)": .type3G,
        "3G (HSPA)": .type3G,
        "2G (IDEN)": .type2G,
        "2G (EVDO_B)": .type2G,
        "4G (LTE)": .type4G,
        "4G": .type4G,
        "2G (EHRPD)": .type2G,
        "3G (HSPA+)": .type3G,
        "4G (LTE CA)": .type4G,
        "5G": .type5G,
        "5G (NR)": .type5G,
        "5G (NSA)": .type5GNSA,
        "4G+(5G)": .type5GNSA,
        "CLI": .unknown,
        "BROWSER": .browser,
        "WLAN": .wlan,
        "2G/3G": .type3G,
        "3G/4G": .type3G,
        "2G/4G": .type4G,
        "2G/3G/4G": .type4G,
        "MOBILE": .type3G,
        "Ethernet": .lan,
        "Bluetooth": .unknown,
        "UNKNOWN": .unknown,
    ]
    
    static var cellularCodeDescriptionDictionary: [String: NetworkType] = [
        "2G/GPRS": .type2G,
        "2G/GSM": .type2G,
        "2G/EDGE": .type2G,
        "2G/CDMA": .type2G,
        "2G/EVDO_0": .type2G,
        "2G/EVDO_A": .type2G,
        "2G/EVDO_B": .type2G,
        "2G/HRPD": .type2G,
        "2G/EHRPD": .type2G,
        "3G/UMTS": .type3G,
        "3G/HSDPA": .type3G,
        "3G/HSUPA": .type3G,
        "4G/LTE": .type4G,
        "5G/NRNSA": .type5GNSA,
        "5G/NR": .type5G,
    ]
}
