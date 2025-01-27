//
//  RMBTHelpers.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 09.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import Darwin

@inline(__always) func RMBTValueOrNull(_ value: Any?) -> Any { return value != nil ? value! : NSNull() }
@inline(__always) func RMBTValueOrString(_ value: Any?, _ result: String) -> Any { return value != nil ? value! : result }

public func RMBTReformatHexIdentifier(_ identifier: String!) -> String! { // !
    if identifier == nil {
        return nil
    }

    var tmp = [String]()

    for c in identifier.components(separatedBy: ":") {
        if c.count == 0 {
            tmp.append("00")
        } else if c.count == 1 {
            tmp.append("0\(c)")
        } else {
            tmp.append(c)
        }
    }

    return tmp.joined(separator: ":")
}

class RMBTHelpers: NSObject {
    static let mechTimebaseInfo: mach_timebase_info_data_t = {
        var info: mach_timebase_info_data_t = mach_timebase_info(numer: 0, denom: 0)
        mach_timebase_info(&info)
        return info
    }()
    
    static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.decimalSeparator = "."
        formatter.usesSignificantDigits = true
        formatter.minimumSignificantDigits = 2
        formatter.maximumSignificantDigits = 2
        return formatter
    }()
    
    static let appName: String = {
        return (Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String) ?? ""
    }()
    
    static let buildNumber: String = {
        return (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
    }()
    
    static let version: String = {
        return (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }()
    
    static let buildInfo: String = {
        guard let info = Bundle.main.infoDictionary else { return "--" }
        let gitBranch = info["GitBranch"] as? String ?? ""
        let gitCommitCount = info["GitCommitCount"] as? String ?? ""
        let gitCommit = info["GitCommit"] as? String ?? ""
        return String(format: "%@-%@-%@", gitBranch, gitCommitCount, gitCommit)
    }()

    static let buildDate: String = {
        guard let info = Bundle.main.infoDictionary else { return "--" }
        return info["BuildDate"] as? String ?? ""
    }()
    
    
    static func RMBTPreferredLanguage() -> String {
        let mostPreferredLanguage = Locale.preferredLanguages.first
        guard let language = mostPreferredLanguage?.components(separatedBy: "-").first?.lowercased()
        else { return "en" }
        return language
    }
    
    // Removes all trailing \n or \r
    @objc static func RMBTChomp(_ string: String) -> String {
        var l = string.count
        while (l > 0) {
            let c = (string as NSString).substring(with: NSRange(location: l - 1, length: 1))
            
            if (!(c == "\r" || c == "\n")) { break }
            l -= 1
        }
        return (string as NSString).substring(to: l)
    }
    
    @objc(RMBTPercent:total:)
    static func RMBTPercent(_ count: Int, _ totalCount: Int) -> UInt {
        var percent = (totalCount == 0) ? 0 : Double(count * 100) / Double(totalCount)
        if percent < 0 { percent = 0 }
        return UInt(round(percent))
    }
    
    @objc static func RMBTTimestamp(with date: Date) -> Int {
        return Int(date.timeIntervalSince1970) * 1000
    }
    
    // Replaces $lang in template with de if current local is german, en otherwise
    static func RMBTLocalize(urlString: String) -> String {
        if urlString.range(of: "$lang") != nil {
            var lang = RMBTHelpers.RMBTPreferredLanguage()
            if (!(lang == "de" || lang == "en")) {
                lang = "en"
            }
            return urlString.replacingOccurrences(of: "$lang", with: lang)
        } else {
            return urlString
        }
    }
    
    // Format a number to two significant digits. See https://trac.rtr.at/iosrtrnetztest/ticket/17
    @objc static func RMBTFormatNumber(_ number: NSNumber) -> String? {
        return formatter.string(from: number)
    }

    // Normalize hexadecimal identifier, i.e. 0:1:c -> 00:01:0c
    @objc static func RMBTReformatHexIdentifier(_ identifier: String) -> String {
        var tmp: [String] = []
        let components = identifier.components(separatedBy: ":")
        for c in components {
            if (c.count == 0) {
                tmp.append("00")
            } else if (c.count == 1) {
                tmp.append("0\(c)")
            } else {
                tmp.append(c)
            }
        }
        return tmp.joined(separator: ":")
    }

    // Returns bundle name from Info.plist (i.e. RTR-NetTest or RTR-Netztest)
    @objc static func RMBTAppTitle() -> String {
        return appName;
    }

    static func RMBTMillisecondsString(with nanos: Int64, withMS: Bool) -> String {
        let ms = NSNumber(value: Double(nanos) * 1.0e-6)
        guard let string = RMBTFormatNumber(ms) else { return ""}
        if (withMS) {
            return "\(string) ms"
        }
        return string
    }
    
    static func RMBTPingClassification(with nanos: Int64) -> Int {
        let ms = Double(nanos) * 1.0e-6
        if ms <= 10.0 {
            return 4
        } else if ms <= 25.0 {
            return 3
        } else if ms <= 75 {
            return 2
        } else {
            return 1
        }
    }
    
    static func RMBTUpClassification(with speed: Double) -> Int {
        if speed >= 50000 {
            return 4
        } else if speed >= 5000 {
            return 3
        } else if speed >= 2500 {
            return 2
        } else {
            return 1
        }
    }
    
    static func RMBTDownClassification(with speed: Double) -> Int {
        if speed >= 100000 {
            return 4
        } else if speed >= 1000 {
            return 3
        } else if speed >= 5000 {
            return 2
        } else {
            return 1
        }
    }

    @objc static func RMBTSecondsString(with nanos: Int64) -> String {
        return String(format: "%f s", Double(nanos) * 1.0e-9)
    }

    @objc static func RMBTCurrentNanos() -> UInt64 {
        var now = mach_absolute_time()
        now *= UInt64(mechTimebaseInfo.numer)
        now /= UInt64(mechTimebaseInfo.denom)
        return now
    }

    // Returns a string containing git commit, branch and commit count from Info.plist fields
    // written by the build script
    @objc static func RMBTBuildInfoString() -> String {
        return buildInfo
    }

    @objc static func RMBTBuildDateString() -> String {
        return buildDate
    }
}

extension fd_set {

/**
     Replacement for FD_ZERO macro.
     
     - Parameter set: A pointer to a fd_set structure.
     
     - Returns: The set that is opinted at is filled with all zero's.
     */
    
    public static func fdZero(_ set: inout fd_set) {
        set.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }
    
    
    /**
     Replacement for FD_SET macro
     
     - Parameter fd: A file descriptor that offsets the bit to be set to 1 in the fd_set pointed at by 'set'.
     - Parameter set: A pointer to a fd_set structure.
     
     - Returns: The given set is updated in place, with the bit at offset 'fd' set to 1.
     
     - Note: If you receive an EXC_BAD_INSTRUCTION at the mask statement, then most likely the socket was already closed.
     */
    
    public static func fdSet(_ fd: Int32, set: inout fd_set) {
        let intOffset: Int32 = Int32(fd / 32)
        let bitOffset: Int32 = Int32(fd % 32)
        let mask: Int32 = 1 << bitOffset
        switch intOffset {
        case 0: set.fds_bits.0 = set.fds_bits.0 | mask
        case 1: set.fds_bits.1 = set.fds_bits.1 | mask
        case 2: set.fds_bits.2 = set.fds_bits.2 | mask
        case 3: set.fds_bits.3 = set.fds_bits.3 | mask
        case 4: set.fds_bits.4 = set.fds_bits.4 | mask
        case 5: set.fds_bits.5 = set.fds_bits.5 | mask
        case 6: set.fds_bits.6 = set.fds_bits.6 | mask
        case 7: set.fds_bits.7 = set.fds_bits.7 | mask
        case 8: set.fds_bits.8 = set.fds_bits.8 | mask
        case 9: set.fds_bits.9 = set.fds_bits.9 | mask
        case 10: set.fds_bits.10 = set.fds_bits.10 | mask
        case 11: set.fds_bits.11 = set.fds_bits.11 | mask
        case 12: set.fds_bits.12 = set.fds_bits.12 | mask
        case 13: set.fds_bits.13 = set.fds_bits.13 | mask
        case 14: set.fds_bits.14 = set.fds_bits.14 | mask
        case 15: set.fds_bits.15 = set.fds_bits.15 | mask
        case 16: set.fds_bits.16 = set.fds_bits.16 | mask
        case 17: set.fds_bits.17 = set.fds_bits.17 | mask
        case 18: set.fds_bits.18 = set.fds_bits.18 | mask
        case 19: set.fds_bits.19 = set.fds_bits.19 | mask
        case 20: set.fds_bits.20 = set.fds_bits.20 | mask
        case 21: set.fds_bits.21 = set.fds_bits.21 | mask
        case 22: set.fds_bits.22 = set.fds_bits.22 | mask
        case 23: set.fds_bits.23 = set.fds_bits.23 | mask
        case 24: set.fds_bits.24 = set.fds_bits.24 | mask
        case 25: set.fds_bits.25 = set.fds_bits.25 | mask
        case 26: set.fds_bits.26 = set.fds_bits.26 | mask
        case 27: set.fds_bits.27 = set.fds_bits.27 | mask
        case 28: set.fds_bits.28 = set.fds_bits.28 | mask
        case 29: set.fds_bits.29 = set.fds_bits.29 | mask
        case 30: set.fds_bits.30 = set.fds_bits.30 | mask
        case 31: set.fds_bits.31 = set.fds_bits.31 | mask
        default: break
        }
    }
    
    
    /**
     Replacement for FD_CLR macro
    
     - Parameter fd: A file descriptor that offsets the bit to be cleared in the fd_set pointed at by 'set'.
     - Parameter set: A pointer to a fd_set structure.
    
     - Returns: The given set is updated in place, with the bit at offset 'fd' cleared to 0.
     */

    public static func fdClr(_ fd: Int32, set: inout fd_set) {
        let intOffset: Int32 = Int32(fd / 32)
        let bitOffset: Int32 = fd % 32
        let mask: Int32 = ~(1 << bitOffset)
        switch intOffset {
        case 0: set.fds_bits.0 = set.fds_bits.0 & mask
        case 1: set.fds_bits.1 = set.fds_bits.1 & mask
        case 2: set.fds_bits.2 = set.fds_bits.2 & mask
        case 3: set.fds_bits.3 = set.fds_bits.3 & mask
        case 4: set.fds_bits.4 = set.fds_bits.4 & mask
        case 5: set.fds_bits.5 = set.fds_bits.5 & mask
        case 6: set.fds_bits.6 = set.fds_bits.6 & mask
        case 7: set.fds_bits.7 = set.fds_bits.7 & mask
        case 8: set.fds_bits.8 = set.fds_bits.8 & mask
        case 9: set.fds_bits.9 = set.fds_bits.9 & mask
        case 10: set.fds_bits.10 = set.fds_bits.10 & mask
        case 11: set.fds_bits.11 = set.fds_bits.11 & mask
        case 12: set.fds_bits.12 = set.fds_bits.12 & mask
        case 13: set.fds_bits.13 = set.fds_bits.13 & mask
        case 14: set.fds_bits.14 = set.fds_bits.14 & mask
        case 15: set.fds_bits.15 = set.fds_bits.15 & mask
        case 16: set.fds_bits.16 = set.fds_bits.16 & mask
        case 17: set.fds_bits.17 = set.fds_bits.17 & mask
        case 18: set.fds_bits.18 = set.fds_bits.18 & mask
        case 19: set.fds_bits.19 = set.fds_bits.19 & mask
        case 20: set.fds_bits.20 = set.fds_bits.20 & mask
        case 21: set.fds_bits.21 = set.fds_bits.21 & mask
        case 22: set.fds_bits.22 = set.fds_bits.22 & mask
        case 23: set.fds_bits.23 = set.fds_bits.23 & mask
        case 24: set.fds_bits.24 = set.fds_bits.24 & mask
        case 25: set.fds_bits.25 = set.fds_bits.25 & mask
        case 26: set.fds_bits.26 = set.fds_bits.26 & mask
        case 27: set.fds_bits.27 = set.fds_bits.27 & mask
        case 28: set.fds_bits.28 = set.fds_bits.28 & mask
        case 29: set.fds_bits.29 = set.fds_bits.29 & mask
        case 30: set.fds_bits.30 = set.fds_bits.30 & mask
        case 31: set.fds_bits.31 = set.fds_bits.31 & mask
        default: break
        }
    }
    
    
    /**
    Replacement for FD_ISSET macro
    
     - Parameter fd: A file descriptor that offsets the bit to be tested in the fd_set pointed at by 'set'.
     - Parameter set: A pointer to a fd_set structure.
    
     - Returns: 'true' if the bit at offset 'fd' is 1, 'false' otherwise.
     */

    public static func fdIsSet(_ fd: Int32, set: inout fd_set) -> Bool {
        let intOffset: Int32 = Int32(fd / 32)
        let bitOffset: Int32 = fd % 32
        let mask: Int32 = 1 << bitOffset
        switch intOffset {
        case 0: return set.fds_bits.0 & mask != 0
        case 1: return set.fds_bits.1 & mask != 0
        case 2: return set.fds_bits.2 & mask != 0
        case 3: return set.fds_bits.3 & mask != 0
        case 4: return set.fds_bits.4 & mask != 0
        case 5: return set.fds_bits.5 & mask != 0
        case 6: return set.fds_bits.6 & mask != 0
        case 7: return set.fds_bits.7 & mask != 0
        case 8: return set.fds_bits.8 & mask != 0
        case 9: return set.fds_bits.9 & mask != 0
        case 10: return set.fds_bits.10 & mask != 0
        case 11: return set.fds_bits.11 & mask != 0
        case 12: return set.fds_bits.12 & mask != 0
        case 13: return set.fds_bits.13 & mask != 0
        case 14: return set.fds_bits.14 & mask != 0
        case 15: return set.fds_bits.15 & mask != 0
        case 16: return set.fds_bits.16 & mask != 0
        case 17: return set.fds_bits.17 & mask != 0
        case 18: return set.fds_bits.18 & mask != 0
        case 19: return set.fds_bits.19 & mask != 0
        case 20: return set.fds_bits.20 & mask != 0
        case 21: return set.fds_bits.21 & mask != 0
        case 22: return set.fds_bits.22 & mask != 0
        case 23: return set.fds_bits.23 & mask != 0
        case 24: return set.fds_bits.24 & mask != 0
        case 25: return set.fds_bits.25 & mask != 0
        case 26: return set.fds_bits.26 & mask != 0
        case 27: return set.fds_bits.27 & mask != 0
        case 28: return set.fds_bits.28 & mask != 0
        case 29: return set.fds_bits.29 & mask != 0
        case 30: return set.fds_bits.30 & mask != 0
        case 31: return set.fds_bits.31 & mask != 0
        default: return false
        }

    }
}
