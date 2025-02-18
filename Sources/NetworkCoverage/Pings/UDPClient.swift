//
//  UDPClient.swift
//  RMBT
//
//  Created by Jiri Urbasek on 18.02.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation
import Network

class UDPClient {
    var connection: NWConnection

    init(host: NWEndpoint.Host, port: NWEndpoint.Port = 0) {
        let params = NWParameters.udp
//        params.allowLocalEndpointReuse = true
//        params.includePeerToPeer = true

        connection = NWConnection(host: host, port: port, using: params)
        connection.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                print("State: Ready")
            case .setup:
                print("State: Setup")
            case .cancelled:
                print("State: Cancelled")
            case .preparing:
                print("State: Preparing")
            case .waiting(let error):
                print("State: Waiting: \(error)n")
            case .failed(let error):
                print("State: Error: \(error)n")
            @unknown default:
                print("Unknown state")
            }
        }
        connection.start(queue: .global())
    }

    deinit {
        connection.cancel()
    }

    var onReceivedData: ((Data) -> Void)?

    func send(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        connection.send(content: data, completion: .contentProcessed { [weak connection] error in
            if let error {
                completion(.failure(error))
            } else {
                connection?.receiveMessage { [weak self] data, context, isComplete, error in
                    guard let data else {
                        print("Error: Received nil Data")
                        return
                    }
                    print("Received: \(String(decoding: data, as: UTF8.self))")

                    self?.onReceivedData?(data)
                }
                completion(.success(()))
            }
        })
    }
}
