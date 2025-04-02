//
//  LocationArea.swift
//  RMBT
//
//  Created by Jiri Urbasek on 12/12/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import CoreLocation

struct LocationArea: Identifiable, Hashable {
    private(set) var locations: [CLLocation]
    private(set) var pings: [PingResult]
    private(set) var technologies: [String]

    let startingLocation: CLLocation
    let id: UUID = UUID()
    let dateEntered: Date
    private(set) var dateExited: Date?

    init(startingLocation: CLLocation, dateEntered: Date, technology: String?, pings: [PingResult] = []) {
        self.dateEntered = dateEntered
        self.startingLocation = startingLocation
        self.locations = [startingLocation]
        self.pings = pings
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

    mutating func exit(at date: Date) {
        dateExited = date
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
        switch self.result {
        case .interval(let duration): duration
        case .error: nil
        }
    }
}
