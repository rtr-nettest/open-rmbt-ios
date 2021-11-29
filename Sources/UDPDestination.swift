//
//  UDPDestination.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 28.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import XCGLogger
import CocoaAsyncSocket

class UDPDestination: BaseQueuedDestination {
    private var port: UInt = 0
    private var host: String = ""
    
    fileprivate let socketQueue = DispatchQueue(label: "socket.queue")
    
    private lazy var socket: GCDAsyncUdpSocket = {
        let socket = GCDAsyncUdpSocket(delegate: nil, delegateQueue: self.socketQueue)
        try? socket.enableBroadcast(true)
        return socket
    }()
    
    init(owner: XCGLogger?, identifier: String = "", host: String, port: UInt = 0) {
        self.host = host
        self.port = port
        super.init(owner: owner, identifier: identifier)
    }
    
    // MARK: - Overridden Methods
    /// Write the log to the udp server
    ///
    /// - Parameters:
    ///     - message:   Formatted/processed message ready for output.
    ///
    /// - Returns:  Nothing
    ///
    open override func write(message: String) {
        if let encodedData = "\(message)\n".data(using: String.Encoding.utf8) {
            self.socket.send(encodedData, toHost: host, port: UInt16(port), withTimeout: -1, tag: 0)
        }
    }
}
