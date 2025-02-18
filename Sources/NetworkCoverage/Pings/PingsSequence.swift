//
//  PingsAsyncIteratorProtocol.swift
//  RMBT
//
//  Created by Jiri Urbasek on 12/4/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import Foundation

// https://itnext.io/mocking-asyncsequence-in-unit-tests-a4cb6a0d5e59

//@rethrows protocol PingsAsyncIteratorProtocol: AsyncIteratorProtocol where Element == PingResult { }


struct PingResult: Hashable {
    enum Result: Hashable {
        case interval(Duration)
        case error
    }

    let result: Result
    let timestamp: Date
}

struct PingsSequence: PingsAsyncSequence, AsyncIteratorProtocol {
    protocol PingSending {
        func sendPing() async throws
    }

    private let pingSender: any PingSending
    private let clock: any Clock<Duration>
    private let now: () -> Date
    private let frequency: Duration

    init(
        pingSender: any PingSending,
        clock: any Clock<Duration>,
        now: @escaping () -> Date = Date.init,
        frequency: Duration
    ) {
        self.pingSender = pingSender
        self.clock = clock
        self.now = now
        self.frequency = frequency
    }

    mutating func next() async -> PingResult? {
        var capturedError: (any Error)? = nil
        let elapsed = await clock.measure {
            do {
                _ = try await pingSender.sendPing()
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

        return .init(
            result: capturedError.map { _ in .error } ?? .interval(elapsed),
            timestamp: now()
        )
    }

    func makeAsyncIterator() -> PingsSequence {
        self
    }
}

extension Duration {
    var milliseconds: Int64 {
        Int64(Double(components.attoseconds) / 1e15)
    }
}

struct HTTPPingSender: PingsSequence.PingSending {
    let pingURL: URL
    let urlSession: URLSession

    func sendPing() async throws {
        let request = URLRequest(url: pingURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        _ = try await urlSession.data(for: request)
    }
}
