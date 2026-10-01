/*****************************************************************************************************
 * Copyright 2013 appscape gmbh
 * Copyright 2014-2016 SPECURE GmbH
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *****************************************************************************************************/

import Foundation
// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

let GAUGE_PARTS = 5.0
let LOG10_MAX = log10(250.0)

///
public func RMBTSpeedLogValue(_ kbps: Double) -> Double {
    var log: Double

    if kbps < 100 {
        log = 0
    } else {
        log = log10(Double(kbps) / 100.0) / GAUGE_PARTS
    }

    if (log > 1.0) {
        log = 1.0
    }
    
    if (log < 0.0) {
        log = 0.0
    }

    return log
}

/// for nkom
public func RMBTSpeedLogValue(_ kbps: Double, gaugeParts: Double, log10Max: Double) -> Double {
    let bps = kbps * 1_000

    if bps < 10_000 {
        return 0
    }

    return ((gaugeParts - log10Max) + log10(Double(bps) / 1e6)) / gaugeParts
}

///
/// Full-value formatter for expert mode: three decimals, no grouping, locale decimal separator
/// (e.g. "1297.987" / "1297,987"). Mirrors Android's `expertFormat()` = `DecimalFormat("####0.000")`.
private let RMBTSpeedExpertFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 3
    formatter.maximumFractionDigits = 3
    return formatter
}()

/// Formats a speed given in kbit/s as a Mbit/s string.
///
/// Rounding mirrors the Android client:
/// - `expertFullValue` (expert mode, final result only): the full value with three decimals.
/// - above 10 Mbit/s: the full number as an integer (e.g. 1298, not "1300" at two significant digits).
/// - up to 10 Mbit/s: two significant digits (e.g. "5.2").
public func RMBTSpeedMbpsString(_ kbps: Double, withMbps: Bool = true, expertFullValue: Bool = false) -> String {
    let mbps = kbps / 1000.0

    let speedValue: String
    if expertFullValue {
        guard let formatted = RMBTSpeedExpertFormatter.string(from: NSNumber(value: mbps)) else { return "-" }
        speedValue = formatted
    } else if mbps > 10 {
        speedValue = String(Int(mbps.rounded()))
    } else if let formatted = RMBTHelpers.RMBTFormatNumber(NSNumber(value: mbps)) {
        speedValue = formatted
    } else {
        return "-"
    }

    if withMbps {
        let localizedMps = NSLocalizedString("test.speed.unit", value: "Mbps", comment: "Speed suffix")

        return String(format: "%@ %@", speedValue, localizedMps)
    }

    return speedValue
}
