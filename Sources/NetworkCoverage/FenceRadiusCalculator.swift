//
//  FenceRadiusCalculator.swift
//  RMBT
//
//  Created on 19.03.2026.
//  Copyright 2026 appscape gmbh. All rights reserved.
//

import CoreLocation
import Foundation

struct FenceRadiusCalculator {
    let minimumRadius: CLLocationDistance

    func radius(for location: CLLocation) -> CLLocationDistance {
        let horizontalAccuracy = location.horizontalAccuracy
        let clampedAccuracy = horizontalAccuracy.isFinite ? max(0, horizontalAccuracy) : 0
        let gpsRadius = 10 + (2 * clampedAccuracy)

        let speed = location.speed
        let speedRadius = speed.isFinite ? max(0, speed) : 0

        return max(minimumRadius, gpsRadius, speedRadius)
    }
}
