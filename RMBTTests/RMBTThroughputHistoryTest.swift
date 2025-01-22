//
//  RMBTThroughputHistoryTest.swift
//  RMBTTest
//
//  Created by Sergey Glushchenko on 28.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import XCTest
@testable import RMBT

class RMBTThroughputHistoryTest: XCTestCase {

    func testSpread() {
        // One block = 250ms
        let h = RMBTThroughputHistory(resolutionNanos: 250)

        XCTAssertEqual(h.totalThroughput.endNanos, 0)
        
        // Transfer 10 kilobit in one second
        h.addLength(1250, atNanos: 1000)
        
        // Assert correct total throughput
        XCTAssertEqual(h.totalThroughput.endNanos, 1000)
        XCTAssertEqual(h.totalThroughput.kilobitsPerSecond(), 10000000)

        // Assert correct period division
        XCTAssertEqual(h.periods.count, 4)
        
        // ..and bytes per period (note that 1250 isn't divisible by 4)
        for i in 0..<3 {
            XCTAssertTrue(h.periods[i].length == 312)
        }
        XCTAssertTrue(h.periods[3].length == 314)
    }

    func testBoundaries() {
        let h = RMBTThroughputHistory(resolutionNanos: 1000)
        XCTAssertEqual(h.lastFrozenPeriodIndex, -1)
        
        h.addLength(1050, atNanos: 1050)
        XCTAssertEqual(h.lastFrozenPeriodIndex, 0)

        h.addLength(150, atNanos: 1200)
        XCTAssertEqual(h.lastFrozenPeriodIndex, 0);
        XCTAssertEqual(h.periods.count, 2);
        XCTAssertEqual(h.totalThroughput.endNanos, 1200);
        XCTAssertEqual(h.periods.last?.endNanos ?? 0, 1200);
        
        h.addLength(800, atNanos: 2000)
        XCTAssertEqual(h.lastFrozenPeriodIndex, 0)
        XCTAssertEqual(h.periods.count, 2)
        
        XCTAssertTrue(h.periods[0].length == 1000);
        XCTAssertTrue(h.periods[1].length == 1000);
        
        h.addLength(1000, atNanos: 3000)
        XCTAssertEqual(h.lastFrozenPeriodIndex, 1)
        XCTAssertEqual(h.periods.count, 3);
        XCTAssertEqual(h.periods.last?.startNanos ?? 0, 2000)
        XCTAssertEqual(h.periods.last?.endNanos ?? 0, 3000)
        XCTAssertTrue(h.periods[2].length == 1000);
    }

    func testFreeze() {
        let h = RMBTThroughputHistory(resolutionNanos: 1000)
        h.addLength(1024, atNanos: 500)
        XCTAssertEqual(h.lastFrozenPeriodIndex, -1)
        XCTAssertEqual(h.totalThroughput.endNanos, 500)
        h.freeze()
        XCTAssertEqual(h.lastFrozenPeriodIndex, 0)
        XCTAssertEqual(h.periods.last?.endNanos ?? 0, 500)
    }

    func testSquash1() {
        let h = RMBTThroughputHistory(resolutionNanos: 1000)
        h.addLength(1000, atNanos: 500)
        h.addLength(1000, atNanos: 1000)
        
        h.addLength(1000, atNanos: 1500)
        h.addLength(1000, atNanos: 2000)
        
        h.addLength(1000, atNanos: 2500)
        h.addLength(1000, atNanos: 3000)
        
        h.freeze()
        
        XCTAssertEqual(h.periods.count, 3)
        h.squashLastPeriods(1)
        
        XCTAssertEqual(h.periods.count, 2);
        XCTAssertEqual(h.periods.last?.endNanos ?? 0, 3000)
        XCTAssertEqual(h.periods.last?.length ?? 0, 4000)
    }

    func testSquash2() {
        let h = RMBTThroughputHistory(resolutionNanos: 1000)
        h.addLength(1000, atNanos: 500)
        h.addLength(1000, atNanos: 1000)
        
        h.addLength(1000, atNanos: 1500)
        h.addLength(1000, atNanos: 2000)
        
        h.addLength(1000, atNanos: 2500)
        h.addLength(1000, atNanos: 3000)
        
        h.freeze()
        
        XCTAssertEqual(h.periods.count, 3)
        h.squashLastPeriods(2)

        XCTAssertEqual(h.periods.count, 1);
        XCTAssertEqual(h.periods.last?.endNanos ?? 0, 3000)
        XCTAssertEqual(h.periods.last?.length ?? 0, 6000)
    }

}
