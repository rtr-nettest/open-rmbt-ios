import Foundation
import SwiftData
import CoreLocation

@Model
final class PersistentLocationArea {
    var timestamp: UInt64
    var latitude: Double
    var longitude: Double
    var avgPingMilliseconds: Int?
    var technology: String?

    init(from area: LocationArea) {
        self.timestamp = UInt64(area.dateEntered.timeIntervalSince1970 * 1_000_000) // microseconds
        self.latitude = area.startingLocation.coordinate.latitude
        self.longitude = area.startingLocation.coordinate.longitude
        self.avgPingMilliseconds = area.averagePing
        self.technology = area.technologies.last
    }

    init(
        timestamp: UInt64,
        latitude: Double,
        longitude: Double,
        avgPingMilliseconds: Int?,
        technology: String?
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.avgPingMilliseconds = avgPingMilliseconds
        self.technology = technology
    }
}
