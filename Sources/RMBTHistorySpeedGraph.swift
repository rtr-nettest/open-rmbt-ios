//
//  RMBTHistorySpeedGraph.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 11.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

@objc class RMBTHistorySpeedGraph: NSObject {

    private(set) var throughputs: [RMBTThroughput] = []
    private(set) var points: [CGPoint] = []
    
    @objc(initWithResponse:)
    init(with response: [[String: Any]]) {
        var bytes: UInt64 = 0
        var t: UInt64 = 0
        throughputs = response.map({ entry in
            let end = UInt64(entry["time_elapsed"] as? Int ?? 0) * NSEC_PER_MSEC
            let deltaBytes = UInt64(entry["bytes_total"] as? Double ?? 0) - bytes
            
            let result = RMBTThroughput(length: deltaBytes, startNanos: t, endNanos: end)
            
            t = end
            bytes += deltaBytes
            return result
        })
        points = RMBTHistorySpeedGraph.createPoints(from: response)
    }
    
    override var description: String {
        return throughputs.map({ t in
            return "[\(RMBTHelpers.RMBTSecondsString(with: Int64(t.endNanos))) \(RMBTSpeedMbpsString(t.kilobitsPerSecond()))]"
        }).joined(separator: "-")
    }
    
    private static func createPoints(from items: [[String: Any]]) -> [CGPoint] {
        let dataItems = items.map(DataItem.init)
        var points: [CGPoint] = []

        let maxTimeEntry = dataItems.max { $0.timeElapsed < $1.timeElapsed }
        if let maxTimeEntry {
            let maxTime = maxTimeEntry.timeElapsed

            if let firstItem = dataItems.first {
                let firstItemProgress = (firstItem.timeElapsed / maxTime ) * 100

                if (firstItemProgress > 0) {
                    let firstItemYPos = RMBTHistorySpeedGraph.getYPos(bytesDiference: firstItem.bytesTotal, timeDifference: firstItem.timeElapsed)
                    points.append(CGPoint(x: 0, y: firstItemYPos))
                }
            }

            var previousTime: Double = 0
            var previousData: Double = 0

            for item in dataItems {
                let dataDifference = item.bytesTotal - previousData;
                let timeDifference = item.timeElapsed - previousTime;

                let x = item.timeElapsed / maxTime
                let y = RMBTHistorySpeedGraph.getYPos(bytesDiference: dataDifference, timeDifference: timeDifference)
                points.append(CGPoint(x: x, y: y))

                previousData = item.bytesTotal
                previousTime = item.timeElapsed
            }
        }
        return points
    }
    
    private static func getYPos(bytesDiference: Double, timeDifference: Double) -> Double {
        toLog(bytesDiference * 8000 / timeDifference)
    }
    
    private static func toLog(_ value: Double) -> Double {
        if value < 1e5 {
            return 0
        }
        return (2 + log10(value / 1e7)) / GAUGE_PARTS
    }
}

private struct DataItem {
    let bytesTotal: Double
    let timeElapsed: Double

    init(jsonData: [String: Any]) {
        bytesTotal = jsonData["bytes_total"] as? Double ?? 0
        timeElapsed = Double(jsonData["time_elapsed"] as? Int ?? 1)
    }
}
