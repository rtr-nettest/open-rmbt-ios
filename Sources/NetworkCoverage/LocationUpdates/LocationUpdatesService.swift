//
//  LocationUpdatesService.swift
//  RMBT
//
//  Created by Jiri Urbasek on 02.04.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import CoreLocation

@rethrows protocol LocationsAsyncSequence: AsyncSequence where Element == LocationUpdate { }
protocol LocationUpdatesService<Sequence> {
    associatedtype Sequence: LocationsAsyncSequence

    func locations() -> Sequence
}

struct RealLocationUpdatesService: LocationUpdatesService {
    let now: () -> Date
    let canReportLocations: () -> Bool

    func locations() -> some LocationsAsyncSequence {
        CLLocationUpdate
            .liveUpdates(.fitness)
            .filter { _ in canReportLocations() }
            .compactMap(\.location)
            .map { LocationUpdate(location: $0, timestamp: now()) }
    }
}

extension AsyncMapSequence: LocationsAsyncSequence where Element == LocationUpdate {}
