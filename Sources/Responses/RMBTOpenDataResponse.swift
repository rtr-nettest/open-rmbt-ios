//
//  RMBTOpenDataResponse.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 09.09.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import ObjectMapper

@objc public class RMBTOpenDataResponse: BasicResponse {

    var downloadSpeedCurve: [RMBTOpenDataSpeedCurveValue] = []
    var uploadSpeedCurve: [RMBTOpenDataSpeedCurveValue] = []
    @objc var pingGraphValues: [RMBTHistoryPing] = []
    var signal: Int?
    var signalClass: Int?
    var fences: [FenceData] = []
    
    @objc func json() -> [String: Any] {
        return self.toJSON()
    }
    
    public override func mapping(map: Map) {
        downloadSpeedCurve <- map["speed_curve.download"]
        uploadSpeedCurve <- map["speed_curve.upload"]
        pingGraphValues <- map["speed_curve.ping"]
        signal <- map["signal_strength"]
        signalClass <- map["signal_classification"]
        fences <- map["fences"]
    }
}

public class RMBTOpenDataSpeedCurveValue: Mappable {
    var bytesTotal: Double?
    var timeElapsed: Int?
    
    public required init?(map: Map) { }
    
    public func mapping(map: Map) {
        bytesTotal <- map["bytes_total"]
        timeElapsed <- map["time_elapsed"]
    }
}

public class FenceData: Mappable {
    var fenceId: String?
    var technologyId: Int?
    var technology: String?
    var longitude: Double?
    var latitude: Double?
    var offsetMs: Int?
    var durationMs: Int?
    var radius: Double?
    
    public required init?(map: Map) { }
    
    public func mapping(map: Map) {
        fenceId <- map["fence_id"]
        technologyId <- map["technology_id"]
        technology <- map["technology"]
        longitude <- map["longitude"]
        latitude <- map["latitude"]
        offsetMs <- map["offset_ms"]
        durationMs <- map["duration_ms"]
        radius <- map["radius"]
    }
}
