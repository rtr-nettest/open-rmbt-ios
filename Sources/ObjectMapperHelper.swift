/*****************************************************************************************************
 * Copyright 2016 SPECURE GmbH
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
import ObjectMapper

/// Reads a JSON number, or a numeric string (the control server sends e.g. `"10"`), as `Double`.
struct NumberOrNumericStringTransform: TransformType {
    func transformFromJSON(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    func transformToJSON(_ value: Double?) -> Double? { value }
}

///
let UInt64NSNumberTransformOf = TransformOf<UInt64, NSNumber>(fromJSON: { $0?.uint64Value }, toJSON: { $0.map { NSNumber(value: $0) } })

let DateStringTransformOf = TransformOf<Date, String>(fromJSON: {
    let defaultDateFormatter = DateFormatter()
//    defaultDateFormatter.locale = NSLocale.current
    defaultDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    if let date = $0 {
        return defaultDateFormatter.date(from: date)
    }
    else {
        return Date()
    }
}, toJSON: {
    let defaultDateFormatter = DateFormatter()
//    defaultDateFormatter.locale = NSLocale.current
    defaultDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    if let date = $0 {
        return defaultDateFormatter.string(from: date)
    }
    else {
        return ""
    }
})

let DateStringTimezoneTransformOf = TransformOf<Date, String>(fromJSON: {
    let defaultDateFormatter = DateFormatter()
//    defaultDateFormatter.locale = NSLocale.current
    defaultDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    if let date = $0 {
        return defaultDateFormatter.date(from: date)
    }
    else {
        return Date()
    }
}, toJSON: {
    let defaultDateFormatter = DateFormatter()
//    defaultDateFormatter.locale = NSLocale.current
    defaultDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    if let date = $0 {
        return defaultDateFormatter.string(from: date)
    }
    else {
        return ""
    }
})

let IntDateStringTransformOf = TransformOf<Int, String>(fromJSON: {
    let defaultDateFormatter = DateFormatter()
    defaultDateFormatter.locale = Locale(identifier: "en_US_POSIX")
    defaultDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
    if let date = $0 {
        return Int(defaultDateFormatter.date(from: date)?.timeIntervalSince1970 ?? 0.0)
    }
    else {
        return Int(Date().timeIntervalSince1970)
    }
}, toJSON: {
    let defaultDateFormatter = DateFormatter()
    defaultDateFormatter.locale = Locale(identifier: "en_US_POSIX")
    defaultDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
    if let timestamp = $0 {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return defaultDateFormatter.string(from: date)
    }
    else {
        return ""
    }
})

let DateMilisecondsTransformOf = TransformOf<Date, Int64>(fromJSON: {
    if let milliseconds = $0 {
        let seconds: TimeInterval = Double(milliseconds) / 1000.0
        return Date(timeIntervalSince1970: seconds)
    }
    return nil
}, toJSON: {
    if let date = $0 {
        return Int64(date.timeIntervalSince1970) * 1000
    }
    else {
        return 0
    }
})
