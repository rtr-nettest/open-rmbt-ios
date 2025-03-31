//
//  PingMeasurementService.swift
//  RMBT
//
//  Created by Jiri Urbasek on 12/12/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import Foundation
import Network
import AsyncAlgorithms

enum PingSendingError: Error {
    case timedOut
    case needsReinitialization
    case networkIssue
}

protocol PingSending<PingSession> {
    associatedtype PingSession

    func initiatePingSession() async throws -> PingSession
    func sendPing(in session: PingSession) async throws(PingSendingError)
}

struct PingResult: Hashable {
    enum Result: Hashable {
        case interval(Duration)
        case error
    }

    let result: Result
    let timestamp: Date
}

struct PingMeasurementService {
    enum PingSessionInitiationState<T> {
        case needsInitiation
        case inProgress
        case finished(T)
    }

    static func pings<T>(
        clock: some Clock<Duration>,
        pingSender: some PingSending<T>,
        now: @escaping () -> Date = Date.init,
        frequency: Duration
    ) -> some PingsAsyncSequence {
        var pingSessionState: PingSessionInitiationState<T> = .needsInitiation

        return chain(
            [clock.now].async,
            AsyncTimerSequence(interval: frequency, clock: clock)
        )
        .flatMap { element in
            do {
                switch pingSessionState {
                case .needsInitiation:
                    pingSessionState = .inProgress
                    let session = try await pingSender.initiatePingSession()
                    pingSessionState = .finished(session)
                    return [await pingResult(sender: pingSender, session: session, clock: clock, at: now())].async
                case .finished(let session):
                    return [await pingResult(sender: pingSender, session: session, clock: clock, at: now())].async
                case .inProgress:
                    // session initiation in progress error
                    return [PingResult(result: .error, timestamp: now())].async
                }
            } catch {
                // TODO: return invalid ping session error
                return [].async
            }
        }
    }

    static func pings2<T>(
        clock: some Clock<Duration>,
        pingSender: some PingSending<T>,
        now: @escaping () -> Date = Date.init,
        frequency: Duration
    ) -> some PingsAsyncSequence {
        var pingSessionState: PingSessionInitiationState<T> = .needsInitiation

        return AsyncStream { continuation in
            let start = clock.now
            let startDate = now()

            let task = Task {
                while true {
                    if Task.isCancelled { break }

                    let tick = clock.now
                    let duration = start.duration(to: tick)
                    let currentDate = startDate.advanced(by: TimeInterval(duration.milliseconds) / 1000)
                    let nextInstant = tick.advanced(by: frequency)

                    Task {
                        do {
                            try Task.checkCancellation()

                            switch pingSessionState {
                            case .needsInitiation:
                                pingSessionState = .inProgress
                                let session = try await pingSender.initiatePingSession()
                                pingSessionState = .finished(session)
                            case .finished(let session):
                                continuation.yield(await pingResult(sender: pingSender, session: session, clock: clock, at: currentDate))
                            case .inProgress:
                                break
                            }
                        } catch is CancellationError {
                            continuation.finish()
                        } catch {
                            // TODO: differentiate errors and eventually initialize new ping session
                            continuation.yield(PingResult(result: .error, timestamp: currentDate))
                        }
                    }

                    if Task.isCancelled { break }
                    try await clock.sleep(until: nextInstant, tolerance: .milliseconds(1))
                }

                // Below is a different implementation which works as well - need to examine which one is better (after unit tests are in place)

//                for await tick in chain(
//                    [clock.now].async,
//                    AsyncTimerSequence(interval: frequency, tolerance: .milliseconds(1), clock: clock)
//                ) {
//                    func currentDate() -> Date {
//                        let duration = startInstant.duration(to: clock.now)
//                        return startDate.advanced(by: TimeInterval(duration.milliseconds) / 1000)
//                    }
//                    do {
//                        try Task.checkCancellation()
//
//                        switch pingSessionState {
//                        case .needsInitiation:
//                            pingSessionState = .inProgress
//                            let session = try await pingSender.initiatePingSession()
//                            pingSessionState = .finished(session)
////                            continuation.yield(await pingResult(sender: pingSender, session: session, clock: clock, at: currentDate()))
//                        case .finished(let session):
//                            continuation.yield(await pingResult(sender: pingSender, session: session, clock: clock, at: currentDate()))
//                        case .inProgress:
//                            // session initiation in progress error, or do not yield anything until session is fully initialized
//                            //continuation.yield(PingResult(result: .error, timestamp: now()))
//                            break
//                        }
//                    } catch is CancellationError {
//                        continuation.finish()
//                    } catch {
//                        // TODO: return invalid ping session error
//                        continuation.yield(PingResult(result: .error, timestamp: currentDate()))
//                    }
//                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func pingResult<T>(
        sender: some PingSending<T>,
        session: T,
        clock: some Clock<Duration>,
        at date: Date
    ) async -> PingResult {
        var capturedError: (any Error)? = nil
        let elapsed = await clock.measure {
            do {
                try await sender.sendPing(in: session)
            } catch {
                capturedError = error
            }
        }
        return PingResult(
            result: capturedError.map { _ in .error } ?? .interval(elapsed),
            timestamp: date
        )
    }
}

extension UDPPingSession: /*PingsSequence.*/PingSending {}

extension AsyncFlatMapSequence: PingsAsyncSequence where Element == PingResult {}
//extension AsyncFlatMapSequence: AsynchronousSequence where Element == PingResult {}

extension AsyncStream: PingsAsyncSequence where Element == PingResult {}

extension Duration {
    var milliseconds: Int64 {
        components.seconds * 1000 + Int64(Double(components.attoseconds) / 1e15)
    }
}

extension CoverageMeasurementSessionInitializer: UDPPingSession.SessionInitiating {
    func initiate() async throws -> UDPPingSession.SessionInitiation {
        let sessionData = try await startNewSession().udpPing
        return .init(serverAddress: sessionData.pingHost, serverPort: sessionData.pingPort, token: sessionData.pingToken)
    }
}

struct MockSessionInitiator: UDPPingSession.SessionInitiating {
    func initiate() async throws -> UDPPingSession.SessionInitiation {
        return .init(
            serverAddress: "udp.netztest.at",
            serverPort: "444",
            token: "Z7kKKZqSYU/j7nSGbjoRLw=="
        )
    }
}
