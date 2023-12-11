//
//  RMBTHistoryResult.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 14.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import CoreLocation

enum RMBTHistoryResultDataState: UInt {
    case index
    case basic
    case full
}

class RMBTHistoryLoopResult: RMBTHistoryResult {
    private(set) var loopResults: [RMBTHistoryResult] = []
    
    init(from loopResults: [RMBTHistoryResult]) {
        super.init()
        if let firstResult = loopResults.last {
            timestamp = firstResult.timestamp
            timeString = firstResult.timeString
            networkTypeServerDescription = firstResult.networkTypeServerDescription
            loopUuid = firstResult.loopUuid ?? firstResult.uuid
        }
        self.loopResults = loopResults
    }
}

class RMBTHistoryResult: NSObject {
    private(set) var dataState: RMBTHistoryResultDataState = .index
    
    // MARK: - Index
    
    private(set) var uuid: String = ""
    private(set) var openTestUuid: String?
    fileprivate(set) var loopUuid: String?
    fileprivate(set) var timestamp: Date = Date(timeIntervalSince1970: 0)
    fileprivate(set) var timeString: String?
    
    private(set) var downloadSpeedMbpsString: String?
    private(set) var uploadSpeedMbpsString: String?

    private(set) var downloadSpeedClass: Int = -1
    private(set) var uploadSpeedClass: Int = -1
    private(set) var pingClass: Int = -1
    private(set) var signalClass: Int = -1
    
    private(set) var signal: NSNumber?
    private(set) var shortestPingMillisString: String?
    private(set) var deviceModel: String?
    private(set) var coordinate: CLLocationCoordinate2D = kCLLocationCoordinate2DInvalid
    fileprivate(set) var networkTypeServerDescription: String = "" // "WLAN", "2G/3G" etc.

    // Available in basic details
    private(set) var networkType: RMBTNetworkType = .unknown
    private(set) var shareText: String?
    private(set) var shareURL: URL?
    
    override init() {
        super.init()
    }
    
    @objc init(response: [String: Any]) {
        downloadSpeedMbpsString = response["speed_download"] as? String
        uploadSpeedMbpsString = response["speed_upload"] as? String
        shortestPingMillisString = response["ping_shortest"] as? String
        // Note: here network_type is a string with full description (i.e. "WLAN") and in the basic details response
        // it's a numeric code
        networkTypeServerDescription = response["network_type"] as? String ?? ""
        uuid = response["test_uuid"] as? String ?? ""
        loopUuid = response["loop_uuid"] as? String
        deviceModel = response["model"] as? String
        timeString = response["time_string"] as? String
            
        if let time = response["time"] as? Int {
            let t = Double(time) / 1000.0
            timestamp = Date(timeIntervalSince1970: t)
        } else {
            if response["time"] != nil {
                assert(false, "can't parse time")
            }
        }
        
        downloadSpeedClass = response["speed_download_classification"] as? Int ?? -1
        uploadSpeedClass = response["speed_upload_classification"] as? Int ?? -1
        pingClass = response["ping_classification"] as? Int ?? -1
        super.init()
        assert(response["ping_classification"] == nil ? true : self.pingClass > -1 )
        assert(response["speed_upload_classification"] == nil ? true : self.uploadSpeedClass > -1)
        assert(response["speed_download_classification"] == nil ? true : self.downloadSpeedClass > -1)
        assert(!self.uuid.isEmpty)
    }

    private lazy var currentYearFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd\nHH:mm"
        return dateFormatter
    }()
    
    private lazy var previousYearFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd\nYYYY"
        return dateFormatter
    }()
    
    func formattedTimestamp() -> String {
        let historyDateComponents = Calendar.current.dateComponents([.year], from: timestamp)

        let currentDateComponents = Calendar.current.dateComponents([.year], from: Date())
        let result: String

        if (currentDateComponents.year == historyDateComponents.year) {
            result = currentYearFormatter.string(from: timestamp)
        } else {
            result = previousYearFormatter.string(from: timestamp)
        }

        // For some reason MMM on iOS7 returns "Aug." with a trailing dot, let's strip the dot manually
        return result.replacingOccurrences(of: ".", with: "")
    }
   
    // MARK: - Basic Details
    private(set) var netItems: [RMBTHistoryResultItem] = []
    private(set) var measurementItems: [RMBTHistoryResultItem]?
    private(set) var qoeClassificationItems: [RMBTHistoryQOEResultItem] = []
    private(set) var qosResults: [RMBTHistoryQoSGroupResult]?
    
    /// response always nil. error will be not nil if we have error
    ///
    func ensureBasicDetails(complete: @escaping RMBTCompleteBlock) {
        var finalError: Error?
        if (self.dataState != .index) {
            complete(nil, nil)
        } else {
            let allDone = DispatchGroup()
            
            allDone.enter()
            RMBTControlServer.shared.getHistoryQOSResultWithUUID(testUuid: self.uuid) { [weak self] response in
                let results = RMBTHistoryQoSGroupResult.results(with: response.json())
                if (results.count > 0) {
                    self?.qosResults = results
                }
                allDone.leave()
            } error: { error in
                finalError = error
                Log.logger.error("Error fetching QoS test results: \(String(describing: error)).")
                allDone.leave()
            }

            allDone.enter()
            RMBTControlServer.shared.getHistoryResultWithUUID(uuid: self.uuid, fullDetails: false, success: { [weak self] r in
                guard let self = self else {
                    allDone.leave()
                    return
                }
                guard let response = r.measurements?.first?.json() else {
                    allDone.leave()
                    return
                }
                if let networkTypeInt = response["network_type"] as? Int {
                    self.networkType = RMBTNetworkType(rawValue: networkTypeInt) ?? .unknown
                }
                if let networkInfo = response["network_info"] as? [String: Any],
                   let networkTypeLabel = networkInfo["network_type_label"] as? String {
                    self.networkTypeServerDescription = networkTypeLabel
                }
                
                self.timeString = response["time_string"] as? String
                if let time = response["time"] as? Int {
                    let t = Double(time) / 1000.0
                    self.timestamp = Date(timeIntervalSince1970: t)
                } else {
                    assert(false, "can't parse time")
                }
                
                self.openTestUuid = response["open_test_uuid"] as? String
                self.shareURL = nil;
                self.shareText = response["share_text"] as? String
                if let shareText = self.shareText,
                   let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
                    
                    let matches = linkDetector.matches(in: shareText, options: [], range: NSRange(location: 0, length: shareText.count))
                    if let r = matches.last {
                        assert(r.resultType == .link, "Invalid match type")
                        self.shareText = (shareText as NSString).replacingCharacters(in: r.range, with: "")
                        self.shareURL = r.url
                    }
                }
                
                if let net = response["net"] as? [[String: Any]] {
                    var netItems: [RMBTHistoryResultItem] = []
                    netItems = net.map({ RMBTHistoryResultItem(with: $0) })
                    self.netItems = netItems
                }

                if let measurement = response["measurement"] as? [[String: Any]] {
                    var measurementItems: [RMBTHistoryResultItem] = []
                    measurementItems = measurement.map({ r in
                        let item = RMBTHistoryResultItem(with: r)
                        if (item.title == "Download") {
                            self.downloadSpeedClass = item.classification
                        } else if (item.title == "Upload") {
                            self.uploadSpeedClass = item.classification
                        } else if (item.title == "Ping") {
                            self.pingClass = item.classification
                        }
                        return item
                    })
                    self.measurementItems = measurementItems
                }
                
                if let qoeClassification = response["qoe_classification"] as? [[String: Any]] {
                    self.qoeClassificationItems = qoeClassification.map({ RMBTHistoryQOEResultItem(with: $0) })
                }
                
                if let lat = response["geo_lat"] as? Double,
                   let long = response["geo_long"] as? Double {
                    self.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: long)
                } else {
                    assert(false, "Can't parse coordinates")
                }

                if let measurementResult = response["measurement_result"] as? [String: Any] {
                    if let download = measurementResult["download_kbit"] as? Int {
                        self.downloadSpeedMbpsString = RMBTSpeedMbpsString(Double(download), withMbps: false)
                    } else {
                        assert(false, "can't parse download")
                    }
                    if let upload = measurementResult["upload_kbit"] as? Int {
                        self.uploadSpeedMbpsString = RMBTSpeedMbpsString(Double(upload), withMbps: false)
                    } else {
                        assert(false, "can't parse upload")
                    }
                    
                    if let ping = measurementResult["ping_ms"] as? Int {
                        self.shortestPingMillisString = "\(ping)"
                    } else {
                        assert(false, "can't parse upload")
                    }
                }

                self.dataState = .basic
                allDone.leave()
            }, error: { error in
                finalError = error
                Log.logger.error("Error fetching test results: \(String(describing: error)).")
                allDone.leave()
            })
            
            allDone.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                if self.dataState == .basic {
                    self.addQosToQoeClassifications()
                    complete(nil, finalError)
                }
            }
        }
    }
    
    // MARK: - QoS in QoE
    func addQosToQoeClassifications() {
        var totalQos = 0
        var okQos = 0
        var okQosPercent = 0.0
        
        if (self.qosResults?.count ?? 0 > 0) {
            for resGroup in self.qosResults ?? [] {
                for res in resGroup.tests {
                    totalQos += 1
                    if (res.isSuccessful) {
                        okQos += 1
                    }
                }
            }
            okQosPercent = Double(okQos) / Double(totalQos)
        }
        var classification = -1
        if (okQosPercent >= 1) {
            classification = 4
        } else if (okQosPercent > 0.95) {
            classification = 3
        } else if (okQosPercent > 0.5) {
            classification = 2
        } else {
            classification = 1
        }
        if (totalQos > 0) {
            let value = String(format: "%d%% (%d/%d)", Int(okQosPercent * 100), okQos, totalQos)
            let qosResultItem = RMBTHistoryQOEResultItem(with: "qos", quality: String(okQosPercent), value: value, classification: classification)
            self.qoeClassificationItems.append(qosResultItem)
        }
    }
    
    // MARK: - Full Details
    private(set) var fullDetailsItems: [Any]?
    
    func ensureFullDetails(success: @escaping RMBTBlock) {
        if (self.dataState == .full) {
            success()
        } else {
            // Fetch data
            RMBTControlServer.shared.getFullDetailsHistoryResultWithUUID(uuid: self.uuid) { [weak self] response in
                if let responseDictionary = response.json()["testresultdetail"] as? [[String: Any]] {
                    let fullDetailsItems = responseDictionary.map({ RMBTHistoryResultItem(with: $0) })
                    self?.fullDetailsItems = fullDetailsItems.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
                }
                
                self?.dataState = .full
                success()
            } error: { error in
                // TODO: propagate error here
            }
        }
    }
    
    // MARK: - Speed graphs
    private(set) var downloadGraph: RMBTHistorySpeedGraph?
    private(set) var uploadGraph: RMBTHistorySpeedGraph?
    private(set) var pingGraph: RMBTHistoryPingGraph?
    
    func ensureSpeedGraph(success: @escaping RMBTBlock) {
        assert(openTestUuid != nil)
        guard let openTestUuid = self.openTestUuid else {
            success()
            return
        }
        RMBTControlServer.shared.getHistoryOpenDataResult(with: openTestUuid, success: { [weak self] response in
            guard let self = self else {
                success()
                return
            }
    
            let r = response.json()
            if let speedCurve = r["speed_curve"] as? [String: Any] {
                if let download = speedCurve["download"] as? [[String: Any]] {
                    self.downloadGraph = RMBTHistorySpeedGraph(with: download)
                }
                if let upload = speedCurve["upload"] as? [[String: Any]] {
                    self.uploadGraph = RMBTHistorySpeedGraph(with: upload)
                }
            }

            self.pingGraph = RMBTHistoryPingGraph(with: response.pingGraphValues)
            self.signal = r["signal_strength"] as? NSNumber
            self.signalClass = r["signal_classification"] as? Int ?? -1
            success()
        }, error: { _,_ in
            // TODO
        })
    }
}

extension RMBTHistoryResult {
    var timeStringIn24hFormat: String? {
        get {
            let df = DateFormatter(withFormat: "dd.MM.yy, HH:mm:ss", locale: Locale.current.language.languageCode?.identifier ?? "en_US")
            
            return df.string(from: timestamp)
        }
    }
}
