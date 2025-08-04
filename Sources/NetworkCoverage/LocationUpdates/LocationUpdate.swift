//
//  LocationUpdate.swift
//  RMBT
//
//  Created by Jiri Urbasek on 02.04.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import CoreLocation

struct LocationUpdate: Hashable, Identifiable {
    let id = UUID()
    let location: CLLocation
    let timestamp: Date
    
    var coordinate: CLLocationCoordinate2D {
        location.coordinate
    }
    
    var horizontalAccuracy: CLLocationAccuracy {
        location.horizontalAccuracy
    }
}
