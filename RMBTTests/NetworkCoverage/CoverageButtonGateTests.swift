import Testing
import CoreLocation
@testable import RMBT

// User story: docs/user-stories/network-coverage/start-button-availability.md
@Suite("CoverageButtonGate")
struct CoverageButtonGateTests {

    private let minAccuracy: CLLocationAccuracy = 15

    @Test("when_locationIsMissing_then_buttonCannotStart")
    func when_locationIsMissing_then_cannotStart() {
        #expect(makeSUT(accuracy: nil, networkType: .cellular) == false)
    }

    @Test(
        "when_accuracyIsNegative_then_buttonCannotStart",
        arguments: [-1.0, -100.0]
    )
    func when_accuracyIsNegative_then_cannotStart(accuracy: CLLocationAccuracy) {
        #expect(makeSUT(accuracy: accuracy, networkType: .cellular) == false)
    }

    @Test("when_accuracyExceedsThreshold_then_buttonCannotStart")
    func when_accuracyExceedsThreshold_then_cannotStart() {
        #expect(makeSUT(accuracy: 15.001, networkType: .cellular) == false)
    }

    @Test(
        "when_accuracyAtBoundaries_then_buttonCanStart",
        arguments: [0.0, 15.0]
    )
    func when_accuracyAtBoundaries_then_canStart(accuracy: CLLocationAccuracy) {
        #expect(makeSUT(accuracy: accuracy, networkType: .cellular) == true)
    }

    @Test(
        "when_accuracyIsGoodAndNotOnWifi_then_buttonCanStart",
        arguments: [
            RMBTNetworkType?.none,
            .some(.unknown),
            .some(.none),
            .some(.browser),
            .some(.cellular),
        ] as [RMBTNetworkType?]
    )
    func when_accuracyIsGoodAndNotOnWifi_then_canStart(networkType: RMBTNetworkType?) {
        #expect(makeSUT(accuracy: 5.0, networkType: networkType) == true)
    }

    @Test("when_onWifi_then_buttonCannotStart")
    func when_onWifi_then_cannotStart() {
        #expect(makeSUT(accuracy: 5.0, networkType: .wifi) == false)
    }

    @Test(
        "when_accuracyIsBad_then_buttonCannotStartRegardlessOfNetwork",
        arguments: [
            RMBTNetworkType.cellular,
            .wifi,
            .none,
            .unknown,
            .browser,
        ]
    )
    func when_accuracyIsBad_then_cannotStartRegardlessOfNetwork(networkType: RMBTNetworkType) {
        #expect(makeSUT(accuracy: 50.0, networkType: networkType) == false)
    }

    private func makeSUT(
        accuracy: CLLocationAccuracy?,
        networkType: RMBTNetworkType?
    ) -> Bool {
        CoverageButtonGate.canStart(
            accuracy: accuracy,
            networkType: networkType,
            minAccuracy: minAccuracy
        )
    }
}
