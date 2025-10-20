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
    var testUUID: String
    // Optional exit timestamp in microseconds since epoch, used to compute duration_ms on resend
    var exitTimestamp: UInt64?
    var radiusMeters: CLLocationDistance

    init(from fence: Fence, testUUID: String) {
        self.timestamp = UInt64(fence.dateEntered.timeIntervalSince1970 * 1_000_000) // microseconds
        self.latitude = fence.startingLocation.coordinate.latitude
        self.longitude = fence.startingLocation.coordinate.longitude
        self.avgPingMilliseconds = fence.averagePing
        self.technology = fence.significantTechnology
        self.testUUID = testUUID
        if let dateExited = fence.dateExited {
            self.exitTimestamp = UInt64(dateExited.timeIntervalSince1970 * 1_000_000)
        }
        self.radiusMeters = fence.radiusMeters
    }

    init(
        testUUID: String,
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
        self.testUUID = testUUID
        self.exitTimestamp = exitTimestamp
        self.radiusMeters = radiusMeters
    }
}

@Model
final class PersistentCoverageSession {
    @Attribute(.unique) var testUUID: String
    var startedAt: UInt64
    var finalizedAt: UInt64?

    init(testUUID: String, startedAt: UInt64, finalizedAt: UInt64? = nil) {
        self.testUUID = testUUID
        self.startedAt = startedAt
        self.finalizedAt = finalizedAt
    }
}
