//
//  UDPConnection.swift
//  RMBT
//
//  Created by Jiri Urbasek on 18.02.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation

enum UDPConnectionError: Error {
    case invalidHostOrPort
    case connectionNotAvailable
}

protocol UDPConnectable {
    func start(host: String, port: String, ipVersion: IPVersion?) async throws(UDPConnectionError)
    func cancel()
    func send(data: Data) throws
    func receive() async throws -> Data
}
