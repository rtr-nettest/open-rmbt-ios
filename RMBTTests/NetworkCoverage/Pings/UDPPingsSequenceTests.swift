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
import Clocks

struct UDPPingsSequenceTests {
    @Test func whenInitializingPingSession_thenDoesNotReportAnyPings() async throws {
        let clock = TestClock()
        try await expect(
            makeSUT(
                clock: clock,
                pingsFrequency: .milliseconds(500),
                initiatePingSessionDelays: [("1", .seconds(1.7))],
                sendPingResults: [
                    .ms(100)
                ]
            ),
            receive: [
                (at: 2.1, makePingUpdate(ms: 100, startedAt: 2.0))
            ],
            after: .seconds(2.1),
            with: clock
        )
    }

    @Test func whenReceivingPingsShorterThenPingsFrequency_thenTheirTimestampDifferenceIsTheFrequency() async throws {
        let clock = TestClock()
        try await expect(
            makeSUT(
                clock: clock,
                pingsFrequency: .seconds(0.5),
                initiatePingSessionDelays: [("1", .seconds(0.2))],
                sendPingResults: [
                    .ms(50),
                    .ms(20),
                    .ms(120),
                    .ms(40),
                    .ms(250)
                ]
            ),
            receive: [
                (at: 0.55, makePingUpdate(ms:  50, startedAt: 0.5)),
                (at: 1.02, makePingUpdate(ms:  20, startedAt: 1)),
                (at: 1.62, makePingUpdate(ms: 120, startedAt: 1.5)),
                (at: 2.04, makePingUpdate(ms:  40, startedAt: 2.0)),
                (at: 2.75, makePingUpdate(ms: 250, startedAt: 2.5))
            ],
            after: .seconds(2.75),
            with: clock
        )
    }

    @Test func whenReceivingPingsLongerThenPingsFrequency_thenTheirTimestampDifferenceIsTheFrequency() async throws {
        let clock = TestClock()
        try await expect(
            makeSUT(
                clock: clock,
                pingsFrequency: .seconds(1),
                initiatePingSessionDelays: [("1", .seconds(1.1))],
                sendPingResults: [
                    .ms(300),
                    .ms(1200),
                    .ms(2700),
                    .ms(1300),
                    .ms(100),
                    .ms(700),
                    .ms(1400),
                    .ms(3800),
                    .ms(1400),
                    .ms(100),
                    .ms(600),
                    .ms(400)
                ]
            ),
            receive: [
                (at:  2.3, makePingUpdate(ms:  300, startedAt: 2)),
                (at:  4.2, makePingUpdate(ms: 1200, startedAt: 3)),
                (at:  6.1, makePingUpdate(ms:  100, startedAt: 6)),
                (at:  6.3, makePingUpdate(ms: 1300, startedAt: 5)),
                (at:  6.7, makePingUpdate(ms: 2700, startedAt: 4)),
                (at:  7.7, makePingUpdate(ms:  700, startedAt: 7)),
                (at:  9.4, makePingUpdate(ms: 1400, startedAt: 8)),
                (at: 11.1, makePingUpdate(ms:  100, startedAt: 11)),
                (at: 11.4, makePingUpdate(ms: 1400, startedAt: 10)),
                (at: 12.6, makePingUpdate(ms:  600, startedAt: 12)),
                (at: 12.8, makePingUpdate(ms: 3800, startedAt: 9)),
                (at: 13.4, makePingUpdate(ms:  400, startedAt: 13))
            ],
            after: .seconds(13.4),
            with: clock
        )
    }

    @Suite("Session Reinitialization")
    struct SessionReinitialization {
        @Test func whenMaxSessionDurationPasses_thenReinitializesSession() async throws {
            let clock = TestClock()
            // Two sessions. First starts at t=0 with 0.2s init delay, lasts 2.0s max. Second has 0.3s init delay.
            try await expect(
                makeSUT(
                    clock: clock,
                    pingsFrequency: .milliseconds(500),
                    initiatePingSessionDelays: [("1", .seconds(0.2)), ("2", .seconds(0.3))],
                    sendPingResults: [
                        .ms(100), .ms(100), .ms(100), .ms(100), .ms(100), // should cover first ~2.5s window
                        .ms(100), .ms(100)
                    ],
                    sessionMaxDurationSeconds: 2.0
                ),
                receive: [
                    // First ping after first init at 0.5s tick, emitted at 0.6s
                    (at: 0.6, makePingUpdate(ms: 100, startedAt: 0.5)),
                    (at: 1.1, makePingUpdate(ms: 100, startedAt: 1.0)),
                    (at: 1.6, makePingUpdate(ms: 100, startedAt: 1.5)),
                    // At 2.0s session limit reached; we reinit, no emission at 2.0s tick
                    // Next emission after reinit on 2.5s tick at 2.6s
                    (at: 2.6, makePingUpdate(ms: 100, startedAt: 2.5)),
                    (at: 3.1, makePingUpdate(ms: 100, startedAt: 3.0))
                ],
                after: .seconds(3.2),
                with: clock
            )
        }

        @Test func whenServerSignalsNeedsReinit_thenReinitializesSession() async throws {
            let clock = TestClock()
            try await expect(
                makeSUT(
                    clock: clock,
                    pingsFrequency: .milliseconds(500),
                    initiatePingSessionDelays: [("1", .seconds(0.2)), ("2", .seconds(0.3))],
                    sendPingResults: [
                        .ms(100),
                        .error(.needsReinitialization), // simulate RE01
                        .ms(100),
                        .ms(100)
                    ]
                ),
                receive: [
                    (at: 0.6, makePingUpdate(ms: 100, startedAt: 0.5)),
                    // 1.0s tick triggers needsReinit -> no emission at ~1.1s
                    // reinit at 1.5 tick with 0.3s delay, first emission at next tick (2.0) with 0.1s send -> 2.1
                    (at: 2.1, makePingUpdate(ms: 100, startedAt: 2.0)),
                    (at: 2.6, makePingUpdate(ms: 100, startedAt: 2.5))
                ],
                after: .seconds(2.7),
                with: clock
            )
        }
    }
}


func makeSUT(
    clock: some Clock<Duration>,
    firstInitializationDate: Date = Date(timeIntervalSinceReferenceDate: 0),
    pingsFrequency: Duration,
    initiatePingSessionDelays: [(PingSenderStub.PingSession, Duration)],
    sendPingResults: [PingResultType],
    sessionMaxDurationSeconds: TimeInterval? = nil
) -> some PingsAsyncSequence {
    let pingSender = PingSenderStub(
        clock: clock,
        initiatePingSessionDelays: initiatePingSessionDelays,
        sendPingResults: sendPingResults.map(makePingResult)
    )
    let sut = PingMeasurementService.pings2(
        clock: clock,
        pingSender: pingSender,
        now: { firstInitializationDate },
        frequency: pingsFrequency,
        sessionMaxDuration: { sessionMaxDurationSeconds }
    )

    return sut
}

func expect(
    _ sut: some PingsAsyncSequence,
    receive expectedElements: [(at: Double, PingResult)],
    after totalDuration: Duration,
    with clock: TestClock<Duration>
) async throws {
    var capturedElements: [PingResult] = []
    var capturedInstants: [TestClock<Duration>.Instant] = []
    await confirmation(expectedCount: expectedElements.count) { confirmation in
        Task {
            for try await element in sut {
                capturedInstants.append(clock.now)
                capturedElements.append(element)
                confirmation.confirm()
            }
        }
        await clock.advance(by: totalDuration)
    }

    #expect(capturedElements == expectedElements.map(\.1))
    #expect(capturedInstants.isEqual(to: expectedElements.map { TestClock.Instant(offset: Duration.seconds($0.0)) }))
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
            delay = .seconds(404)
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

func makePingUpdate(ms: Int, startedAt timeInterval: TimeInterval) -> PingResult {
    .init(result: PingResult.Result.interval(.milliseconds(ms)), timestamp: Date(timeIntervalSinceReferenceDate: timeInterval))
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

extension Duration {
    var absolute: Self {
        self >= .zero ? self : .milliseconds(-self.milliseconds)
    }
}

extension TestClock.Instant where Duration == Swift.Duration {
    func isEqual(to other: Self) -> Bool {
        self.duration(to: other).absolute < .nanoseconds(1)
    }
}

extension [TestClock<Duration>.Instant] {
    func isEqual(to other: Self) -> Bool {
        guard count == other.count else { return false }
        return zip(self, other).allSatisfy { $0.isEqual(to: $1) }
    }
}
