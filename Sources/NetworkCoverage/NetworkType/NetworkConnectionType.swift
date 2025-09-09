//
//  NetworkConnectionType.swift
//  RMBT
//
//  Created by Jiri Urbasek on 09.09.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation

struct NetworkTypeUpdate: Equatable {
    enum NetworkConnectionType: Equatable {
        case wifi
        case cellular
    }
    
    let type: NetworkConnectionType
    let timestamp: Date
}
