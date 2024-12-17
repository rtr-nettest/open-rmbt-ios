//
//  LocationArea.swift
//  RMBT
//
//  Created by Jiri Urbasek on 12/12/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import CoreLocation

struct LocationArea {
    private(set) var locations: [CLLocation]
    private(set) var pings: [PingResult]
    private(set) var technologies: [String]

    let startingLocation: CLLocation
    let id: UUID = UUID()
    let time: Date

    init(startingLocation: CLLocation, technology: String?, dateNow: () -> Date = Date.init) {
        time = dateNow()
        self.startingLocation = startingLocation
        self.locations = [startingLocation]
        self.pings = []
        technologies = technology.map { [$0] } ?? []
    }

    mutating func append(location: CLLocation) {
        locations.append(location)
    }

    mutating func append(ping: PingResult) {
        pings.append(ping)
    }

    mutating func append(technology: String) {
        technologies.append(technology)
    }
}

extension LocationArea {
    var averagePing: Int? {
        let pingsDurations = pings.compactMap(\.interval)
        if pingsDurations.isEmpty { return nil }
        return Int(pingsDurations.map(\.milliseconds).average)
    }
}

extension PingResult {
    var interval: Duration? {
        switch self {
        case .interval(let duration): duration
        case .error: nil
        }
    }
}
