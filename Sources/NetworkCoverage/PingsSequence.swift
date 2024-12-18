//
//  PingsAsyncIteratorProtocol.swift
//  RMBT
//
//  Created by Jiri Urbasek on 12/4/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import Foundation

// https://itnext.io/mocking-asyncsequence-in-unit-tests-a4cb6a0d5e59

@rethrows protocol PingsAsyncIteratorProtocol: AsyncIteratorProtocol where Element == PingResult { }

@rethrows protocol PingsAsyncSequence: AsyncSequence where AsyncIterator: PingsAsyncIteratorProtocol { }

enum PingResult: Hashable {
    case interval(Duration)
    case error
}

struct PingsSequence: PingsAsyncSequence {
    let urlSession: URLSession
    let request: URLRequest
    let clock: any Clock<Duration>
    let frequency: Duration

    struct AsyncIterator: PingsAsyncIteratorProtocol {
        let urlSession: URLSession
        let request: URLRequest
        let clock: any Clock<Duration>
        let frequency: Duration

        mutating func next() async -> PingResult? {
            var capturedError: (any Error)? = nil
            let elapsed = await clock.measure {
                do {
                    _ = try await urlSession.data(for: request)
                } catch {
                    capturedError = error
                }
            }

            do {
                let waitTime = frequency - elapsed
                if waitTime > .zero {
                    try await clock.sleep(for: waitTime)
                }
            } catch {
               return nil
            }
            return capturedError.map { _ in .error } ?? .interval(elapsed)
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(urlSession: urlSession, request: request, clock: clock, frequency: frequency)
    }
}

extension Duration {
    var milliseconds: Int64 {
        Int64(Double(components.attoseconds) / 1e15)
    }
}
