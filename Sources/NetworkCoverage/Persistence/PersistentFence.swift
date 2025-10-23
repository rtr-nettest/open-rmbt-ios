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

    init(from fence: Fence) {
        self.timestamp = UInt64(fence.dateEntered.timeIntervalSince1970 * 1_000_000) // microseconds
        self.latitude = fence.startingLocation.coordinate.latitude
        self.longitude = fence.startingLocation.coordinate.longitude
        self.avgPingMilliseconds = fence.averagePing
        self.technology = fence.significantTechnology
        if let dateExited = fence.dateExited {
            self.exitTimestamp = UInt64(dateExited.timeIntervalSince1970 * 1_000_000)
        }
        self.radiusMeters = fence.radiusMeters
    }

    init(
        timestamp: UInt64,
        latitude: Double,
        longitude: Double,
        avgPingMilliseconds: Int?,
        technology: String?,
        exitTimestamp: UInt64? = nil,
        radiusMeters: CLLocationDistance
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.avgPingMilliseconds = avgPingMilliseconds
        self.technology = technology
        self.exitTimestamp = exitTimestamp
        self.radiusMeters = radiusMeters
    }
}

@Model
final class PersistentCoverageSession {
    // Unique when non-nil; SwiftData doesn't support conditional uniqueness, so we rely on app logic.
    @Attribute(.unique) var testUUID: String?
    var loopUUID: String?
    var startedAt: UInt64
    var anchorAt: UInt64?
    var finalizedAt: UInt64?
    @Relationship(deleteRule: .cascade) var fences: [PersistentFence] = []

    init(testUUID: String? = nil, loopUUID: String? = nil, startedAt: UInt64, anchorAt: UInt64? = nil, finalizedAt: UInt64? = nil) {
        self.testUUID = testUUID
        self.loopUUID = loopUUID
        self.startedAt = startedAt
        self.anchorAt = anchorAt
        self.finalizedAt = finalizedAt
    }
}
