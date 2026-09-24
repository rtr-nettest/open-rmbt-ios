import CoreLocation

enum CoverageButtonGate {
    /// Single source of truth for whether a location fix is accurate enough to begin / stay ready.
    /// Both the readiness GPS row (`NetworkCoverageViewModel.makeGpsReadiness`) and the start gate
    /// (`canStart` / `isReadyToBegin`) call this, so the displayed "OK" and the ability to actually start
    /// can never disagree. Raw comparison (matching Android) — do NOT round here or in callers, or a fix a
    /// fraction over the limit reads as "OK/green" while the start refuses to begin.
    static func isAccuracyAcceptable(_ accuracy: CLLocationAccuracy?, minAccuracy: CLLocationAccuracy) -> Bool {
        guard let accuracy, accuracy >= 0 else { return false }
        return accuracy <= minAccuracy
    }

    static func canStart(
        accuracy: CLLocationAccuracy?,
        networkType: RMBTNetworkType?,
        minAccuracy: CLLocationAccuracy
    ) -> Bool {
        isAccuracyAcceptable(accuracy, minAccuracy: minAccuracy) && networkType != .wifi
    }
}
