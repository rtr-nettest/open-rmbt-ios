/*****************************************************************************************************
 * Copyright 2016 SPECURE GmbH
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *****************************************************************************************************/

import Foundation
import ObjectMapper
import CoreLocation

// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}


///
@objc public class SpeedMeasurementResult: BasicRequest {

    ///
    var jpl: SpeedMeasurementJPLResult?

    ///
    var clientUuid: String?

    ///
    var extendedTestStat = ExtendedTestStat()

    ///
    var geoLocations = [GeoLocation]()

    ///
    var networkType: Int?

    ///
    var pings = [Ping]()

    ///
    var speedDetail = [SpeedRawItem]()

    ///
    var bytesDownload: UInt64?

    ///
    var bytesUpload: UInt64?

    ///
    var encryption: String?

    ///
    var ipLocal: String?

    ///
    var ipServer: String?

    ///
    var durationUploadNs: UInt64?

    ///
    var durationDownloadNs: UInt64?

    ///
    var numThreads = 1

    ///
    var numThreadsUl = 1

    ///
//    var pingShortest: Int? {
//        get {
//            return Int(bestPingNanos)
//        }
//        set {
//            // do nothing
//        }
//    }
    var pingShortest: Int?

    ///
    var portRemote: Int?

    ///
    var speedDownload: UInt64?

    ///
    var speedUpload: UInt64?

    ///
    var token: String?

    ///
    var totalBytesDownload: Int?

    ///
    var totalBytesUpload: Int?

    ///
    var interfaceTotalBytesDownload = 0

    ///
    var interfaceTotalBytesUpload = 0

    ///
    var interfaceDltestBytesDownload = 0

    ///
    var interfaceDltestBytesUpload = 0

    ///
    var interfaceUltestBytesDownload = 0

    ///
    var interfaceUltestBytesUpload = 0

    ///
    var time: Date?

    ///
    var relativeTimeDlNs: Int?

    ///
    var relativeTimeUlNs: Int?

    #if os(iOS)

    ///
    var signals = [Signal]()

    ///
    var telephonyInfo: TelephonyInfo?

    ///
    var wifiInfo: WifiInfo?

    ///
    //var cellLocations = [CellLocation]()

    var networkName: String?
    var bssid: String?
    var telephonyNetworkSimCountry: String?
    var telephonyNetworkSimOperator: String?
    
    #endif

    ///
    var publishPublicData = true

    ///
    var tag: String?

    ///////////

    ///
    var resolutionNanos: UInt64 = 0

    ///
    var testStartNanos: UInt64 = 0

    ///
    var testStartDate: Date?

    ///
    var bestPingNanos: UInt64 = 0

    ///
    var medianPingNanos: UInt64 = 0

    /////

    ///
    fileprivate var maxFrozenPeriodIndex: Int!

    ///
    let totalDownloadHistory: RMBTThroughputHistory

    ///
    let totalUploadHistory: RMBTThroughputHistory

    ///
    var totalCurrentHistory: RMBTThroughputHistory?

    ///
    var currentHistories: [RMBTThroughputHistory] = []

    ///
    var perThreadDownloadHistories: NSMutableArray!//[RMBTThroughputHistory]()

    ///
    var perThreadUploadHistories: NSMutableArray!//[RMBTThroughputHistory]()

    ///
    fileprivate var connectivities = [RMBTConnectivity]()

    ////////////

    ///
    init(resolutionNanos nanos: UInt64) {
        self.resolutionNanos = nanos

        self.totalDownloadHistory = RMBTThroughputHistory(resolutionNanos: nanos)
        self.totalUploadHistory = RMBTThroughputHistory(resolutionNanos: nanos)

        super.init()
    }

    @objc public convenience init(withJSON: [String: Any]) {
        self.init(JSON: withJSON)!
    }
    
    @objc public init(with dictionary:[String: Any]) {
        totalDownloadHistory = RMBTThroughputHistory(resolutionNanos: 0)
        totalUploadHistory = RMBTThroughputHistory(resolutionNanos: 0)
        
        super.init()
        
        
        pings = (dictionary["pings"] as? [[String: Any]])?.compactMap({ Ping(JSON: $0) }) ?? []
        token = dictionary["test_token"] as? String
        totalBytesDownload = dictionary["test_total_bytes_download"] as? Int
        totalBytesUpload = dictionary["test_total_bytes_upload"] as? Int
        encryption = dictionary["test_encryption"] as? String
        ipLocal = dictionary["test_ip_local"] as? String
        ipServer = dictionary["test_ip_server"] as? String
//        
//        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:[_testResult resultDictionary]];
//
//        result[@"test_token"] = _testParams.testToken;
//
//        // Collect total transfers from all threads
//        uint64_t sumBytesDownloaded = 0;
//        uint64_t sumBytesUploaded = 0;
//        for (RMBTTestWorker* w in _workers) {
//            sumBytesDownloaded += w.totalBytesDownloaded;
//            sumBytesUploaded += w.totalBytesUploaded;
//        }
//
//        NSAssert(sumBytesDownloaded > 0, @"Total bytes <= 0");
//        NSAssert(sumBytesUploaded > 0, @"Total bytes <= 0");
//
//        RMBTTestWorker *firstWorker = [_workers objectAtIndex:0];
//        [result addEntriesFromDictionary:@{
//            @"test_total_bytes_download": [NSNumber numberWithUnsignedLongLong:sumBytesDownloaded],
//            @"test_total_bytes_upload": [NSNumber numberWithUnsignedLongLong:sumBytesUploaded],
//            @"test_encryption": firstWorker.negotiatedEncryptionString,
//            @"test_ip_local": RMBTValueOrNull(firstWorker.localIp),
//            @"test_ip_server": RMBTValueOrNull(firstWorker.serverIp),
//        }];
//
//        [result addEntriesFromDictionary:[self interfaceBytesResultDictionaryWithStartInfo:_downlinkStartInterfaceInfo
//                                                                                   endInfo:_downlinkEndInterfaceInfo
//                                                                                    prefix:@"testdl"]];
//
//        [result addEntriesFromDictionary:[self interfaceBytesResultDictionaryWithStartInfo:_uplinkStartInterfaceInfo
//                                                                                   endInfo:_uplinkEndInterfaceInfo
//                                                                                    prefix:@"testul"]];
//
//        [result addEntriesFromDictionary:[self interfaceBytesResultDictionaryWithStartInfo:_startInterfaceInfo
//                                                                                   endInfo:_uplinkEndInterfaceInfo
//                                                                                    prefix:@"test"]];
//
//        // Add relative time_(dl/ul)_ns timestamps:
//        uint64_t startNanos = _testResult.testStartNanos;
//
//        [result addEntriesFromDictionary:@{
//             @"time_dl_ns": [NSNumber numberWithUnsignedLongLong:_downlinkTestStartedAtNanos - startNanos],
//             @"time_ul_ns": [NSNumber numberWithUnsignedLongLong:_uplinkTestStartedAtNanos - startNanos]
//        }];
//
//        if (_qosTestStartedAtNanos > 0) {
//            result[@"time_qos_ns"] = [NSNumber numberWithUnsignedLongLong:_qosTestStartedAtNanos - startNanos];
//            if (_qosTestFinishedAtNanos > _qosTestStartedAtNanos){
//                result[@"test_nsec_qos"] = [NSNumber numberWithUnsignedLongLong:_qosTestFinishedAtNanos - _qosTestStartedAtNanos];
//            } else {
//                NSParameterAssert(false);
//            }
//        }
//
//        return result;
    }
    ///
    required public init?(map: Map) {
        let nanos = self.resolutionNanos
        self.totalDownloadHistory = RMBTThroughputHistory(resolutionNanos: nanos)
        self.totalUploadHistory = RMBTThroughputHistory(resolutionNanos: nanos)
        super.init(map: map)
    }

    //////////

    ///
    func addLength(_ length: UInt64, atNanos ns: UInt64, forThreadIndex threadIndex: Int) -> [RMBTThroughput]! {
        assert(threadIndex >= 0 && threadIndex < numThreads, "Invalid thread index")

        let h = currentHistories[threadIndex]
        h.addLength(length, atNanos: ns)

        // TODO: optimize calling updateTotalHistory only when certain preconditions are met

        return updateTotalHistory()
    }

    /// Returns array of throughputs in intervals for which all threads have reported speed
    fileprivate func updateTotalHistory() -> [RMBTThroughput]! { // TODO: distinguish between download/upload thread counts
        var commonFrozenPeriodIndex = Int.max

        for h in currentHistories {
            commonFrozenPeriodIndex = min(commonFrozenPeriodIndex, h.lastFrozenPeriodIndex)
        }

        // TODO: assert ==
        if commonFrozenPeriodIndex == Int.max || commonFrozenPeriodIndex <= maxFrozenPeriodIndex {
            return nil
        }

        for i in maxFrozenPeriodIndex + 1...commonFrozenPeriodIndex {
            //for var i = maxFrozenPeriodIndex + 1; i <= commonFrozenPeriodIndex; i += 1 {
            if i == commonFrozenPeriodIndex && currentHistories[0].isFrozen { //currentHistories[0].isFrozen) {
                // We're adding up the last throughput, clip totals according to spec
                // 1) find t*
                var minEndNanos: UInt64 = 0
                var minPeriodIndex: UInt64 = 0

                for threadIndex in 0 ..< numThreads {
                    let threadHistory = currentHistories[threadIndex]
                    assert(threadHistory.isFrozen)

                    let threadLastFrozenPeriodIndex = threadHistory.lastFrozenPeriodIndex

                    let threadLastTput = threadHistory.periods[threadLastFrozenPeriodIndex]
                    if minEndNanos == 0 || threadLastTput.endNanos < minEndNanos {
                        minEndNanos = threadLastTput.endNanos
                        minPeriodIndex = UInt64(threadLastFrozenPeriodIndex)
                    }
                }

                // 2) Add up bytes in proportion to t*
                var length: UInt64 = 0

                for threadIndex in 0 ..< numThreads {
                    let threadLastPut = currentHistories[threadIndex].periods[Int(minPeriodIndex)]
                    // Factor = (t*-t(k,m-1)/t(k,m)-t(k,m-1))
                    let factor = Double(minEndNanos - threadLastPut.startNanos) / Double(threadLastPut.durationNanos)

                    assert(factor >= 0.0 && factor <= 1.0, "Invalid factor")

                    length += UInt64(factor) * threadLastPut.length
                }

                totalCurrentHistory?.addLength(length, atNanos: minEndNanos)
            } else {
                var length: UInt64 = 0

                for threadIndex in 0 ..< numThreads {
                    let tt = currentHistories[threadIndex].periods[i]
                    length += tt.length

                    assert(totalCurrentHistory?.totalThroughput.endNanos == tt.startNanos, "Period start time mismatch")
                }

                totalCurrentHistory?.addLength(length, atNanos: UInt64(i + 1) * resolutionNanos)
            }
        }

        let result = (totalCurrentHistory?.periods as NSArray?)?.subarray(
            with: NSRange(location: maxFrozenPeriodIndex + 1,
                          length: commonFrozenPeriodIndex - maxFrozenPeriodIndex)
            ) as? [RMBTThroughput]
        //var result = Array(totalCurrentHistory.periods[Int(maxFrozenPeriodIndex + 1)...Int(commonFrozenPeriodIndex - maxFrozenPeriodIndex)])
        // TODO: why is this not optional? does this return an empty array? see return statement

        maxFrozenPeriodIndex = commonFrozenPeriodIndex

        return result?.count ?? 0 > 0 ? result : nil
    }

    //////////

    ///
    func startDownloadWithThreadCount(_ threadCount: Int) {
        numThreads = threadCount

        perThreadDownloadHistories = NSMutableArray(capacity: threadCount)
        perThreadUploadHistories = NSMutableArray(capacity: threadCount)

        for _ in 0 ..< threadCount {
            perThreadDownloadHistories.add(RMBTThroughputHistory(resolutionNanos: resolutionNanos))
            perThreadUploadHistories.add(RMBTThroughputHistory(resolutionNanos: resolutionNanos))
        }

        totalCurrentHistory = totalDownloadHistory // TODO: check pass by value on array
        currentHistories = perThreadDownloadHistories as! [RMBTThroughputHistory] // TODO: check pass by value on array
        maxFrozenPeriodIndex = -1
    }

    /// Per spec has same thread count as download
    func startUpload() {
        numThreadsUl = numThreads // TODO: can upload threads be different from download threads?

        totalCurrentHistory = totalUploadHistory // TODO: check pass by value on array
        currentHistories = perThreadUploadHistories as! [RMBTThroughputHistory] // TODO: check pass by value on array
        maxFrozenPeriodIndex = -1
    }

    /// Called at the end of each phase. Flushes out values to total history.
    func flush() -> [AnyObject]! {
        var result: [AnyObject]!// = [AnyObject]()

        for h in currentHistories {
            h.freeze()
        }

        result = updateTotalHistory()

        totalCurrentHistory?.freeze()

        let totalPeriodCount = totalCurrentHistory?.periods.count ?? 0

        totalCurrentHistory?.squashLastPeriods(1)

        // Squash last two periods in all histories
        for h in currentHistories {
            h.squashLastPeriods(1 + (h .periods.count - totalPeriodCount))
        }

        // Remove last measurement from result, as we don't want to plot that one as it's usually too short
//        if result.count > 0 {
//            result = Array(result[0..<(result.count - 1)])
//        }

        return result
    }

    //////

    ///
    func addConnectivity(_ connectivity: RMBTConnectivity) {
        connectivities.append(connectivity)
    }

    ///
    func lastConnectivity() -> RMBTConnectivity? {
        return connectivities.last
    }

    //////////

    ///
    func markTestStart() {
        testStartNanos = RMBTHelpers.RMBTCurrentNanos()
        testStartDate = Date()
    }

    ///
    func addPingWithServerNanos(_ serverNanos: UInt64, clientNanos: UInt64) {
        assert(testStartNanos > 0)

        let ping = Ping(
            serverNanos: serverNanos,
            clientNanos: clientNanos,
            relativeTimestampNanos: RMBTHelpers.RMBTCurrentNanos() - testStartNanos)

        pings.append(ping)

        if bestPingNanos == 0 || bestPingNanos > serverNanos {
            bestPingNanos = serverNanos
        }

        if bestPingNanos > clientNanos {
            bestPingNanos = clientNanos
        }

        // Take median from server pings as "best" ping
        let sortedPings = pings.sorted { (p1: Ping, p2: Ping) -> Bool in
            return p1.serverNanos < p2.serverNanos // TODO: is this correct?
        }

        let sortedPingsCount = sortedPings.count

        if sortedPingsCount % 2 == 1 {
            // Uneven number of pings, median is right in the middle
            let i = (sortedPingsCount - 1) / 2
            medianPingNanos = UInt64(sortedPings[i].serverNanos)
        } else {
            // Even number of pings, median is defined as average of two middle elements
            let i = sortedPingsCount / 2
            medianPingNanos = (UInt64(sortedPings[i].serverNanos) + UInt64(sortedPings[i - 1].serverNanos)) / 2 // TODO: is division correct? should divisor be casted to double?
        }
    }

    ///
    func addLocation(_ location: CLLocation) {
        let geoLocation = GeoLocation(location: location)
        //geoLocation.relativeTimeNs =
        geoLocations.append(geoLocation)
    }

    ///
    func addCpuUsage(_ cpuUsage: Double, atNanos ns: UInt64) {
        let cpuStatValue = ExtendedTestStat.TestStat.TestStatValue()

        cpuStatValue.value = cpuUsage
        cpuStatValue.timeNs = ns

        extendedTestStat.cpuUsage.values.append(cpuStatValue)
    }

    ///
    func addMemoryUsage(_ ramUsage: Double, atNanos ns: UInt64) {
        let memStatValue = ExtendedTestStat.TestStat.TestStatValue()

        memStatValue.value = ramUsage
        memStatValue.timeNs = ns

        extendedTestStat.memUsage.values.append(memStatValue)
    }

    /////////

    ///
    func calculateThreadThroughputs(_ perThreadArray: /*[RMBTThroughputHistory]*/NSArray, direction: SpeedRawItem.SpeedRawItemDirection) {

        for i in 0 ..< perThreadArray.count {
            let h = perThreadArray.object(at: i)/*[i]*/ as! RMBTThroughputHistory
            var totalLength: UInt64 = 0

            for t in h.periods {
                totalLength += t.length

                let speedRawItem = SpeedRawItem()

                speedRawItem.direction = direction
                speedRawItem.thread = i
                speedRawItem.time = t.endNanos
                speedRawItem.bytes = totalLength

                speedDetail.append(speedRawItem)
            }
        }
    }

    ///
    func calculate() {
        if let perThreadDownloadHistories = perThreadDownloadHistories {
            calculateThreadThroughputs(perThreadDownloadHistories, direction: .Download)
        }
        if let perThreadUploadHistories = perThreadUploadHistories {
            calculateThreadThroughputs(perThreadUploadHistories, direction: .Upload)
        }

        // download total troughputs
        speedDownload = UInt64(totalDownloadHistory.totalThroughput.kilobitsPerSecond())
        durationDownloadNs = totalDownloadHistory.totalThroughput.endNanos
        bytesDownload = totalDownloadHistory.totalThroughput.length

        // upload total troughputs
        speedUpload = UInt64(totalUploadHistory.totalThroughput.kilobitsPerSecond())
        durationUploadNs = totalUploadHistory.totalThroughput.endNanos
        bytesUpload = totalUploadHistory.totalThroughput.length

        #if os(iOS)
        // connectivities
        for c in connectivities {
            let s = Signal(connectivity: c)
            signals.append(s)

            networkType = max(networkType ?? -1, s.networkTypeId)
        }

        // TODO: is it correct to get telephony/wifi info from lastConnectivity?
        if let lastConnectivity = lastConnectivity() {
            if lastConnectivity.networkType == .cellular {
                telephonyInfo = TelephonyInfo(connectivity: lastConnectivity)
            } else if lastConnectivity.networkType == .wifi {
                wifiInfo = WifiInfo(connectivity: lastConnectivity)
            }
        }
        #else
        networkType = RMBTNetworkType.wiFi.rawValue // TODO: correctly set on macos and tvOS
        #endif
    }

    /////////

    ///
    public override func mapping(map: Map) {
        super.mapping(map: map)

        jpl                     <- map["jpl"]
    //
        clientUuid              <- map["client_uuid"]
        extendedTestStat        <- map["extended_test_stat"]

        geoLocations            <- map["geoLocations"]
        networkType             <- map["network_type"]
        pings                   <- map["pings"]
        
        speedDetail             <- map["speed_detail"]
        
        //
        bytesDownload           <- (map["test_bytes_download"], UInt64NSNumberTransformOf)
        bytesUpload             <- (map["test_bytes_upload"], UInt64NSNumberTransformOf)
        encryption              <- map["test_encryption"]
        ipLocal                 <- map["test_ip_local"]
        ipServer                <- map["test_ip_server"]
        durationUploadNs        <- (map["test_nsec_upload"], UInt64NSNumberTransformOf)
        durationDownloadNs      <- (map["test_nsec_download"], UInt64NSNumberTransformOf)
        numThreads              <- map["test_num_threads"]
        numThreadsUl            <- map["num_threads_ul"]
        pingShortest            <- map["test_ping_shortest"]
        portRemote              <- map["port_remote"]
        speedDownload           <- (map["test_speed_download"], UInt64NSNumberTransformOf)
        speedUpload             <- (map["test_speed_upload"], UInt64NSNumberTransformOf)
        
        token                   <- map["test_token"]
        totalBytesDownload      <- map["test_total_bytes_download"]
        totalBytesUpload        <- map["test_total_bytes_upload"]
        interfaceTotalBytesDownload  <- map["test_if_bytes_download"]
        interfaceTotalBytesUpload    <- map["test_if_bytes_upload"]
        interfaceDltestBytesDownload <- map["testdl_if_bytes_download"]
        interfaceDltestBytesUpload   <- map["testdl_if_bytes_upload"]
        interfaceUltestBytesDownload <- map["testul_if_bytes_download"]
        interfaceUltestBytesUpload   <- map["testul_if_bytes_upload"]
        
        time              <- map["time"]
        relativeTimeDlNs  <- map["time_dl_ns"]
        relativeTimeUlNs  <- map["time_ul_ns"]
        
        publishPublicData <- map["publish_public_data"]
        
        #if os(iOS)
            signals       <- map["signals"]
            telephonyInfo <- map["telephony_info"]
            wifiInfo      <- map["wifi_info"]
            //cellLocations   <- map["cell_locations"]
        
        if networkType == RMBTNetworkType.wifi.rawValue {
            networkName   <- map["wifi_ssid"]
            bssid   <- map["wifi_bssid"]
        }
        #endif
    }
}
