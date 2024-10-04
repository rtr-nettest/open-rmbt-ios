//
//  RMBTQoSIPTest.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 10.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

enum RMBTQoIPTestDirection: Int {
    case out
    case `in`
    case error
}

class RMBTQoSIPTest: RMBTQoSCCTest, @unchecked Sendable {

    var direction: RMBTQoIPTestDirection = .error
    private(set) var outPort: UInt = 0
    private(set) var inPort: UInt = 0
   
    override init?(with params: [String : Any]) {
        if let port = params["in_port"] as? String,
           let intPort = UInt(port) {
            inPort = intPort
        } else if let port = params["out_port"] as? String,
           let intPort = UInt(port) {
            outPort = intPort
        } else {
            assert(false, "Can't parse ports")
            return nil
        }
        super.init(with: params)
    }
    
    func ipMain(_ isOutgoing: Bool) {
        assert(false) // should be overriden in subclass
    }
    
    override func main() {
        if (direction != .out && direction != .in) {
            assert(false) // catch this invalid state in debug, but don't bail if we encounter it in production
            Log.logger.error("\(self) has invalid direction")
            self.status = .error
            return;
        }

        self.ipMain(direction == .out)
    }
}
