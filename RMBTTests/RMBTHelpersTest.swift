//
//  RMBTHelpersTest.swift
//  RMBTTest
//
//  Created by Sergey Glushchenko on 28.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import XCTest
@testable import RMBT

class RMBTHelpersTest: XCTestCase {

    func testBSSIDConversion() {
        XCTAssertEqual(RMBTReformatHexIdentifier("0:0:fb:1"), "00:00:fb:01")
        XCTAssertEqual(RMBTReformatHexIdentifier("hello"), "hello")
        XCTAssertEqual(RMBTReformatHexIdentifier("::FF:1"), "00:00:FF:01")
    }

    func testChomp() {
        XCTAssertEqual(RMBTHelpers.RMBTChomp("\n\ntest\n "), "\n\ntest\n ")
        XCTAssertEqual(RMBTHelpers.RMBTChomp("\n\ntest\n\r\n"), "\n\ntest")
        XCTAssertEqual(RMBTHelpers.RMBTChomp(""), "")
        XCTAssertEqual(RMBTHelpers.RMBTChomp("\r\n"), "")
        XCTAssertEqual(RMBTHelpers.RMBTChomp("\n"), "")
    }

    func testPercent() {
        XCTAssertEqual(RMBTHelpers.RMBTPercent(-1, -100), 1)
        XCTAssertEqual(RMBTHelpers.RMBTPercent(100, 0), 0)
        XCTAssertEqual(RMBTHelpers.RMBTPercent(3, 9), 33)
    }

    func testResolveNetworkLabels_whenWifiSSIDMissing_thenShowsWLANOnly() {
        let resolved = RMBTIntroPortraitView.resolveNetworkLabels(
            networkType: .wifi,
            networkName: nil,
            networkDescription: "WLAN"
        )

        XCTAssertEqual(resolved.networkName, "WLAN")
        XCTAssertNil(resolved.networkDescription)
    }

    func testResolveNetworkLabels_whenWifiSSIDAvailable_thenShowsSSIDAndWLAN() {
        let resolved = RMBTIntroPortraitView.resolveNetworkLabels(
            networkType: .wifi,
            networkName: "DZ SlowInternet",
            networkDescription: "WLAN"
        )

        XCTAssertEqual(resolved.networkName, "DZ SlowInternet")
        XCTAssertEqual(resolved.networkDescription, "WLAN")
    }

    func testResolveNetworkLabels_whenCellular_thenShowsTechnologyOnly() {
        let resolved = RMBTIntroPortraitView.resolveNetworkLabels(
            networkType: .cellular,
            networkName: "Carrier",
            networkDescription: "4G/LTE"
        )

        XCTAssertEqual(resolved.networkName, "4G/LTE")
        XCTAssertNil(resolved.networkDescription)
    }

    // MARK: - Download speed classification (RTR FAQ thresholds, in kbps)

    func testDownClassification_whenSpeedAtOrAbove100Mbps_thenReturnsDarkGreen() {
        XCTAssertEqual(RMBTHelpers.RMBTDownClassification(with: 100_000), 4)
        XCTAssertEqual(RMBTHelpers.RMBTDownClassification(with: 250_000), 4)
    }

    func testDownClassification_whenSpeedBetween10And100Mbps_thenReturnsGreen() {
        XCTAssertEqual(RMBTHelpers.RMBTDownClassification(with: 99_999), 3)
        XCTAssertEqual(RMBTHelpers.RMBTDownClassification(with: 30_000), 3)
        XCTAssertEqual(RMBTHelpers.RMBTDownClassification(with: 10_000), 3)
    }

    func testDownClassification_whenSpeedBetween5And10Mbps_thenReturnsYellow() {
        XCTAssertEqual(RMBTHelpers.RMBTDownClassification(with: 9_999), 2)
        XCTAssertEqual(RMBTHelpers.RMBTDownClassification(with: 7_500), 2)
        XCTAssertEqual(RMBTHelpers.RMBTDownClassification(with: 5_000), 2)
    }

    func testDownClassification_whenSpeedBelow5Mbps_thenReturnsRed() {
        XCTAssertEqual(RMBTHelpers.RMBTDownClassification(with: 4_999), 1)
        XCTAssertEqual(RMBTHelpers.RMBTDownClassification(with: 1_000), 1)
        XCTAssertEqual(RMBTHelpers.RMBTDownClassification(with: 0), 1)
    }

    // MARK: - Upload speed classification (RTR FAQ thresholds, in kbps)

    func testUpClassification_whenSpeedAtOrAbove50Mbps_thenReturnsDarkGreen() {
        XCTAssertEqual(RMBTHelpers.RMBTUpClassification(with: 50_000), 4)
        XCTAssertEqual(RMBTHelpers.RMBTUpClassification(with: 120_000), 4)
    }

    func testUpClassification_whenSpeedBetween5And50Mbps_thenReturnsGreen() {
        XCTAssertEqual(RMBTHelpers.RMBTUpClassification(with: 49_999), 3)
        XCTAssertEqual(RMBTHelpers.RMBTUpClassification(with: 10_000), 3)
        XCTAssertEqual(RMBTHelpers.RMBTUpClassification(with: 5_000), 3)
    }

    func testUpClassification_whenSpeedBetween2_5And5Mbps_thenReturnsYellow() {
        XCTAssertEqual(RMBTHelpers.RMBTUpClassification(with: 4_999), 2)
        XCTAssertEqual(RMBTHelpers.RMBTUpClassification(with: 3_000), 2)
        XCTAssertEqual(RMBTHelpers.RMBTUpClassification(with: 2_500), 2)
    }

    func testUpClassification_whenSpeedBelow2_5Mbps_thenReturnsRed() {
        XCTAssertEqual(RMBTHelpers.RMBTUpClassification(with: 2_499), 1)
        XCTAssertEqual(RMBTHelpers.RMBTUpClassification(with: 500), 1)
        XCTAssertEqual(RMBTHelpers.RMBTUpClassification(with: 0), 1)
    }

    // MARK: - Ping classification (RTR FAQ thresholds, in ms; helper takes nanoseconds)

    func testPingClassification_whenLatencyAtOrBelow10ms_thenReturnsDarkGreen() {
        XCTAssertEqual(RMBTHelpers.RMBTPingClassification(with: ms(0)), 4)
        XCTAssertEqual(RMBTHelpers.RMBTPingClassification(with: ms(5)), 4)
        XCTAssertEqual(RMBTHelpers.RMBTPingClassification(with: ms(10)), 4)
    }

    func testPingClassification_whenLatencyBetween10And25ms_thenReturnsGreen() {
        XCTAssertEqual(RMBTHelpers.RMBTPingClassification(with: ms(11)), 3)
        XCTAssertEqual(RMBTHelpers.RMBTPingClassification(with: ms(20)), 3)
        XCTAssertEqual(RMBTHelpers.RMBTPingClassification(with: ms(25)), 3)
    }

    func testPingClassification_whenLatencyBetween25And75ms_thenReturnsYellow() {
        XCTAssertEqual(RMBTHelpers.RMBTPingClassification(with: ms(26)), 2)
        XCTAssertEqual(RMBTHelpers.RMBTPingClassification(with: ms(50)), 2)
        XCTAssertEqual(RMBTHelpers.RMBTPingClassification(with: ms(75)), 2)
    }

    func testPingClassification_whenLatencyAbove75ms_thenReturnsRed() {
        XCTAssertEqual(RMBTHelpers.RMBTPingClassification(with: ms(76)), 1)
        XCTAssertEqual(RMBTHelpers.RMBTPingClassification(with: ms(500)), 1)
    }

    private func ms(_ milliseconds: Int64) -> Int64 {
        milliseconds * 1_000_000
    }
}
