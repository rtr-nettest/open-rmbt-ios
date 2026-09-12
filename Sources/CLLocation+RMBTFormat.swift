//
//  CLLocation+RMBTFormat.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 09.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import Foundation
import CoreLocation

/// Inferred origin of a `CLLocation`. iOS never exposes the provider, so we classify it (see
/// `CLLocation.rmbtSource`). The raw values match the backend / Android `provider` field.
enum RMBTLocationSource: String {
    case gps
    case network
}

extension CLLocation {
    /// Upper bound on vertical accuracy (metres) for a fix we treat as genuine GNSS ("gps").
    /// iOS fuses GNSS, Wi‑Fi and cell into one opaque `CLLocation` with no provider field, but the
    /// vertical accuracy betrays the source: real satellite fixes report small vertical accuracy
    /// (single/low double‑digit metres), whereas Wi‑Fi/cell (network) fixes report hundreds of
    /// metres or an invalid (negative) value — measured on device: network fixes ~840–920 m.
    /// Tunable; kept comfortably above real GNSS vertical accuracy yet far below network fixes.
    static let maxVerticalAccuracyForGPSFix: CLLocationAccuracy = 40

    /// Inferred source of this fix, from vertical accuracy (see `maxVerticalAccuracyForGPSFix`).
    var rmbtSource: RMBTLocationSource {
        (verticalAccuracy > 0 && verticalAccuracy <= Self.maxVerticalAccuracyForGPSFix) ? .gps : .network
    }

    /// True when this fix is inferred to come from the GNSS receiver rather than Wi‑Fi/cell.
    var isGenuineGPSFix: Bool { rmbtSource == .gps }
}

extension CLLocation {
    static var timestampFormatter: DateFormatter = {
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "HH:mm:ss"
        return timestampFormatter
    }()
    func rmbtFormattedString() -> String {
        var latSeconds = Int(round(fabs(self.coordinate.latitude * 3600)))
        let latDegrees = latSeconds / 3600
        latSeconds = latSeconds % 3600
        
        let latMinutes: CLLocationDegrees = Double(latSeconds) / 60.0
        
        var longSeconds = Int(round(fabs(self.coordinate.longitude * 3600)))
        let longDegrees = longSeconds / 3600
        longSeconds = longSeconds % 3600
        let longMinutes: CLLocationDegrees = Double(longSeconds) / 60.0
        
        let latDirection = (self.coordinate.latitude  >= 0) ? "N" : "S"
        let longDirection = (self.coordinate.longitude >= 0) ? "E" : "W"
        
        return String(format: "%@ %ld° %.3f' %@ %ld° %.3f' (+/- %.0fm)\n@%@", latDirection, Int(latDegrees), latMinutes, longDirection, Int(longDegrees), longMinutes, self.horizontalAccuracy, CLLocation.timestampFormatter.string(from: self.timestamp))
    }
    
    @objc func paramsDictionary() -> [String: Any] {
        return [
            "long": self.coordinate.longitude,
            "lat":  self.coordinate.latitude,
            "time": RMBTHelpers.RMBTTimestamp(with: self.timestamp),
            "accuracy": self.horizontalAccuracy,
            "altitude": self.altitude,
            "speed": (self.speed > 0.0 ? self.speed : 0.0),
            // Inferred fix source ("gps"/"network"); matches the backend/Android `provider` field.
            "provider": self.rmbtSource.rawValue
        ]
    }
}
