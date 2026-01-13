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

}
