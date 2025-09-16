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
        fences <- map["speed_curve.fences"]
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

public class FenceData: ImmutableMappable {
    let fenceId: String?
    let technologyId: Int
    let longitude: Double
    let latitude: Double
    let offsetMs: Int
    let durationMs: Int?
    let radius: Double
    let avgPingMs: Double

    required public init(map: Map) throws {
        fenceId = try? map.value("fence_id")
        technologyId = try map.value("technology_id")
        longitude = try map.value("longitude")
        latitude = try map.value("latitude")
        offsetMs = try map.value("offset_ms")
        durationMs = try? map.value("duration_ms")
        radius = try map.value("radius")
        avgPingMs = try map.value("avg_ping_ms")
    }
}
