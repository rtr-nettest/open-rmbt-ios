//
//  UDPPingsSequenceTests.swift
//  RMBTTest
//
//  Created by Jiri Urbasek on 18.02.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Testing
import Foundation
@testable import RMBT
import Network
import Clocks

struct UDPPingsSequenceTests {
    @Test func whenInitializingPingSession_thenDoesNotReportAnyPings() async throws {
        let delays = [makePingResult(.ms(100))]
        let clock = ContinuousClock()
        let sut = makeSUT(
            clock: clock,
            firstInitializationDate: Date(timeIntervalSinceReferenceDate: 0),
            pingsFrequency: .milliseconds(500),
            initiatePingSessionDelays: [("1", .seconds(1.7))],
            sendPingResults: delays
        )
        var capturedElements: [PingResult] = []
        var count = 0
        for try await element in sut {
            capturedElements.append(element)
            count += 1
            if count >= delays.count {
                break
            }
        }
        #expect(capturedElements.isEqual(to: [makePingResult(ms: 100, at: 2.0)]))
    }

    @Test func whenReceivingPingsShorterThenPingsFrequency_thenTheirTimestampDifferenceIsTheFrequency() async throws {
        let clock = ContinuousClock()
        let pingResults = [
            makePingResult(.ms(50)),
            makePingResult(.ms(20)),
            makePingResult(.ms(120)),
            makePingResult(.ms(40)),
            makePingResult(.ms(250))
        ]
        let sut = makeSUT(
            clock: clock,
            firstInitializationDate: Date(timeIntervalSinceReferenceDate: 0),
            pingsFrequency: .seconds(0.5),
            initiatePingSessionDelays: [("1", .seconds(0.2))],
            sendPingResults: pingResults
        )
        var capturedElements: [PingResult] = []
        var count = 0
        for try await element in sut {
            capturedElements.append(element)
            count += 1
            if count >= pingResults.count {
                break
            }
        }

        #expect(capturedElements.isEqual(to: [
            makePingResult(ms: 50, at: 0.5),
            makePingResult(ms: 20, at: 1),
            makePingResult(ms: 120, at: 1.5),
            makePingResult(ms: 40, at: 2.0),
            makePingResult(ms: 250, at: 2.5)
        ]))
    }

    @Test func whenReceivingPingsLongerThenPingsFrequency_thenTheirTimestampDifferenceIsTheFrequency() async throws {
        let clock = ContinuousClock()
        let pingResults = [
            makePingResult(.ms(300)),
            makePingResult(.ms(1200)),
            makePingResult(.ms(2700)),
            makePingResult(.ms(1300)),
            makePingResult(.ms(100)),
            makePingResult(.ms(700)),
            makePingResult(.ms(1400)),
            makePingResult(.ms(3800)),
            makePingResult(.ms(1400)),
            makePingResult(.ms(100)),
            makePingResult(.ms(600)),
            makePingResult(.ms(400))
        ]
        let sut = makeSUT(
            clock: clock,
            firstInitializationDate: Date(timeIntervalSinceReferenceDate: 0),
            pingsFrequency: .seconds(1),
            initiatePingSessionDelays: [("1", .seconds(1.1))],
            sendPingResults: pingResults
        )
        var capturedElements: [PingResult] = []
        var count = 0
        for try await element in sut {
            capturedElements.append(element)
            count += 1
            if count >= pingResults.count {
                break
            }
        }

        #expect(capturedElements.isEqual(to: [
            makePingResult(ms:  300, at: 2),
            makePingResult(ms: 1200, at: 3),
            makePingResult(ms:  100, at: 6),
            makePingResult(ms: 1300, at: 5),
            makePingResult(ms: 2700, at: 4),
            makePingResult(ms:  700, at: 7),
            makePingResult(ms: 1400, at: 8),
            makePingResult(ms:  100, at: 11),
            makePingResult(ms: 1400, at: 10),
            makePingResult(ms:  600, at: 12),
            makePingResult(ms: 3800, at: 9),
            makePingResult(ms:  400, at: 13)
        ]))
    }
}

extension UDPPingsSequenceTests {
    func makeSUT(
        clock: some Clock<Duration>,
        firstInitializationDate: Date,
        pingsFrequency: Duration,
        initiatePingSessionDelays: [(PingSenderStub.PingSession, Duration)],
        sendPingResults: [PingSenderStub.SendPingResult]
    ) -> some PingsAsyncSequence {
        let pingSender = PingSenderStub(
            clock: clock,
            initiatePingSessionDelays: initiatePingSessionDelays,
            sendPingResults: sendPingResults
        )

        let sut = PingMeasurementService.pings2(
            clock: clock,
            pingSender: pingSender,
            now: { firstInitializationDate },
            frequency: pingsFrequency
        )

        return sut
    }

    final class PingSenderStub: PingSending {
        typealias SendPingResult = Result<Duration, PingSendingError>

        private let clock: any Clock<Duration>
        private var initiatePingSessionDelays: [(PingSession, Duration)]
        private var sendPingResults: [SendPingResult]

        init(
            clock: any Clock<Duration>,
            initiatePingSessionDelays: [(PingSession, Duration)],
            sendPingResults: [SendPingResult]
        ) {
            self.clock = clock
            self.initiatePingSessionDelays = initiatePingSessionDelays
            self.sendPingResults = sendPingResults
        }

        func initiatePingSession() async throws -> String {
            let delay = initiatePingSessionDelays.removeFirst()
            try await clock.sleep(for: delay.1)
            return delay.0
        }
        
        func sendPing(in session: String) async throws(PingSendingError) {
            let delay: Duration
            if sendPingResults.isEmpty {
                delay = .nanoseconds(-1)
            } else {
                delay = try sendPingResults.removeFirst().get()
            }
            do {
                try await clock.sleep(for: delay)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    enum PingResultType {
        case ms(Int)
        case error(PingSendingError)
    }

    func makePingResult(_ result: PingResultType) -> PingSenderStub.SendPingResult {
        switch result {
        case .ms(let ms):
            return .success(.milliseconds(ms))
        case .error(let error):
            return .failure(error)
        }
    }

    func makePingResult(ms: Int, at timeInterval: TimeInterval) -> PingResult {
        .init(result: PingResult.Result.interval(.milliseconds(ms)), timestamp: Date(timeIntervalSinceReferenceDate: timeInterval))
    }
}

extension PingResult: @retroactive CustomTestStringConvertible, @retroactive CustomDebugStringConvertible {
    public var debugDescription: String { testDescription }

    public var testDescription: String {
        switch self.result {
        case .interval(let duration):
            "\(duration.milliseconds) ms at \(timestamp.timeIntervalSinceReferenceDate)"
        case .error:
            "error at \(timestamp.timeIntervalSinceReferenceDate)"
        }
    }
}

extension PingResult {
    /// Custom equality check because for purpose of the unit tests we want to use only limited precission on comparision of `timestamp`
    func isEqual(to other: PingResult) -> Bool {
        result.isEquual(to: other.result) &&
        timestamp.timeIntervalSinceReferenceDate - other.timestamp.timeIntervalSinceReferenceDate < 0.1
    }
}

extension PingResult.Result {
    func isEquual(to other: PingResult.Result) -> Bool {
        switch (self, other) {
        case (.interval(let lhsInterval), .interval(let rhsInterval)):
            return (lhsInterval - rhsInterval).absolute < .milliseconds(Double(lhsInterval.milliseconds) * 0.15)
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}

extension Duration {
    var absolute: Self {
        self >= .zero ? self : .milliseconds(-self.milliseconds)
    }
}
extension [PingResult] {
    func isEqual(to other: [PingResult]) -> Bool {
        guard count == other.count else { return false }
        return zip(self, other).allSatisfy { $0.isEqual(to: $1) }
    }
}

// MARK: - Attempt to implement custom "Immediate Clock" (not working properly yet)

public final class ManualClock: Clock, @unchecked Sendable {
    public var minimumResolution: Duration = .zero

    public struct Instant: InstantProtocol {
        var offset: Duration = .zero

        public func advanced(by duration: Duration) -> ManualClock.Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: ManualClock.Instant) -> Duration {
            other.offset - offset
        }

        public static func < (_ lhs: ManualClock.Instant, _ rhs: ManualClock.Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    struct WakeUp {
        var when: Instant
        var continuation: UnsafeContinuation<Void, Never>
    }

    public private(set) var now = Instant()

    // General storage for the sleep points we want to wake-up for
    // this could be optimized to be a more efficient data structure
    // as well as enforced for generation stability for ordering
    var wakeUps = [WakeUp]()

    // adjusting now or the wake-ups can be done from different threads/tasks
    // so they need to be treated as critical mutations
    let lock = os_unfair_lock_t.allocate(capacity: 1)

    private var willBeAdvancing = false

    deinit {
        lock.deallocate()
    }

    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        // Enqueue a pending wake-up into the list such that when
        try Task.checkCancellation()

        Task {
            guard !willBeAdvancing else { return }

            let closestDeadline = self.wakeUps
                .sorted { lhs, rhs in lhs.when < rhs.when }
                .first?.when ?? deadline

            advance(by: now.duration(to: closestDeadline))
        }
        return await withUnsafeContinuation {
            if deadline <= now {
                $0.resume()
            } else {
                os_unfair_lock_lock(lock)
                wakeUps.append(WakeUp(when: deadline, continuation: $0))
                os_unfair_lock_unlock(lock)
            }
        }
    }

    public func advance(by amount: Duration) {
        // step the now forward and gather all of the pending
        // wake-ups that are in need of execution
        os_unfair_lock_lock(lock)
        willBeAdvancing = true

        let finalNow = now.advanced(by: amount)

        var toService = [WakeUp]()
        for index in (0..<(wakeUps.count)).reversed() {
            let wakeUp = wakeUps[index]
            if wakeUp.when <= finalNow {
                toService.insert(wakeUp, at: 0)
                wakeUps.remove(at: index)
            }
        }
        os_unfair_lock_unlock(lock)

        // make sure to service them outside of the lock
        toService.sort { lhs, rhs -> Bool in
            lhs.when < rhs.when
        }
        for item in toService {
            os_unfair_lock_lock(lock)
            now = item.when
            os_unfair_lock_unlock(lock)
            item.continuation.resume()
        }

        os_unfair_lock_lock(lock)
        if now < finalNow {
            now = finalNow
        }

        if !wakeUps.isEmpty {
            willBeAdvancing = true

            Task {
                if let closestDeadline = (self.wakeUps
                    .sorted { lhs, rhs in lhs.when < rhs.when }
                    .first?.when) {
                        advance(by: now.duration(to: closestDeadline))
                    }
            }
        } else {
            willBeAdvancing = false
        }
        os_unfair_lock_unlock(lock)
    }
}
