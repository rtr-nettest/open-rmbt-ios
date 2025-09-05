//
//  Fence.swift
//  RMBT
//
//  Created by Jiri Urbasek on 12/12/24.
//  Copyright 2024 appscape gmbh. All rights reserved.
//

import CoreLocation
import SwiftUI
import CoreTelephony

struct Fence: Identifiable, Hashable {
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

extension Fence {
    static let mockFences: [Fence] = [
        .init(
            startingLocation: CLLocation(
                latitude: 49.74805411063806,
                longitude: 13.37696845562318
            ),
            dateEntered: .init(timeIntervalSince1970: 1734526653),
            technology: CTRadioAccessTechnologyHSDPA,
            pings: [.init(result: .interval(.milliseconds(122)), timestamp: .init(timeIntervalSince1970: 1734526653))]
        ),
        .init(
            startingLocation: CLLocation(
                latitude: 49.747849194587204,
                longitude: 13.376917714305671
            ),
            dateEntered: .init(timeIntervalSince1970: 1734526656),
            technology: CTRadioAccessTechnologyLTE,
            pings: [.init(result: .interval(.milliseconds(84)), timestamp: .init(timeIntervalSince1970: 1734526656))]
        ),
        .init(
            startingLocation: CLLocation(
                latitude: 49.746123456789,
                longitude: 13.378456789012
            ),
            dateEntered: .init(timeIntervalSince1970: 1734526700),
            technology: CTRadioAccessTechnologyNR,
            pings: [.init(result: .interval(.milliseconds(45)), timestamp: .init(timeIntervalSince1970: 1734526700))]
        ),
        .init(
            startingLocation: CLLocation(
                latitude: 49.749876543210,
                longitude: 13.375123456789
            ),
            dateEntered: .init(timeIntervalSince1970: 1734526750),
            technology: CTRadioAccessTechnologyWCDMA,
            pings: [.init(result: .interval(.milliseconds(156)), timestamp: .init(timeIntervalSince1970: 1734526750))]
        )
    ]
    
    var averagePing: Int? {
        let pingsDurations = pings.compactMap(\.interval)
        if pingsDurations.isEmpty { return nil }
        return Int(pingsDurations.map(\.milliseconds).average)
    }
    
    var significantTechnology: String? {
        technologies.last
    }
    
    var coordinate: CLLocationCoordinate2D {
        startingLocation.coordinate
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
