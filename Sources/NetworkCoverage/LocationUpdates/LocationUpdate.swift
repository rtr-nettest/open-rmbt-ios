//
//  LocationUpdate.swift
//  RMBT
//
//  Created by Jiri Urbasek on 02.04.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import CoreLocation

struct LocationUpdate: Hashable {
    let location: CLLocation
    let timestamp: Date
}
