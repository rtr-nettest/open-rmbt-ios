//
//  RMBTTestResult.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 18.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import CoreLocation

@objc class RMBTTestResult: NSObject {
    private(set) var threadCount: UInt = 0
    private(set) var resolutionNanos: UInt64 = 0
    
    @objc private(set) var pings: [Ping] = []
    private(set) var bestPingNanos: UInt64 = 0
    private(set) var medianPingNanos: UInt64 = 0
    
    @objc private(set) var totalDownloadHistory: RMBTThroughputHistory
    @objc private(set) var totalUploadHistory: RMBTThroughputHistory
    private(set) var totalCurrentHistory: RMBTThroughputHistory?
    
    private(set) var perThreadDownloadHistories: [RMBTThroughputHistory] = []
    private(set) var perThreadUploadHistories: [RMBTThroughputHistory] = []

    private(set) var locations: [CLLocation] = []
    private(set) var connectivities: [RMBTConnectivity] = []
    
    @objc private(set) var testStartNanos: UInt64 = 0
    private var testStartDate: Date?
    
    private var currentHistories: [RMBTThroughputHistory]?
    private var maxFrozenPeriodIndex: Int = 0
    
    @objc init(resolutionNanos: UInt64) {
        self.resolutionNanos = resolutionNanos
        totalDownloadHistory = RMBTThroughputHistory(resolutionNanos: resolutionNanos)
        totalUploadHistory = RMBTThroughputHistory(resolutionNanos: resolutionNanos)
    }
    
    @objc func markTestStart() {
        testStartNanos = RMBTHelpers.RMBTCurrentNanos()
        testStartDate = Date()
    }

    @objc func addPingWithServerNanos(_ serverNanos: UInt64, clientNanos: UInt64) {
        assert(testStartNanos > 0)

        let p = Ping(serverNanos: serverNanos,
                     clientNanos: clientNanos,
                     relativeTimestampNanos: RMBTHelpers.RMBTCurrentNanos() - testStartNanos)
        pings.append(p)

        if (bestPingNanos == 0 || bestPingNanos > serverNanos) { bestPingNanos = serverNanos }
        if (bestPingNanos > clientNanos) { bestPingNanos = clientNanos }

        // Take median from server pings as "best" ping
        let sortedPings = pings.sorted(by: { $0.serverNanos > $1.serverNanos })

        if (sortedPings.count % 2 == 1) {
            // Uneven number of pings, median is right in the middle
            let i: Int = (sortedPings.count - 1) / 2
            medianPingNanos = sortedPings[i].serverNanos
        } else {
            // Even number of pings, median is defined as average of two middle elements
            let i2 = sortedPings.count / 2
            medianPingNanos = (sortedPings[i2].serverNanos + sortedPings[i2 - 1].serverNanos) / 2
        }

        //RMBTLog(@"Pings: %@, Sorted: %@, Median: %" PRIu64, _pings, sortedPings, _bestPingNanos);
    }
    
    @objc func addLength(_ length: UInt64, atNanos ns: UInt64, for threadIndex: UInt) -> [RMBTThroughput]? {
        assert(threadIndex >= 0 && threadIndex < threadCount, "Invalid thread index")

        if let h = currentHistories?[Int(threadIndex)] {
            h.addLength(length, atNanos: ns)
        }
    
        //TODO: optimize calling updateTotalHistory only when certain preconditions are met
        return self.updateTotalHistory()
    }

    @objc func addLocation(_ location: CLLocation) {
        locations.append(location)
    }
    
    @objc func addConnectivity(_ connectivity: RMBTConnectivity) {
        connectivities.append(connectivity)
    }
    
    @objc func lastConnectivity() -> RMBTConnectivity? {
        return connectivities.last
    }

    @objc func startDownload(with threadCount: UInt) {
        self.threadCount = threadCount
        perThreadDownloadHistories = []
        perThreadUploadHistories = []
        
        for _ in 0..<threadCount {
            perThreadDownloadHistories.append(RMBTThroughputHistory(resolutionNanos: resolutionNanos))
            perThreadUploadHistories.append(RMBTThroughputHistory(resolutionNanos: resolutionNanos))
        }
        
        totalCurrentHistory = totalDownloadHistory
        currentHistories = perThreadDownloadHistories
        
        maxFrozenPeriodIndex = -1
    }
    
    @objc func startUpload() { // Per spec has same thread count as download
        totalCurrentHistory = totalUploadHistory
        currentHistories = perThreadUploadHistories
        maxFrozenPeriodIndex = -1
    }

    // Called at the end of each phase. Flushes out values to total history.
    @objc func flush() -> [RMBTThroughput]? {
        guard let currentHistories = self.currentHistories else { return nil }
        
        for h in currentHistories {
            h.freeze()
        }
        
        var result = self.updateTotalHistory()
        
        totalCurrentHistory?.freeze()
        
        let totalPeriodCount = totalCurrentHistory?.periods.count ?? 0
        totalCurrentHistory?.squashLastPeriods(1)

        // Squash last two periods in all histories
        for h in currentHistories {
            h.squashLastPeriods(1 + (h.periods.count - totalPeriodCount))
        }
        
        // Remove last measurement from result, as we don't want to plot that one as it's usually too short
        // TODO: return result after squashing
        if (result?.count ?? 0 > 0) {
            result?.removeLast()
        }
        return result
    }
    
    // Returns array of throughputs in intervals for which all threads have reported speed
    func updateTotalHistory() -> [RMBTThroughput]? {
        guard let currentHistories = self.currentHistories else { return nil }
        var commonFrozenPeriodIndex = Int.max
        
        for h in currentHistories {
            commonFrozenPeriodIndex = min(commonFrozenPeriodIndex, h.lastFrozenPeriodIndex)
        }

        //TODO: assert ==
        if (commonFrozenPeriodIndex == Int.max || commonFrozenPeriodIndex <= maxFrozenPeriodIndex) { return nil }

        for i in (maxFrozenPeriodIndex + 1)...commonFrozenPeriodIndex {
            if (i == commonFrozenPeriodIndex && currentHistories[0].isFrozen) {
                // We're adding up the last throughput, clip totals according to spec
                // 1) find t*
                var minEndNanos: UInt64 = 0
                var minPeriodIndex: Int = 0
                
                for threadIndex in 0..<threadCount {
                    let threadHistory = currentHistories[Int(threadIndex)]
                    assert(threadHistory.isFrozen)
                    
                    let threadLastFrozenPeriodIndex = threadHistory.lastFrozenPeriodIndex
                    
                    let threadLastTput: RMBTThroughput = threadHistory.periods[threadLastFrozenPeriodIndex]
                    
                    if (minEndNanos == 0 || threadLastTput.endNanos < minEndNanos) {
                        minEndNanos = threadLastTput.endNanos
                        minPeriodIndex = threadLastFrozenPeriodIndex
                    }
                }
                
                // 2) Add up bytes in proportion to t*
                var length: UInt64 = 0
                for threadIndex in 0..<threadCount {
                    let threadLastTput: RMBTThroughput = currentHistories[Int(threadIndex)].periods[minPeriodIndex]
                    // Factor = (t*-t(k,m-1)/t(k,m)-t(k,m-1))
                    let factor: Double = Double(minEndNanos - threadLastTput.startNanos) / Double(threadLastTput.durationNanos)
                    assert(factor >= 0.0 && factor <= 1.0, "Invalid factor")
                    length += UInt64(factor) * threadLastTput.length
                }
                totalCurrentHistory?.addLength(length, atNanos: minEndNanos)
            } else {
                var length: UInt64 = 0
                for threadIndex in 0..<threadCount {
                    let tt = currentHistories[Int(threadIndex)].periods[i]
                    length += tt.length
                    assert(totalCurrentHistory?.totalThroughput.endNanos == tt.startNanos, "Period start time mismatch");
                }
                totalCurrentHistory?.addLength(length, atNanos: UInt64((i + 1)) * resolutionNanos)
            }
        }

        let range = NSRange(location: maxFrozenPeriodIndex + 1, length: commonFrozenPeriodIndex - maxFrozenPeriodIndex)
        let periods = ((totalCurrentHistory?.periods) as NSArray?)
        let result: [RMBTThroughput]? = periods?.subarray(with: range) as? [RMBTThroughput]
        maxFrozenPeriodIndex = commonFrozenPeriodIndex
        return result
    }
    
    @objc func resultDictionary() -> [String: Any] {
        var pings: [[String: Any]] = []

        for p in self.pings {
            pings.append(p.json())
        }
        
        var speedDetails: [[String: Any]] = []
        
        speedDetails.append(contentsOf: subresult(for: perThreadDownloadHistories, with: "download"))
        speedDetails.append(contentsOf: subresult(for: perThreadUploadHistories, with: "upload"))

        var result: [String: Any] = [
            "test_ping_shortest": bestPingNanos, // TODO: helper
            "pings": pings,
            "speed_detail": speedDetails,
            "test_num_threads": threadCount,
        ]

        let totalDownload = subresult(for: self.totalDownloadHistory.totalThroughput,  with: "download")
        totalDownload.forEach { item in
            result[item.key] = item.value
        }
        
        
        let totalUpload = subresult(for: self.totalUploadHistory.totalThroughput,  with: "upload")
        totalUpload.forEach { item in
            result[item.key] = item.value
        }
        
        locationsResultDictionary().forEach { item in
            result[item.key] = item.value
        }
        
        connectivitiesResultDictionary().forEach { item in
            result[item.key] = item.value
        }
        
        return result
    }
    
    func subresult(for threadThroughputs: [RMBTThroughputHistory], with directionString: String) -> [[String: Any]] {
        var result: [[String: Any]] = []
        
        for (i, h) in threadThroughputs.enumerated() {
            var totalLength: UInt64 = 0
            for t in h.periods {
                totalLength += t.length
                result.append([
                    "direction": directionString,
                    "thread": i,
                    "time": t.endNanos,
                    "bytes": totalLength
                ])
            }
        }
        return result
    }

    func subresult(for totalThroughput: RMBTThroughput, with directionString: String) -> [String: Any] {
        return [
             "test_speed_\(directionString)": totalThroughput.kilobitsPerSecond(),
             "test_nsec_\(directionString)": totalThroughput.endNanos,
             "test_bytes_\(directionString)": totalThroughput.length
        ]
    }

    func locationsResultDictionary() -> [String: Any] {
        var result: [[String: Any]] = []
        
        for l in locations {
            let t = max(0, l.timestamp.timeIntervalSince(testStartDate ?? Date()))

            let ts_nanos: UInt64 = UInt64(t) * NSEC_PER_SEC
            var entry: [String: Any] = [
               "geo_long": l.coordinate.longitude,
               "geo_lat":  l.coordinate.latitude,
               "tstamp":   UInt64(l.timestamp.timeIntervalSince1970 * 1000),
               "time_ns":  ts_nanos,
               "accuracy": l.horizontalAccuracy,
               "altitude": l.altitude,
               // Speed in m/s (raw CLLocation.speed), matching Android; 0 when the fix has no speed.
               "speed": l.speed > 0.0 ? l.speed : 0.0,
               // Inferred fix source ("gps"/"network"); the backend maps `provider` to loc_src.
               "provider": l.rmbtSource.rawValue
             ]
            // Heading (bearing) in degrees; only when the fix carries a valid course (course >= 0).
            if l.course >= 0 {
                entry["heading"] = l.course
            }
            result.append(entry)
        }
        return ["geoLocations": result]
    }

    func connectivitiesResultDictionary() -> [String: Any] {
        var result: [String: Any] = [:]
        var signals: [[String: Any]] = []
        var networkType: Int = -1
        
        for c in connectivities {
            let cResult = c.testResultDictionary()
            signals.append([
                "time": RMBTHelpers.RMBTTimestamp(with: c.timestamp),
                "network_type_id": cResult["network_type"] as? Int ?? 0
            ])

            let currentNetworkType = (cResult["network_type"] as? Int) ?? -1
            // Take maximum network type
            networkType = max(currentNetworkType, networkType)
            result = cResult
        }
        
        result["network_type"] = networkType
        result["signals"] = signals
        return result;
    }
}
