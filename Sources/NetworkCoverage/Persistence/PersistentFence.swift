import Foundation
import SwiftData
import CoreLocation

@Model
final class PersistentFence {
    var timestamp: UInt64
    var latitude: Double
    var longitude: Double
    var avgPingMilliseconds: Int?
    var technology: String?
    // Optional exit timestamp in microseconds since epoch, used to compute duration_ms on resend
    var exitTimestamp: UInt64?
    var radiusMeters: CLLocationDistance
    // Location extras submitted alongside the coordinate; nil when the source reading had no
    // valid value, so resent fences carry the same data the live submission would have.
    var accuracy: Double?
    var altitude: Double?
    var bearing: Double?
    var speed: Double?

    init(from fence: Fence) {
        let location = fence.startingLocation
        self.timestamp = UInt64(fence.dateEntered.timeIntervalSince1970 * 1_000_000) // microseconds
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.avgPingMilliseconds = fence.averagePing
        self.technology = fence.significantTechnology
        if let dateExited = fence.dateExited {
            self.exitTimestamp = UInt64(dateExited.timeIntervalSince1970 * 1_000_000)
        }
        self.radiusMeters = fence.radiusMeters
        self.accuracy = location.horizontalAccuracy > 0 ? location.horizontalAccuracy : nil
        self.altitude = location.verticalAccuracy >= 0 ? location.altitude : nil
        self.bearing = location.course >= 0 ? location.course : nil
        self.speed = location.speed >= 0 ? location.speed : nil
    }

    init(
        timestamp: UInt64,
        latitude: Double,
        longitude: Double,
        avgPingMilliseconds: Int?,
        technology: String?,
        exitTimestamp: UInt64? = nil,
        radiusMeters: CLLocationDistance,
        accuracy: Double? = nil,
        altitude: Double? = nil,
        bearing: Double? = nil,
        speed: Double? = nil
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.avgPingMilliseconds = avgPingMilliseconds
        self.technology = technology
        self.exitTimestamp = exitTimestamp
        self.radiusMeters = radiusMeters
        self.accuracy = accuracy
        self.altitude = altitude
        self.bearing = bearing
        self.speed = speed
    }
}

@Model
final class PersistentCoverageSession {
    // Unique when non-nil; SwiftData doesn't support conditional uniqueness, so we rely on app logic.
    @Attribute(.unique) var testUUID: String?
    var startedAt: UInt64
    var anchorAt: UInt64?
    var finalizedAt: UInt64?
    @Relationship(deleteRule: .cascade) var fences: [PersistentFence] = []

    init(testUUID: String? = nil, startedAt: UInt64, anchorAt: UInt64? = nil, finalizedAt: UInt64? = nil) {
        self.testUUID = testUUID
        self.startedAt = startedAt
        self.anchorAt = anchorAt
        self.finalizedAt = finalizedAt
    }
}
