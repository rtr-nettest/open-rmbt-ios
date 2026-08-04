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
                prepareSessionDelays: [("1", .seconds(1.7))],
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
                prepareSessionDelays: [("1", .seconds(0.2))],
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
                prepareSessionDelays: [("1", .seconds(1.1))],
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
                    prepareSessionDelays: [("1", .seconds(0.2)), ("2", .seconds(0.3))],
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
                    prepareSessionDelays: [("1", .seconds(0.2)), ("2", .seconds(0.3))],
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

        @Test func whenMultipleDelayedReinitializationSignalsArriveDuringReinit_thenStartsOnlyOneNewSession() async throws {
            let clock = TestClock()
            let pingSender = ReinitializationPingSenderSpy(
                clock: clock,
                prepareSessionSteps: [
                    .init(session: "S1", delay: .zero),
                    .init(session: "S2", delay: .milliseconds(600)),
                    .init(session: "S3", delay: .zero)
                ],
                sendPingSteps: [
                    .init(delay: .milliseconds(150), outcome: .failure(.needsReinitialization)),
                    .init(delay: .milliseconds(250), outcome: .failure(.needsReinitialization))
                ]
            )
            let sut = PingMeasurementService.pings2(
                clock: clock,
                pingSender: pingSender,
                now: { Date(timeIntervalSinceReferenceDate: 0) },
                frequency: .milliseconds(100)
            )

            let consumer = consume(sut)
            await clock.advance(by: .milliseconds(550))
            consumer.cancel()

            #expect(await pingSender.prepareSessionCallCount() == 2)
        }
    }

    @Suite("Wi-Fi pause")
    struct WiFiPause {
        @Test func whenOnWiFi_thenNoPingsAreSentNorReported() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(clock: clock, networkType: .wifi)
            let results = PingResultsCollector()

            let consumer = consume(sut, into: results)
            await advance(clock, by: .seconds(1))
            await finish(consumer)

            await expectPreparations(from: sender, [])
            #expect(results.captured.isEmpty)
        }

        @Test func whenStartedOnWiFi_thenExactlyOneSessionIsCreatedAfterCellularReturns() async throws {
            let clock = TestClock()
            let (sut, sender, network) = makeSUT(clock: clock, networkType: .wifi)
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(350))
            network.simulateNetworkType(.cellular)
            await advance(clock, by: .milliseconds(600))
            await finish(consumer)

            await expectPreparations(from: sender, [.milliseconds(400)])
            await expectSentSessions(from: sender, ["S1", "S1", "S1", "S1", "S1"])
        }

        @Test func whenSwitchedFromWiFiToCellular_thenPreparesNewSessionAndResumesPings() async throws {
            let clock = TestClock()
            let (sut, sender, network) = makeSUT(clock: clock)
            let results = PingResultsCollector()

            let consumer = consume(sut, into: results)
            await advance(clock, by: .milliseconds(150))
            network.simulateNetworkType(.wifi)
            await advance(clock, by: .milliseconds(200))
            network.simulateNetworkType(.cellular)
            await advance(clock, by: .milliseconds(300))
            await finish(consumer)

            await expectPreparations(from: sender, [.zero, .milliseconds(400)])
            await expectSentSessions(from: sender, ["S1", "S2", "S2"])
            #expect(results.captured == [
                makePingUpdate(ms: 0, startedAt: 0.1),
                makePingUpdate(ms: 0, startedAt: 0.5),
                makePingUpdate(ms: 0, startedAt: 0.6)
            ])
        }

        @Test func whenSwitchedFromWiFiToUnsatisfiedPath_thenKeepsReportingFailedPings() async throws {
            let clock = TestClock()
            let (sut, sender, network) = makeSUT(
                clock: clock,
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 100)
            )
            let results = PingResultsCollector()

            let consumer = consume(sut, into: results)
            await advance(clock, by: .milliseconds(250))
            network.simulateNetworkType(.wifi)
            await advance(clock, by: .milliseconds(200))
            network.simulateNetworkType(nil)
            await advance(clock, by: .milliseconds(300))
            await finish(consumer)

            await expectPreparations(from: sender, [.zero, .milliseconds(500)])
            #expect(results.captured == [
                makePingFailure(startedAt: 0.1),
                makePingFailure(startedAt: 0.2),
                makePingFailure(startedAt: 0.6),
                makePingFailure(startedAt: 0.7)
            ])
        }

        @Test func whenSuccessfulOutcomeCompletesWhilePausedOnWiFi_thenItIsNeitherCountedNorReported() async throws {
            let clock = TestClock()
            let (sut, sender, network) = makeSUT(clock: clock, send: [.succeeds(after: .milliseconds(250))])
            let results = PingResultsCollector()

            let consumer = consume(sut, into: results)
            await advance(clock, by: .milliseconds(250))
            network.simulateNetworkType(.wifi)
            await advance(clock, by: .milliseconds(350))
            await finish(consumer)

            #expect(results.captured.isEmpty)
            await expectPreparations(from: sender, [.zero])
        }

        @Test func whenFailedOutcomeCompletesWhilePausedOnWiFi_thenItIsNeitherCountedNorReported() async throws {
            let clock = TestClock()
            let (sut, sender, network) = makeSUT(
                clock: clock,
                send: [.fails(.networkIssue, after: .milliseconds(250))],
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 2)
            )
            let results = PingResultsCollector()

            let consumer = consume(sut, into: results)
            await advance(clock, by: .milliseconds(250))
            network.simulateNetworkType(.wifi)
            await advance(clock, by: .milliseconds(350))
            await finish(consumer)

            #expect(results.captured.isEmpty)
            await expectPreparations(from: sender, [.zero])
        }

        @Test func whenWiFiIsEnteredDuringPreparation_thenTheNewSessionIsRefreshedAfterwards() async throws {
            let clock = TestClock()
            let (sut, sender, network) = makeSUT(
                clock: clock,
                prepare: [.succeeds(after: .zero), .succeeds(after: .milliseconds(450)), .succeeds(after: .zero)],
                recovery: makeRecoveryPolicy(
                    maxConsecutiveFailures: 100,
                    initialBackoff: .milliseconds(500),
                    recoveryPrepareTimeout: .seconds(5)
                )
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(150))
            network.simulateNetworkType(.wifi)
            await advance(clock, by: .milliseconds(200))
            network.simulateNetworkType(.cellular)
            await advance(clock, by: .milliseconds(200))
            network.simulateNetworkType(.wifi)
            await advance(clock, by: .milliseconds(200))
            network.simulateNetworkType(.cellular)
            await advance(clock, by: .milliseconds(200))
            await finish(consumer)

            await expectPreparations(from: sender, [.zero, .milliseconds(400), .milliseconds(900)])
            await expectActivatedSessions(from: sender, ["S1", "S2", "S3"])
        }

        @Test func whenWiFiFlapsRepeatedly_thenOnlyOneRecoveryPerBackoffWindow() async throws {
            let clock = TestClock()
            let (sut, sender, network) = makeSUT(
                clock: clock,
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 100, initialBackoff: .milliseconds(500))
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(150))
            for _ in 0..<3 {
                network.simulateNetworkType(.wifi)
                await advance(clock, by: .milliseconds(100))
                network.simulateNetworkType(.cellular)
                await advance(clock, by: .milliseconds(100))
            }
            await advance(clock, by: .milliseconds(200))
            await finish(consumer)

            // One recovery when the window was open, the two Wi-Fi epochs owed in the meantime coalesce
            // into a single deferred recovery once the backoff window elapses.
            await expectPreparations(from: sender, [.zero, .milliseconds(300), .milliseconds(800)])
        }

        @Test func whenOldSessionPingSucceedsWhileWiFiRecoveryIsOwed_thenRecoveryStillHappens() async throws {
            let clock = TestClock()
            let (sut, sender, network) = makeSUT(
                clock: clock,
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 1, initialBackoff: .milliseconds(800))
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(250))
            await sender.simulateSendBehavior(.succeeds(after: .zero))
            await advance(clock, by: .milliseconds(100))
            network.simulateNetworkType(.wifi)
            await advance(clock, by: .milliseconds(100))
            network.simulateNetworkType(.cellular)
            await advance(clock, by: .milliseconds(600))
            await finish(consumer)

            // A working old session does not satisfy the Wi-Fi refresh: its `ip_version` may be wrong for
            // the new path, so the owed recovery still fires once the backoff window elapses.
            await expectPreparations(from: sender, [.zero, .milliseconds(200), .milliseconds(1000)])
        }
    }

    @Suite("Failure recovery")
    struct FailureRecovery {
        @Test func whenUsingDefaultRecoveryPolicy_thenThresholdAndBackoffLadderMatchAgreedValues() {
            #expect(RecoveryPolicy.default.maxConsecutiveFailures == 30)
            #expect(RecoveryPolicy.default.initialBackoff == .seconds(10))
            #expect(RecoveryPolicy.default.maxBackoff == .seconds(120))
            #expect(RecoveryPolicy.default.recoveryPrepareTimeout == .seconds(15))
            // The activation gap is the only window in which nothing can send, so it is bounded far tighter
            // than the credentials fetch.
            #expect(RecoveryPolicy.default.activationTimeout == .seconds(5))
        }

        @Test func whenConsecutiveFailuresReachThreshold_thenPreparesNewSession() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 3)
            )
            let results = PingResultsCollector()

            let consumer = consume(sut, into: results)
            await advance(clock, by: .milliseconds(450))
            await finish(consumer)

            await expectPreparations(from: sender, [.zero, .milliseconds(400)])
            #expect(results.captured == [
                makePingFailure(startedAt: 0.1),
                makePingFailure(startedAt: 0.2),
                makePingFailure(startedAt: 0.3)
            ])
        }

        @Test func whenFailuresStayBelowThreshold_thenDoesNotRecover() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                send: [
                    .fails(.networkIssue, after: .zero),
                    .fails(.timedOut, after: .zero),
                    .succeeds(after: .zero)
                ],
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 3)
            )
            let consumer = consume(sut)
            await advance(clock, by: .seconds(1))
            await finish(consumer)

            await expectPreparations(from: sender, [.zero])
        }

        @Test func whenPingSucceedsBetweenFailures_thenFailureCountResets() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                send: [
                    .fails(.networkIssue, after: .zero),
                    .fails(.networkIssue, after: .zero),
                    .succeeds(after: .zero),
                    .fails(.timedOut, after: .zero),
                    .fails(.timedOut, after: .zero),
                    .succeeds(after: .zero)
                ],
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 3)
            )
            let consumer = consume(sut)
            await advance(clock, by: .seconds(1))
            await finish(consumer)

            await expectPreparations(from: sender, [.zero])
        }

        @Test func whenFailuresPersist_thenRecoveriesFollowTheBackoffLadder() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(
                    maxConsecutiveFailures: 1,
                    initialBackoff: .milliseconds(200),
                    maxBackoff: .milliseconds(800)
                )
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(2450))
            await finish(consumer)

            // First recovery is immediate, then the delay doubles until it is capped at `maxBackoff`.
            await expectPreparations(from: sender, [
                .zero,
                .milliseconds(200),
                .milliseconds(400),
                .milliseconds(800),
                .milliseconds(1600),
                .milliseconds(2400)
            ])
        }

        @Test func whenPingSucceedsAfterRecovery_thenBackoffLadderRestartsFromTheInitialDelay() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(
                    maxConsecutiveFailures: 1,
                    initialBackoff: .milliseconds(300),
                    maxBackoff: .milliseconds(1200)
                )
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(1150))
            await sender.simulateSendBehavior(.succeeds(after: .zero))
            await advance(clock, by: .milliseconds(400))
            await sender.simulateSendBehavior(.fails(.networkIssue, after: .zero))
            await advance(clock, by: .milliseconds(500))
            await finish(consumer)

            // The ladder had climbed to its 1200 ms cap; without the reset the recovery following the
            // resumed failures could not have happened before 2300 ms.
            await expectPreparations(from: sender, [
                .zero,
                .milliseconds(200),
                .milliseconds(500),
                .milliseconds(1100),
                .milliseconds(1700),
                .milliseconds(2000)
            ])
        }

        @Test func whenPingSucceedsWhileRecoveryPreparationIsInFlight_thenAFailedPreparationDoesNotRetry() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                prepare: [.succeeds(after: .zero), .fails(after: .milliseconds(350))],
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(
                    maxConsecutiveFailures: 1,
                    initialBackoff: .milliseconds(500),
                    recoveryPrepareTimeout: .seconds(5)
                )
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(250))
            await sender.simulateSendBehavior(.succeeds(after: .zero))
            await advance(clock, by: .milliseconds(950))
            await finish(consumer)

            // The path recovered on its own while the replacement was being fetched, so the failed preparation must
            // not resurrect the failure cause it was launched for and try again.
            await expectPreparations(from: sender, [.zero, .milliseconds(200)])
        }

        @Test func whenSuccessCompletesBetweenTwoFailures_thenTheFailureRunRestartsFromThatCompletion() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                send: [
                    .fails(.networkIssue, after: .milliseconds(250)),
                    .succeeds(after: .zero),
                    .fails(.networkIssue, after: .milliseconds(250))
                ],
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 2)
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(650))
            await finish(consumer)

            // The ping started second completes first and succeeds, so the two failures around it are not
            // consecutive *completions* and the threshold is only reached once the second failure lands (0.55).
            await expectPreparations(from: sender, [.zero, .milliseconds(600)])
        }

        @Test func whenOutcomesCompleteOutOfOrder_thenConsecutiveFailuresFollowCompletionOrder() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                send: [
                    .succeeds(after: .milliseconds(350)),
                    .fails(.networkIssue, after: .zero),
                    .fails(.networkIssue, after: .zero),
                    .succeeds(after: .zero)
                ],
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 2)
            )
            let results = PingResultsCollector()

            let consumer = consume(sut, into: results)
            await advance(clock, by: .milliseconds(480))
            await finish(consumer)

            // "Consecutive" means consecutive completions: the recovery is not held back by the ping that
            // was started first but completes last.
            await expectPreparations(from: sender, [.zero, .milliseconds(400)])
            #expect(results.captured == [
                makePingFailure(startedAt: 0.2),
                makePingFailure(startedAt: 0.3)
            ])
        }
    }

    @Suite("Recovery must not silence the measurement")
    struct RecoveryKeepsMeasuring {
        @Test func whenRecoveryPreparationIsInFlight_thenOldSessionKeepsReportingPings() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                prepare: [.succeeds(after: .zero), .succeeds(after: .milliseconds(650))],
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 3, recoveryPrepareTimeout: .seconds(5))
            )
            let results = PingResultsCollector()

            let consumer = consume(sut, into: results)
            await advance(clock, by: .milliseconds(450))
            await sender.simulateSendBehavior(.succeeds(after: .zero))
            await advance(clock, by: .milliseconds(530))
            await finish(consumer)

            await expectSentSessions(from: sender, ["S1", "S1", "S1", "S1", "S1", "S1", "S1", "S1"])
            #expect(results.captured == [
                makePingFailure(startedAt: 0.1),
                makePingFailure(startedAt: 0.2),
                makePingFailure(startedAt: 0.3),
                makePingUpdate(ms: 0, startedAt: 0.5),
                makePingUpdate(ms: 0, startedAt: 0.6),
                makePingUpdate(ms: 0, startedAt: 0.7),
                makePingUpdate(ms: 0, startedAt: 0.8),
                makePingUpdate(ms: 0, startedAt: 0.9)
            ])
        }

        @Test func whenRecoveryPreparationNeverCompletes_thenItTimesOutAndOldSessionSurvives() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                prepare: [.succeeds(after: .zero), .neverCompletes, .succeeds(after: .zero)],
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(
                    maxConsecutiveFailures: 3,
                    initialBackoff: .milliseconds(500),
                    recoveryPrepareTimeout: .milliseconds(450)
                )
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(1050))
            await finish(consumer)

            await expectPreparations(from: sender, [.zero, .milliseconds(400), .milliseconds(900)])
            await expectSentSessions(from: sender, ["S1", "S1", "S1", "S1", "S1", "S1", "S1", "S3"])
        }

        @Test func whenRecoveryPreparationFails_thenRetryIsScheduledForTheNextSlot() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                prepare: [.succeeds(after: .zero), .fails(after: .zero), .succeeds(after: .zero)],
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 3, initialBackoff: .milliseconds(500))
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(1050))
            await finish(consumer)

            await expectPreparations(from: sender, [.zero, .milliseconds(400), .milliseconds(900)])
            await expectSentSessions(from: sender, ["S1", "S1", "S1", "S1", "S1", "S1", "S1", "S3"])
        }

        @Test func whenActivationFailsAfterCommittedPreparation_thenRetryIsGatedAndOldSessionIsNotResurrected() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                activate: [.succeeds, .fails, .succeeds],
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(
                    maxConsecutiveFailures: 3,
                    initialBackoff: .milliseconds(500),
                    retryDelay: .milliseconds(300)
                )
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(1050))
            await finish(consumer)

            // The retry is gated to `retryDelay` after the attempt was launched (0.4 + 0.3).
            await expectPreparations(from: sender, [.zero, .milliseconds(400), .milliseconds(700)])
            await expectActivatedSessions(from: sender, ["S1", "S2", "S3"])
            // Nothing is sent between the failed activation and the gated retry — the committed session
            // is never resurrected, because its `test_uuid` has already been superseded.
            await expectSentSessions(from: sender, ["S1", "S1", "S1", "S3", "S3", "S3"])
        }

        @Test func whenStaleFailureFromPreviousSessionArrives_thenNeitherCountedNorReported() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                prepare: [.succeeds(after: .zero), .succeeds(after: .milliseconds(350))],
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 1, initialBackoff: .milliseconds(500))
            )
            let results = PingResultsCollector()

            let consumer = consume(sut, into: results)
            await advance(clock, by: .milliseconds(250))
            await sender.simulateSendBehavior(.fails(.networkIssue, after: .milliseconds(450)))
            await advance(clock, by: .milliseconds(730))
            await finish(consumer)

            // The pings started in the previous session complete after its replacement was committed. Had
            // they been counted, the threshold of 1 would have produced a third preparation.
            await expectPreparations(from: sender, [.zero, .milliseconds(200)])
            #expect(results.captured == [makePingFailure(startedAt: 0.1)])
        }

        @Test func whenStaleSuccessFromPreviousSessionArrives_thenItIsNotReported() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                prepare: [.succeeds(after: .zero), .succeeds(after: .milliseconds(350))],
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 1, initialBackoff: .milliseconds(500))
            )
            let results = PingResultsCollector()

            let consumer = consume(sut, into: results)
            await advance(clock, by: .milliseconds(250))
            await sender.simulateSendBehavior(.succeeds(after: .milliseconds(450)))
            await advance(clock, by: .milliseconds(730))
            await finish(consumer)

            await expectPreparations(from: sender, [.zero, .milliseconds(200)])
            #expect(results.captured == [makePingFailure(startedAt: 0.1)])
        }

        @Test func whenActivationNeverCompletes_thenItTimesOutAndSessionIsRetried() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                activate: [.succeeds, .neverCompletes, .succeeds],
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(
                    maxConsecutiveFailures: 3,
                    initialBackoff: .milliseconds(500),
                    recoveryPrepareTimeout: .milliseconds(450),
                    retryDelay: .milliseconds(300)
                )
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(1050))
            await finish(consumer)

            // A hung activation must not silence the run forever: it is bounded like the preparation. The attempt
            // spent longer failing (450 ms) than `retryDelay`, so the retry happens at the next tick after it gave up.
            await expectPreparations(from: sender, [.zero, .milliseconds(400), .milliseconds(900)])
            await expectActivatedSessions(from: sender, ["S1", "S2", "S3"])
            await expectSentSessions(from: sender, ["S1", "S1", "S1", "S3"])
        }

        @Test func whenFirstActivationNeverCompletes_thenItTimesOutAndPreparationIsRetried() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                activate: [.neverCompletes, .succeeds],
                recovery: makeRecoveryPolicy(
                    recoveryPrepareTimeout: .milliseconds(450),
                    retryDelay: .milliseconds(300)
                )
            )
            let consumer = consume(sut)

            await advance(clock, by: .milliseconds(750))
            await finish(consumer)

            // Only the very first *credentials fetch* may park (offline start). Activation runs after the device is
            // demonstrably online, so a route-less UDP path must not be able to silence the whole run.
            await expectPreparations(from: sender, [.zero, .milliseconds(500)])
            await expectActivatedSessions(from: sender, ["S1", "S2"])
            await expectSentSessions(from: sender, ["S2", "S2"])
        }

        @Test func whenFirstPreparationFails_thenRetriesAfterRetryDelayAndReportsNothing() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                prepare: [.fails(after: .zero)],
                recovery: makeRecoveryPolicy(retryDelay: .milliseconds(300))
            )
            let results = PingResultsCollector()

            let consumer = consume(sut, into: results)
            await advance(clock, by: .milliseconds(750))
            await finish(consumer)

            // Retries are gated instead of hammering /coverageRequest at the 10 Hz cadence, and a preparation
            // failure reports no ping at all — nothing was measured, so there is no failed ping to report either.
            await expectPreparations(from: sender, [.zero, .milliseconds(300), .milliseconds(600)])
            #expect(results.captured.isEmpty)
            await expectSentSessions(from: sender, [])
        }

        @Test func whenStaleReinitializationSignalArrives_thenCurrentSessionIsNotHardCut() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                prepare: [.succeeds(after: .zero), .succeeds(after: .milliseconds(350))],
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 1, initialBackoff: .milliseconds(500))
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(250))
            // These land after the replacement has been committed, so they belong to a session no longer in use.
            await sender.simulateSendBehavior(.fails(.needsReinitialization, after: .milliseconds(450)))
            await advance(clock, by: .milliseconds(480))
            await finish(consumer)

            // A stale RE01 must not hard-cut the session that replaced its own — that would drop a healthy session.
            await expectPreparations(from: sender, [.zero, .milliseconds(200)])
            await expectActivatedSessions(from: sender, ["S1", "S2"])
        }

        @Test func whenFailureThresholdIsCrossedWhilePreparationIsInFlight_thenNoSecondPreparationStarts() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                prepare: [.succeeds(after: .zero), .succeeds(after: .milliseconds(650))],
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(
                    maxConsecutiveFailures: 1,
                    initialBackoff: .milliseconds(200),
                    recoveryPrepareTimeout: .seconds(5)
                )
            )
            let results = PingResultsCollector()

            let consumer = consume(sut, into: results)
            await advance(clock, by: .milliseconds(750))
            await finish(consumer)

            // The old session keeps failing throughout the preparation and the backoff window elapses, yet only one
            // /coverageRequest is ever in flight — the recovery gate requires an active session.
            await expectPreparations(from: sender, [.zero, .milliseconds(200)])
            #expect(results.captured.allSatisfy { $0.result == .error })
        }

        @Test(.timeLimit(.minutes(1)))
        func whenStoppedDuringPendingRecovery_thenSequenceTerminates() async throws {
            let clock = TestClock()
            let (sut, _, _) = makeSUT(
                clock: clock,
                prepare: [.succeeds(after: .zero), .neverCompletes],
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 1)
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(300))

            // `finish` returning at all is the assertion: the sequence terminated instead of hanging on the
            // preparation that never completes.
            await finish(consumer)
        }
    }

    @Suite("Hard cuts interacting with recovery")
    struct HardCuts {
        @Test func whenRE01ArrivesDuringPreparation_thenOldSessionStopsAndOnlyOneRequestIsInFlight() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                prepare: [.succeeds(after: .zero), .succeeds(after: .milliseconds(450))],
                send: [.fails(.networkIssue, after: .zero)],
                recovery: makeRecoveryPolicy(
                    maxConsecutiveFailures: 1,
                    initialBackoff: .milliseconds(500),
                    recoveryPrepareTimeout: .seconds(5)
                )
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(250))
            await sender.simulateSendBehavior(.fails(.needsReinitialization, after: .zero))
            await advance(clock, by: .milliseconds(470))
            await finish(consumer)

            // The rejected session stops being used right away, but the preparation already in flight is
            // kept — a hard cut must never start a second `/coverageRequest`.
            await expectPreparations(from: sender, [.zero, .milliseconds(200)])
            await expectSentSessions(from: sender, ["S1", "S1", "S2"])
        }

        @Test func whenMeasurementDurationExpiresDuringPreparation_thenSameCandidateIsKept() async throws {
            let clock = TestClock()
            let (sut, sender, _) = makeSUT(
                clock: clock,
                prepare: [.succeeds(after: .zero), .succeeds(after: .milliseconds(450))],
                send: [.fails(.networkIssue, after: .zero)],
                sessionMaxDuration: 0.55,
                recovery: makeRecoveryPolicy(
                    maxConsecutiveFailures: 1,
                    initialBackoff: .milliseconds(500),
                    recoveryPrepareTimeout: .seconds(5)
                )
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(720))
            await finish(consumer)

            await expectPreparations(from: sender, [.zero, .milliseconds(200)])
            await expectSentSessions(from: sender, ["S1", "S1", "S1", "S1", "S2"])
        }

        @Test func whenMeasurementDurationExpiresWhilePausedOnWiFi_thenHardCutStillApplies() async throws {
            let clock = TestClock()
            let (sut, sender, network) = makeSUT(
                clock: clock,
                sessionMaxDuration: 0.55,
                recovery: makeRecoveryPolicy(maxConsecutiveFailures: 100, initialBackoff: .milliseconds(500))
            )
            let consumer = consume(sut)
            await advance(clock, by: .milliseconds(150))
            network.simulateNetworkType(.wifi)
            await advance(clock, by: .milliseconds(700))
            network.simulateNetworkType(.cellular)
            await advance(clock, by: .milliseconds(200))
            await finish(consumer)

            // The expired session is dropped at the first non-Wi-Fi tick and the fresh credentials that
            // follow also settle the Wi-Fi refresh — exactly one new session, not two.
            await expectPreparations(from: sender, [.zero, .milliseconds(900)])
            await expectSentSessions(from: sender, ["S1", "S2"])
        }
    }
}

// MARK: - makeSUT & Factories

func makeSUT(
    clock: some Clock<Duration>,
    firstInitializationDate: Date = Date(timeIntervalSinceReferenceDate: 0),
    pingsFrequency: Duration,
    prepareSessionDelays: [(PingSenderStub.PingSession, Duration)],
    sendPingResults: [PingResultType],
    sessionMaxDurationSeconds: TimeInterval? = nil
) -> some PingsAsyncSequence {
    let pingSender = PingSenderStub(
        clock: clock,
        prepareSessionDelays: prepareSessionDelays,
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

private func makeSUT(
    clock: TestClock<Duration>,
    frequency: Duration = .milliseconds(100),
    prepare: [PingSenderSpy.PrepareBehavior] = [.succeeds(after: .zero)],
    activate: [PingSenderSpy.ActivateBehavior] = [.succeeds],
    send: [PingSenderSpy.SendBehavior] = [.succeeds(after: .zero)],
    networkType: NetworkTypeUpdate.NetworkConnectionType? = .cellular,
    sessionMaxDuration: TimeInterval? = nil,
    recovery: RecoveryPolicy = makeRecoveryPolicy()
) -> (sut: some PingsAsyncSequence, sender: PingSenderSpy, network: NetworkTypeProviderStub) {
    let sender = PingSenderSpy(
        clock: clock,
        prepareBehaviors: prepare,
        activateBehaviors: activate,
        sendBehaviors: send
    )
    let network = NetworkTypeProviderStub(networkType: networkType)
    let sut = PingMeasurementService.pings2(
        clock: clock,
        pingSender: sender,
        now: { Date(timeIntervalSinceReferenceDate: 0) },
        frequency: frequency,
        sessionMaxDuration: { sessionMaxDuration },
        networkTypeProvider: network,
        recovery: recovery
    )
    return (sut, sender, network)
}

/// Advances the test clock in small steps, settling after each one, so that the task hops behind every cadence tick
/// (decide action → child task → sender → controller) complete before the next tick fires. Advancing in one jump
/// leaves it up to the scheduler whether a tick's chain finishes before the following tick, which makes assertions
/// on exact preparation offsets nondeterministic.
private func advance(_ clock: TestClock<Duration>, by duration: Duration) async {
    let step = Duration.milliseconds(10)
    var remaining = duration
    while remaining > .zero {
        let nextStep = min(step, remaining)
        await clock.advance(by: nextStep)
        await clock.advance(by: .zero)
        remaining -= nextStep
    }
    await clock.advance(by: .zero)
}

/// Stops the sequence and waits for the consumer to finish, so results already yielded are never missed.
private func finish(_ consumer: Task<Void, Never>) async {
    consumer.cancel()
    await consumer.value
}

private func expectPreparations(
    from sender: PingSenderSpy,
    _ expectedOffsets: [Duration],
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let offsets = await sender.preparationOffsets
    #expect(offsets == expectedOffsets, sourceLocation: sourceLocation)
}

private func expectSentSessions(
    from sender: PingSenderSpy,
    _ expectedSessions: [String],
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let sessions = await sender.sentSessions
    #expect(sessions == expectedSessions, sourceLocation: sourceLocation)
}

private func expectActivatedSessions(
    from sender: PingSenderSpy,
    _ expectedSessions: [String],
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let sessions = await sender.activatedSessions
    #expect(sessions == expectedSessions, sourceLocation: sourceLocation)
}

private func makeRecoveryPolicy(
    maxConsecutiveFailures: Int = 3,
    initialBackoff: Duration = .milliseconds(500),
    maxBackoff: Duration = .seconds(2),
    recoveryPrepareTimeout: Duration = .milliseconds(450),
    activationTimeout: Duration? = nil,
    retryDelay: Duration = .milliseconds(300)
) -> RecoveryPolicy {
    .init(
        maxConsecutiveFailures: maxConsecutiveFailures,
        initialBackoff: initialBackoff,
        maxBackoff: maxBackoff,
        recoveryPrepareTimeout: recoveryPrepareTimeout,
        activationTimeout: activationTimeout ?? recoveryPrepareTimeout,
        retryDelay: retryDelay
    )
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
        let consumer = Task {
            for try await element in sut {
                capturedInstants.append(clock.now)
                capturedElements.append(element)
                confirmation.confirm()
            }
        }
        await advance(clock, by: totalDuration)
        consumer.cancel()
        _ = await consumer.result
    }

    #expect(capturedElements == expectedElements.map(\.1))
    #expect(capturedInstants.isEqual(to: expectedElements.map { TestClock.Instant(offset: Duration.seconds($0.0)) }))
}

func consume(_ sut: some PingsAsyncSequence) -> Task<Void, Never> {
    Task {
        do {
            for try await _ in sut {}
        } catch {}
    }
}

private func consume(_ sut: some PingsAsyncSequence, into collector: PingResultsCollector) -> Task<Void, Never> {
    Task {
        do {
            for try await element in sut { collector.append(element) }
        } catch {}
    }
}

func makePingUpdate(ms: Int, startedAt timeInterval: TimeInterval) -> PingResult {
    .init(result: PingResult.Result.interval(.milliseconds(ms)), timestamp: Date(timeIntervalSinceReferenceDate: timeInterval))
}

func makePingFailure(startedAt timeInterval: TimeInterval) -> PingResult {
    .init(result: .error, timestamp: Date(timeIntervalSinceReferenceDate: timeInterval))
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

// MARK: - Test Doubles

final class PingResultsCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [PingResult] = []

    var captured: [PingResult] {
        lock.lock()
        defer { lock.unlock() }
        return elements
    }

    func append(_ element: PingResult) {
        lock.lock()
        defer { lock.unlock() }
        elements.append(element)
    }
}

final class NetworkTypeProviderStub: CurrentNetworkTypeProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var networkType: NetworkTypeUpdate.NetworkConnectionType?

    init(networkType: NetworkTypeUpdate.NetworkConnectionType?) {
        self.networkType = networkType
    }

    func currentNetworkType() -> NetworkTypeUpdate.NetworkConnectionType? {
        lock.lock()
        defer { lock.unlock() }
        return networkType
    }

    func simulateNetworkType(_ type: NetworkTypeUpdate.NetworkConnectionType?) {
        lock.lock()
        defer { lock.unlock() }
        networkType = type
    }
}

/// Scripted two-phase ping sender. Behaviour arrays are consumed in order; the last element keeps
/// repeating, so `[.succeeds(after: .zero)]` means "always succeeds immediately".
actor PingSenderSpy: PingSending {
    typealias PingSession = String

    enum CapturedMessage: Equatable {
        case prepare
        case activate(session: PingSession)
        case send(session: PingSession)
    }

    enum PrepareBehavior: Sendable {
        case succeeds(after: Duration)
        case fails(after: Duration)
        case neverCompletes
    }

    enum ActivateBehavior: Sendable {
        case succeeds
        case fails
        case neverCompletes
    }

    enum SendBehavior: Sendable {
        case succeeds(after: Duration)
        case fails(PingSendingError, after: Duration)
    }

    private struct SpyError: Error {}

    private let clock: TestClock<Duration>
    private var prepareBehaviors: [PrepareBehavior]
    private var activateBehaviors: [ActivateBehavior]
    private var sendBehaviors: [SendBehavior]

    private(set) var capturedMessages: [CapturedMessage] = []
    private(set) var preparationOffsets: [Duration] = []

    init(
        clock: TestClock<Duration>,
        prepareBehaviors: [PrepareBehavior],
        activateBehaviors: [ActivateBehavior],
        sendBehaviors: [SendBehavior]
    ) {
        precondition(!prepareBehaviors.isEmpty && !activateBehaviors.isEmpty && !sendBehaviors.isEmpty)
        self.clock = clock
        self.prepareBehaviors = prepareBehaviors
        self.activateBehaviors = activateBehaviors
        self.sendBehaviors = sendBehaviors
    }

    var activatedSessions: [PingSession] {
        capturedMessages.compactMap { if case .activate(let session) = $0 { session } else { nil } }
    }

    var sentSessions: [PingSession] {
        capturedMessages.compactMap { if case .send(let session) = $0 { session } else { nil } }
    }

    func simulateSendBehavior(_ behavior: SendBehavior) {
        sendBehaviors = [behavior]
    }

    func prepareSession() async throws -> PingSession {
        capturedMessages.append(.prepare)
        preparationOffsets.append(TestClock<Duration>.Instant().duration(to: clock.now))
        let session = "S\(preparationOffsets.count)"

        switch next(&prepareBehaviors) {
        case .succeeds(let delay):
            try await clock.sleep(for: delay)
            return session
        case .fails(let delay):
            try await clock.sleep(for: delay)
            throw SpyError()
        case .neverCompletes:
            try await clock.sleep(for: .seconds(60 * 60))
            throw SpyError()
        }
    }

    func activateSession(_ session: PingSession) async throws {
        capturedMessages.append(.activate(session: session))
        switch next(&activateBehaviors) {
        case .succeeds:
            return
        case .fails:
            throw SpyError()
        case .neverCompletes:
            try await clock.sleep(for: .seconds(60 * 60))
            throw SpyError()
        }
    }

    func sendPing(in session: PingSession) async throws(PingSendingError) {
        capturedMessages.append(.send(session: session))
        switch next(&sendBehaviors) {
        case .succeeds(let delay):
            await sleepIgnoringCancellation(for: delay)
        case .fails(let error, let delay):
            await sleepIgnoringCancellation(for: delay)
            throw error
        }
    }

    private func sleepIgnoringCancellation(for delay: Duration) async {
        try? await clock.sleep(for: delay)
    }

    private func next<Behavior>(_ behaviors: inout [Behavior]) -> Behavior {
        behaviors.count > 1 ? behaviors.removeFirst() : behaviors[0]
    }
}

actor PingSenderStub: PingSending {
    typealias SendPingResult = Result<Duration, PingSendingError>
    typealias PingSession = String

    private let clock: any Clock<Duration>
    private var prepareSessionDelays: [(PingSession, Duration)]
    private var sendPingResults: [SendPingResult]

    init(
        clock: any Clock<Duration>,
        prepareSessionDelays: [(PingSession, Duration)],
        sendPingResults: [SendPingResult]
    ) {
        self.clock = clock
        self.prepareSessionDelays = prepareSessionDelays
        self.sendPingResults = sendPingResults
    }

    func prepareSession() async throws -> String {
        let delay = prepareSessionDelays.removeFirst()
        try await clock.sleep(for: delay.1)
        return delay.0
    }

    func activateSession(_ session: String) async throws {}

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

actor ReinitializationPingSenderSpy: PingSending {
    struct PrepareSessionStep {
        let session: String
        let delay: Duration
    }

    struct SendPingStep {
        let delay: Duration
        let outcome: Result<Void, PingSendingError>
    }

    private let clock: any Clock<Duration>
    private var prepareSessionSteps: [PrepareSessionStep]
    private var sendPingSteps: [SendPingStep]
    private var prepareSessionCalls = 0

    init(
        clock: any Clock<Duration>,
        prepareSessionSteps: [PrepareSessionStep],
        sendPingSteps: [SendPingStep]
    ) {
        self.clock = clock
        self.prepareSessionSteps = prepareSessionSteps
        self.sendPingSteps = sendPingSteps
    }

    func prepareSession() async throws -> String {
        prepareSessionCalls += 1
        guard let step = prepareSessionSteps.first else {
            try await clock.sleep(for: .seconds(404))
            return "unexpected-session"
        }
        prepareSessionSteps.removeFirst()
        try await clock.sleep(for: step.delay)
        return step.session
    }

    func activateSession(_ session: String) async throws {}

    func sendPing(in session: String) async throws(PingSendingError) {
        guard let step = sendPingSteps.first else {
            do {
                try await clock.sleep(for: .seconds(404))
            } catch is CancellationError {
                return
            } catch {
                return
            }
            return
        }
        sendPingSteps.removeFirst()
        do {
            try await clock.sleep(for: step.delay)
        } catch is CancellationError {
            return
        } catch {
            return
        }

        switch step.outcome {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    func prepareSessionCallCount() -> Int {
        prepareSessionCalls
    }
}

// MARK: - SwiftTesting Debug Support

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
