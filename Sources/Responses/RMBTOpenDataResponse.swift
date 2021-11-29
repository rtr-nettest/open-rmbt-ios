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
    var signal: Int?
    var signalClass: Int?
    
    @objc func json() -> [String: Any] {
        return self.toJSON()
    }
    
    public override func mapping(map: Map) {
        downloadSpeedCurve <- map["speed_curve.download"]
        uploadSpeedCurve <- map["speed_curve.upload"]
        signal <- map["signal_strength"]
        signalClass <- map["signal_classification"]
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
