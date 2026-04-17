//
//  FenceFactory.swift
//  RMBTTests
//

import CoreLocation
@testable import RMBT

func makeFence(
    lat: CLLocationDegrees = Double.random(in: -90...90),
    lon: CLLocationDegrees = Double.random(in: -180...180),
    altitude: CLLocationDistance = Double.random(in: 0...1000),
    horizontalAccuracy: CLLocationAccuracy = Double.random(in: 1...50),
    verticalAccuracy: CLLocationAccuracy = Double.random(in: -1...20),
    course: CLLocationDirection = -1,
    speed: CLLocationSpeed = -1,
    dateEntered: Date = Date(timeIntervalSinceReferenceDate: TimeInterval.random(in: 0...10000)),
    technology: String? = [nil, "3G", "4G", "5G", "LTE"].randomElement() ?? nil,
    pings: [PingResult] = [],
    radiusMeters: CLLocationDistance = Double.random(in: 1...100),
    sessionUUID: String? = nil,
    exitedAt: Date? = nil
) -> Fence {
    var fence = Fence(
        startingLocation: CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course,
            speed: speed,
            timestamp: dateEntered
        ),
        dateEntered: dateEntered,
        technology: technology,
        pings: pings,
        radiusMeters: radiusMeters,
        sessionUUID: sessionUUID
    )
    if let exitedAt {
        fence.exit(at: exitedAt)
    }
    return fence
}
