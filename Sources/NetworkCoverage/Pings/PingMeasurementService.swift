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
    static func pings2<T>(
        clock: some Clock<Duration>,
        pingSender: some PingSending<T>,
        now: @escaping () -> Date = Date.init,
        frequency: Duration,
        sessionMaxDuration: @escaping () -> TimeInterval? = { nil }
    ) -> some PingsAsyncSequence {
        let state = PingSessionStateController<T>()

        return AsyncStream { continuation in
            let start = clock.now
            let startDate = now()

            let task = Task {
                await withDiscardingTaskGroup { group in
                    while !Task.isCancelled {
                        let tick = clock.now
                        let duration = start.duration(to: tick)
                        let currentDate = startDate.advanced(by: TimeInterval(duration.milliseconds) / 1000)
                        let nextInstant = tick.advanced(by: frequency)

                        group.addTask {
                            let action = await state.actionForTick(
                                at: currentDate,
                                sessionMaxDuration: sessionMaxDuration()
                            )

                            do {
                                try Task.checkCancellation()

                                switch action {
                                case .initiate(let generation):
                                    Log.logger.info("UDPPing: Initiating new ping session")
                                    let session = try await pingSender.initiatePingSession()
                                    await state.didInitiateSession(
                                        session,
                                        at: currentDate,
                                        generation: generation
                                    )
                                    Log.logger.info("UDPPing: Ping session initiated successfully")
                                case .send(let session, let generation):
                                    if let result = await pingResult(
                                        sender: pingSender,
                                        session: session,
                                        clock: clock,
                                        at: currentDate,
                                        reinitializeSession: {
                                            await state.requestReinitialization(for: generation)
                                        }
                                    ) {
                                        continuation.yield(result)
                                    }
                                case .skip:
                                    break
                                }
                            } catch is CancellationError {
                                return
                            } catch {
                                if case .initiate(let generation) = action {
                                    await state.didFailInitiation(generation: generation)
                                }
                                continuation.yield(PingResult(result: .error, timestamp: currentDate))
                            }
                        }

                        do {
                            try await clock.sleep(until: nextInstant, tolerance: .milliseconds(1))
                        } catch is CancellationError {
                            break
                        } catch {
                            break
                        }
                    }

                    group.cancelAll()
                }

                continuation.finish()
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
        at date: Date,
        reinitializeSession: () async -> Void
    ) async -> PingResult? {
        var capturedError: PingSendingError? = nil
        let elapsed = await clock.measure {
            do throws(PingSendingError) {
                try await sender.sendPing(in: session)
            } catch {
                capturedError = error
            }
        }
        if let capturedError {
            if capturedError == .needsReinitialization {
                Log.logger.info("UDPPing: Server responded with reinitialisation request (RE01), will start new session")
                await reinitializeSession()
                return nil
            } else {
                return PingResult(result: .error, timestamp: date)
            }
        } else {
            return PingResult(result: .interval(elapsed), timestamp: date)
        }
    }
}

private actor PingSessionStateController<Session> {
    enum TickAction {
        case initiate(generation: Int)
        case send(session: Session, generation: Int)
        case skip
    }

    private enum State {
        case needsInitiation
        case inProgress(generation: Int)
        case finished(session: Session, generation: Int, startedAt: Date)
    }

    private var state: State = .needsInitiation
    private var nextGeneration = 0

    func actionForTick(
        at currentDate: Date,
        sessionMaxDuration: TimeInterval?
    ) -> TickAction {
        if
            case let .finished(_, _, startedAt) = state,
            let sessionMaxDuration,
            currentDate.timeIntervalSince(startedAt) >= sessionMaxDuration
        {
            Log.logger.info(
                "UDPPing: Session timeout reached (\(sessionMaxDuration)s elapsed since \(startedAt)), requesting reinitialisation"
            )
            state = .needsInitiation
        }

        switch state {
        case .needsInitiation:
            nextGeneration += 1
            let generation = nextGeneration
            state = .inProgress(generation: generation)
            return .initiate(generation: generation)
        case .inProgress:
            return .skip
        case .finished(let session, let generation, _):
            return .send(session: session, generation: generation)
        }
    }

    func didInitiateSession(
        _ session: Session,
        at currentDate: Date,
        generation: Int
    ) {
        guard case .inProgress(let currentGeneration) = state, currentGeneration == generation else {
            return
        }
        state = .finished(session: session, generation: generation, startedAt: currentDate)
    }

    func didFailInitiation(generation: Int) {
        guard case .inProgress(let currentGeneration) = state, currentGeneration == generation else {
            return
        }
        state = .needsInitiation
    }

    func requestReinitialization(for generation: Int) {
        guard case .finished(_, let currentGeneration, _) = state, currentGeneration == generation else {
            return
        }
        state = .needsInitiation
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

extension OnlineAwareSessionInitializer: UDPPingSession.SessionInitiating {
    func initiate() async throws -> UDPPingSession.SessionInitiation {
        let sessionData = try await startNewSession(loopID: lastLoopUUID).udpPing
        return .init(
            serverAddress: sessionData.pingHost,
            serverPort: sessionData.pingPort,
            token: sessionData.pingToken,
            ipVersion: sessionData.ipVersion
        )
    }
}

struct MockSessionInitiator: UDPPingSession.SessionInitiating {
    func initiate() async throws -> UDPPingSession.SessionInitiation {
        return .init(
            serverAddress: "udp.netztest.at",
            serverPort: "444",
            token: "Z7kKKZqSYU/j7nSGbjoRLw==",
            ipVersion: nil
        )
    }
}
