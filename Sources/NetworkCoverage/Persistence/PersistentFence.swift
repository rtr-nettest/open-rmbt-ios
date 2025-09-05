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

    init(from fence: Fence, testUUID: String) {
        self.timestamp = UInt64(fence.dateEntered.timeIntervalSince1970 * 1_000_000) // microseconds
        self.latitude = fence.startingLocation.coordinate.latitude
        self.longitude = fence.startingLocation.coordinate.longitude
        self.avgPingMilliseconds = fence.averagePing
        self.technology = fence.significantTechnology
        self.testUUID = testUUID
    }

    init(
        testUUID: String,
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
        self.testUUID = testUUID
    }
}
