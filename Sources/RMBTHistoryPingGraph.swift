//
//  RMBTHistoryPingGraph.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 06.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import ObjectMapper

class RMBTHistoryPing: NSObject, Mappable {
    var pingMs: Double = 0.0
    var timeElapsed: Int = 0
    
    required init?(map: Map) { }
    required init(pingMs: Double, timeElapsed: Int) {
        self.pingMs = pingMs
        self.timeElapsed = timeElapsed
    }
    
    func mapping(map: Map) {
        pingMs <- map["ping_ms"]
        timeElapsed <- map["time_elapsed"]
    }
}

@objc class RMBTHistoryPingGraph: NSObject, Mappable {
    var pings: [RMBTHistoryPing] = []
    
    @objc(initWithPings:)
    init(with pings: [RMBTHistoryPing] = []) {
        self.pings = pings
    }
    
    required init?(map: Map) { }
    
    func mapping(map: Map) {
        pings <- map["ping"]
    }
}
