import CoreLocation

enum CoverageButtonGate {
    static func canStart(
        accuracy: CLLocationAccuracy?,
        networkType: RMBTNetworkType?,
        minAccuracy: CLLocationAccuracy
    ) -> Bool {
        let acc = accuracy ?? -1
        let isAccuracyOK = acc >= 0 && acc <= minAccuracy
        let isWifi = networkType == .wifi
        return isAccuracyOK && !isWifi
    }
}
