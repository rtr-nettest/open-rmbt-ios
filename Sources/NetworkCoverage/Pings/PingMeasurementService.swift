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

protocol PingSending<PingSession>: Sendable {
    associatedtype PingSession: Sendable

    /// Fetches the credentials of a new ping session. May take arbitrarily long and must leave the
    /// currently running transport untouched, so that an already active session can keep measuring
    /// while a replacement is being prepared.
    func prepareSession() async throws -> PingSession

    /// Brings the transport up for an already prepared session. Fast, but destroys the previous transport.
    func activateSession(_ session: PingSession) async throws

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

/// Rules for recovering a ping session whose send path stopped working.
struct RecoveryPolicy: Sendable {
    /// Number of consecutive failed ping outcomes after which a replacement session is prepared.
    let maxConsecutiveFailures: Int

    /// Delay enforced between the first and the second recovery. Doubled after every recovery, capped at `maxBackoff`.
    /// The first recovery of a run is not delayed.
    let initialBackoff: Duration

    let maxBackoff: Duration

    /// Upper bound for a recovery preparation. The very first preparation of a run is deliberately unbounded,
    /// because parking until the device gets online is the existing offline-start behaviour.
    let recoveryPrepareTimeout: Duration

    /// Upper bound for bringing the transport up. Always applied, including for the first session of a run: this is
    /// the only window in which nothing can send, so it is kept far shorter than the credentials fetch.
    let activationTimeout: Duration

    /// Minimum delay before retrying a preparation that failed while no usable session was left.
    let retryDelay: Duration

    init(
        maxConsecutiveFailures: Int,
        initialBackoff: Duration,
        maxBackoff: Duration,
        recoveryPrepareTimeout: Duration,
        activationTimeout: Duration,
        retryDelay: Duration
    ) {
        precondition(maxConsecutiveFailures > 0, "A threshold of 0 would owe a recovery on every tick")
        precondition(initialBackoff >= .zero && maxBackoff >= .zero, "Backoff delays cannot be negative")
        precondition(initialBackoff <= maxBackoff, "The backoff ladder must not start above its own cap")
        precondition(recoveryPrepareTimeout > .zero, "A non-positive timeout would abandon every attempt at once")
        precondition(activationTimeout > .zero, "A non-positive timeout would abandon every activation at once")
        precondition(retryDelay >= .zero, "A negative retry delay cannot gate anything")
        self.maxConsecutiveFailures = maxConsecutiveFailures
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff
        self.recoveryPrepareTimeout = recoveryPrepareTimeout
        self.activationTimeout = activationTimeout
        self.retryDelay = retryDelay
    }

    static let `default` = RecoveryPolicy(
        maxConsecutiveFailures: 30,
        initialBackoff: .seconds(10),
        maxBackoff: .seconds(120),
        recoveryPrepareTimeout: .seconds(15),
        activationTimeout: .seconds(5),
        retryDelay: .seconds(1)
    )
}

struct PingMeasurementService {
    static func pings2<T>(
        clock: some Clock<Duration>,
        pingSender: some PingSending<T>,
        now: @escaping () -> Date = Date.init,
        frequency: Duration,
        sessionMaxDuration: @escaping () -> TimeInterval? = { nil },
        networkTypeProvider: (any CurrentNetworkTypeProvider)? = nil,
        recovery: RecoveryPolicy = .default
    ) -> some PingsAsyncSequence {
        let state = PingSessionStateController<T>(policy: recovery)

        return AsyncStream { continuation in
            let start = clock.now
            let startDate = now()

            let task = Task {
                await withDiscardingTaskGroup { group in
                    while !Task.isCancelled {
                        let tick = clock.now
                        let currentDate = startDate.advanced(by: start.duration(to: tick).timeInterval)
                        let nextInstant = tick.advanced(by: frequency)

                        // Decided on the ordered tick, so that pausing, failure thresholds and the recovery
                        // gate never observe out-of-order timestamps of concurrently completing child tasks.
                        let action = state.actionForTick(
                            at: currentDate,
                            sessionMaxDuration: sessionMaxDuration(),
                            networkType: networkTypeProvider?.currentNetworkType()
                        )

                        // A rolling picture of what the ping engine is doing. Transition logs alone leave a long
                        // field run unreadable: they say what changed, never what the steady state looks like.
                        if let summary = state.periodicSummary(at: currentDate) {
                            Log.logger.info("UDPPing: \(summary)")
                        }

                        group.addTask {
                            guard !Task.isCancelled else { return }

                            switch action {
                            case .prepare(let generation, let isPreparationBounded):
                                await prepareAndActivateSession(
                                    sender: pingSender,
                                    state: state,
                                    clock: clock,
                                    generation: generation,
                                    at: currentDate,
                                    preparationTimeout: isPreparationBounded
                                        ? recovery.recoveryPrepareTimeout
                                        : nil,
                                    activationTimeout: recovery.activationTimeout
                                )

                            case .send(let session, let generation):
                                switch await measureSend(sender: pingSender, session: session, clock: clock) {
                                case .needsReinitialization:
                                    state.requestReinitialization(for: generation)

                                case .failed(let error):
                                    if state.recordFailure(generation: generation, kind: error) {
                                        continuation.yield(PingResult(result: .error, timestamp: currentDate))
                                    }

                                case .succeeded(let elapsed):
                                    if state.recordSuccess(generation: generation) {
                                        continuation.yield(
                                            PingResult(result: .interval(elapsed), timestamp: currentDate)
                                        )
                                    }
                                }

                            case .skip:
                                break
                            }
                        }

                        do {
                            try await clock.sleep(until: nextInstant, tolerance: .milliseconds(1))
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

    // MARK: - Action execution

    private struct PreparationTimedOutError: Error {}

    private enum SendOutcome {
        case succeeded(Duration)
        case failed(PingSendingError)
        case needsReinitialization
    }

    /// Runs the two phases of bringing a session up, reporting each of them separately: the state controller
    /// keeps the previous session usable until the credentials of the replacement are in hand.
    private static func prepareAndActivateSession<T>(
        sender: some PingSending<T>,
        state: PingSessionStateController<T>,
        clock: some Clock<Duration>,
        generation: Int,
        at date: Date,
        preparationTimeout: Duration?,
        activationTimeout: Duration
    ) async {
        do {
            let session = try await withTimeout(preparationTimeout, clock: clock) {
                try await sender.prepareSession()
            }
            state.didPrepareSession(generation: generation)

            // Activation is *always* bounded, including for the first session of a run: `NWUDPConnection.start`
            // never resumes while the path stays `.waiting`, and a hang here leaves nothing able to send and
            // nothing to retry it. Only the credentials fetch may park, because waiting for the device to come
            // online is the offline-start behaviour.
            try await withTimeout(activationTimeout, clock: clock) {
                try await sender.activateSession(session)
            }
            state.didActivateSession(session, at: date, generation: generation)
            Log.logger.info("UDPPing: Ping session activated")
        } catch {
            // Only a genuine shutdown may go unreported: leaving the controller in `.preparing` means every later
            // tick skips, so any other error — including a spurious `CancellationError` — must be reported.
            guard !Task.isCancelled else { return }
            Log.logger.warning("UDPPing: Ping session preparation failed: \(error)")
            state.didFailPreparation(generation: generation, launchedAt: date)
        }
    }

    private static func measureSend<T>(
        sender: some PingSending<T>,
        session: T,
        clock: some Clock<Duration>
    ) async -> SendOutcome {
        var capturedError: PingSendingError?
        let elapsed = await clock.measure {
            do throws(PingSendingError) {
                try await sender.sendPing(in: session)
            } catch {
                capturedError = error
            }
        }

        guard let capturedError else { return .succeeded(elapsed) }

        if capturedError == .needsReinitialization {
            Log.logger.info("UDPPing: Server responded with reinitialisation request (RE01), will start new session")
            return .needsReinitialization
        }
        return .failed(capturedError)
    }

    private static func withTimeout<R>(
        _ timeout: Duration?,
        clock: some Clock<Duration>,
        operation: @escaping () async throws -> R
    ) async throws -> R {
        guard let timeout else {
            return try await operation()
        }

        return try await withThrowingTaskGroup(of: Optional<R>.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await clock.sleep(for: timeout)
                return nil
            }

            while let result = try await group.next() {
                group.cancelAll()
                guard let result else { throw PreparationTimedOutError() }
                return result
            }
            throw CancellationError()
        }
    }
}

// MARK: - Session state

/// Deadlines and tick timestamps are both floating-point seconds derived from independent additions, so
/// they are compared with a tolerance far below the ping cadence.
private let deadlineComparisonTolerance: TimeInterval = 0.001

/// How often the ping loop emits its rolling field-log summary.
private let pingSummaryInterval: TimeInterval = 10

/// Why a replacement session was asked for. Kept so that a failed attempt can re-latch its own cause.
private struct RecoveryCauses: OptionSet {
    let rawValue: Int

    static let networkTypeChange = RecoveryCauses(rawValue: 1 << 0)
    static let failureRun = RecoveryCauses(rawValue: 1 << 1)
}

/// Serialised with a lock rather than an actor on purpose: every transition here is a short, synchronous
/// state update, and keeping it non-suspending is what lets the cadence loop decide a tick's action
/// without a suspension point between reading the tick's timestamp and acting on it.
private final class PingSessionStateController<Session: Sendable>: @unchecked Sendable {
    enum TickAction {
        case prepare(generation: Int, isPreparationBounded: Bool)
        case send(session: Session, generation: Int)
        case skip
    }

    private struct SessionInfo {
        let value: Session
        let generation: Int
        /// The tick this session's preparation was launched from, not the tick it became usable. The server counts
        /// `max_coverage_measurement_seconds` from `/coverageRequest`, so the client's window has to start there too.
        /// After a long park that leaves the first session with little budget left — deliberate, and unchanged
        /// from the behaviour before the prepare/activate split.
        let startedAt: Date
    }

    private enum State {
        /// Nothing usable, nothing in flight.
        case idle
        /// A replacement is being fetched. While `old` is non-nil it keeps measuring (make before break).
        case preparing(generation: Int, old: SessionInfo?, causes: RecoveryCauses)
        case active(SessionInfo)
    }

    private let policy: RecoveryPolicy

    private var state: State = .idle
    private var nextGeneration = 0

    private var isPaused = false
    private var pendingNetworkTypeRecovery = false
    private var pendingFailureRecovery = false
    private var consecutiveFailures = 0
    private var hardCutRequested = false

    private var backoff: Duration
    private var nextRecoveryAllowedAt: Date?
    private var nextPrepareAllowedAt: Date?
    private var isRecoveryThrottleClampPending = false

    // Counters behind the periodic field-log summary. The interval counters reset on every emitted summary so each
    // line describes its own window; the run totals never reset, so a summary line lost to a truncated log does not
    // take its counts with it.
    private var repliedCount = 0
    private var timedOutCount = 0
    private var networkIssueCount = 0
    private var totalRepliedCount = 0
    private var totalTimedOutCount = 0
    private var totalNetworkIssueCount = 0
    private var lastSummaryAt: Date?
    /// Whether the session currently in use has ever had a reply. Turning false→true is the only direct evidence
    /// that bringing up a replacement actually fixed anything.
    private var hasCurrentSessionReplied = false
    /// Only the very first credentials fetch of a run may park indefinitely (offline start). Set as soon as that
    /// fetch is launched, so a retry after it fails is bounded like every other one.
    private var hasLaunchedFirstPreparation = false

    private let lock = NSLock()

    init(policy: RecoveryPolicy) {
        self.policy = policy
        self.backoff = policy.initialBackoff
    }

    func actionForTick(
        at currentDate: Date,
        sessionMaxDuration: TimeInterval?,
        networkType: NetworkTypeUpdate.NetworkConnectionType?
    ) -> TickAction {
        lock.lock()
        defer { lock.unlock() }

        // Wi-Fi results are meaningless for coverage, so pings pause. An unsatisfied path (`nil`) must keep
        // pinging: its failures are what renders a fence as "no coverage".
        if networkType == .wifi {
            if !isPaused {
                Log.logger.info("UDPPing: Wi-Fi path active, pausing ping measurement")
                isPaused = true
            }
            pendingNetworkTypeRecovery = true
            pendingFailureRecovery = false
            consecutiveFailures = 0
            return .skip
        }

        if isPaused {
            isPaused = false
            Log.logger.info("UDPPing: Wi-Fi path left, resuming ping measurement")
        }

        applyHardCutIfNeeded(at: currentDate, sessionMaxDuration: sessionMaxDuration)

        // A working path restarts the ladder, but it must not unlock an immediate recovery: otherwise
        // flapping Wi-Fi would mint a new session on every single flap. All deadline arithmetic stays on
        // the ordered tick so it never runs against a stale timestamp.
        if isRecoveryThrottleClampPending {
            isRecoveryThrottleClampPending = false
            if let deadline = nextRecoveryAllowedAt {
                nextRecoveryAllowedAt = min(deadline, currentDate.addingTimeInterval(policy.initialBackoff.timeInterval))
            }
        }

        if consecutiveFailures >= policy.maxConsecutiveFailures {
            Log.logger.info("UDPPing: \(consecutiveFailures) consecutive ping failures, session recovery owed")
            pendingFailureRecovery = true
            consecutiveFailures = 0
        }

        if
            pendingNetworkTypeRecovery || pendingFailureRecovery,
            case .active(let session) = state,
            hasReached(nextRecoveryAllowedAt, at: currentDate)
        {
            nextRecoveryAllowedAt = currentDate.addingTimeInterval(backoff.timeInterval)
            backoff = min(backoff * 2, policy.maxBackoff)
            return startPreparation(replacing: session, isRecovery: true)
        }

        switch state {
        case .idle:
            if !hasReached(nextPrepareAllowedAt, at: currentDate) {
                return .skip
            }
            nextPrepareAllowedAt = nil
            return startPreparation(replacing: nil, isRecovery: false)

        case .preparing(_, let old, _):
            guard let old else { return .skip }
            return .send(session: old.value, generation: old.generation)

        case .active(let session):
            return .send(session: session.value, generation: session.generation)
        }
    }

    /// Returns a one-line field-log summary once per `summaryInterval`, or `nil` in between. Counters are collected
    /// under the lock and formatted by the caller so no logging happens while it is held.
    func periodicSummary(at currentDate: Date) -> String? {
        lock.lock()

        guard let since = lastSummaryAt else {
            lastSummaryAt = currentDate
            lock.unlock()
            return nil
        }
        guard currentDate.timeIntervalSince(since) >= pingSummaryInterval else {
            lock.unlock()
            return nil
        }
        lastSummaryAt = currentDate

        let interval = currentDate.timeIntervalSince(since)
        let elapsed = Int(interval.rounded())
        let replied = repliedCount
        let timedOut = timedOutCount
        let networkIssues = networkIssueCount
        repliedCount = 0
        timedOutCount = 0
        networkIssueCount = 0
        let totals = (replied: totalRepliedCount, timedOut: totalTimedOutCount, networkIssues: totalNetworkIssueCount)

        // The cadence loop only ticks while the app is executing, so a long interval means it was stalled — most
        // likely suspended. Saying so explicitly keeps that from reading like a truncated log.
        let wasStalled = interval >= pingSummaryInterval * 2

        let sessionDescription: String
        switch state {
        case .idle:
            sessionDescription = "no session"
        case .preparing(let generation, let old, _):
            sessionDescription = old == nil
                ? "activating generation \(generation)"
                : "preparing generation \(generation), still sending on the previous one"
        case .active(let session):
            sessionDescription = "generation \(session.generation)"
        }

        var owed: [String] = []
        if pendingNetworkTypeRecovery { owed.append("network-type") }
        if pendingFailureRecovery { owed.append("failure-run") }
        let owedDescription = owed.isEmpty ? "none" : owed.joined(separator: "+")

        let paused = isPaused
        let failures = consecutiveFailures
        lock.unlock()

        var fields = [
            "\(elapsed)s: \(replied) replied, \(timedOut) timed out, \(networkIssues) network error(s)",
            "run total: \(totals.replied) replied, \(totals.timedOut) timed out, \(totals.networkIssues) network error(s)",
            sessionDescription,
            "paused: \(paused)",
            "consecutive failures: \(failures)",
            "recovery owed: \(owedDescription)"
        ]
        if wasStalled {
            fields.insert("measurement loop was stalled for \(elapsed)s (app suspended?)", at: 0)
        }
        return fields.joined(separator: "; ")
    }

    /// `true` when the outcome was accepted, meaning it belongs to the session currently in use and the
    /// measurement is not paused. Rejected outcomes are neither counted nor reported.
    func recordFailure(generation: Int, kind: PingSendingError) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard accepts(generation) else { return false }
        consecutiveFailures += 1
        switch kind {
        case .timedOut:
            timedOutCount += 1
            totalTimedOutCount += 1
        case .networkIssue:
            networkIssueCount += 1
            totalNetworkIssueCount += 1
        case .needsReinitialization:
            break
        }
        return true
    }

    func recordSuccess(generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard accepts(generation) else { return false }
        consecutiveFailures = 0
        pendingFailureRecovery = false
        backoff = policy.initialBackoff
        isRecoveryThrottleClampPending = true
        repliedCount += 1
        totalRepliedCount += 1

        if !hasCurrentSessionReplied {
            hasCurrentSessionReplied = true
            Log.logger.info("UDPPing: First reply in ping session generation \(generation)")
        }

        // A working path settles the failure cause for good, including for an attempt already in flight: otherwise a
        // preparation that later fails would resurrect the cause from its snapshot and recover a path that recovered
        // on its own. An owed network-type refresh is deliberately left in place.
        if case .preparing(let preparingGeneration, let old, var causes) = state, causes.contains(.failureRun) {
            causes.remove(.failureRun)
            state = .preparing(generation: preparingGeneration, old: old, causes: causes)
        }
        return true
    }

    func requestReinitialization(for generation: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard accepts(generation) else { return }
        hardCutRequested = true
    }

    /// Credentials are in hand — this is the commit point. The previous session is dropped here, because
    /// its `test_uuid` has already been superseded by the announcement the fetch made.
    func didPrepareSession(generation: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard case .preparing(let currentGeneration, _, let causes) = state, currentGeneration == generation else {
            return
        }
        state = .preparing(generation: generation, old: nil, causes: causes)
    }

    func didActivateSession(_ session: Session, at currentDate: Date, generation: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard case .preparing(let currentGeneration, _, _) = state, currentGeneration == generation else { return }
        state = .active(.init(value: session, generation: generation, startedAt: currentDate))
        hasCurrentSessionReplied = false
        consecutiveFailures = 0
        hardCutRequested = false
        // Failures observed on the session being replaced are settled by this activation: the fresh
        // credentials and transport are exactly what the owed failure recovery was asking for. An owed
        // network-type refresh is deliberately kept — this candidate may have been fetched on the old path.
        pendingFailureRecovery = false
    }

    /// `launchedAt` is the tick the failed attempt started from. The retry deadline is anchored to it rather than
    /// to whichever tick happens to observe the failure: an attempt that failed fast is throttled, while one that
    /// already spent longer than `retryDelay` failing retries at once.
    func didFailPreparation(generation: Int, launchedAt: Date) {
        lock.lock()
        defer { lock.unlock() }

        guard case .preparing(let currentGeneration, let old, let causes) = state, currentGeneration == generation
        else { return }

        // Re-latch whatever asked for this attempt, so the retry actually happens at the next gate slot.
        if causes.contains(.networkTypeChange) { pendingNetworkTypeRecovery = true }
        if causes.contains(.failureRun) { pendingFailureRecovery = true }

        if let old {
            // Nothing was committed and the transport was never touched — the old session is still good.
            Log.logger.info("UDPPing: Keeping the previous ping session after a failed preparation")
            state = .active(old)
        } else {
            Log.logger.info("UDPPing: No usable ping session left, retrying after \(policy.retryDelay)")
            state = .idle
            nextPrepareAllowedAt = launchedAt.addingTimeInterval(policy.retryDelay.timeInterval)
        }
    }

    // MARK: - Private helpers

    private var sessionInUse: SessionInfo? {
        switch state {
        case .idle: nil
        case .preparing(_, let old, _): old
        case .active(let session): session
        }
    }

    private func accepts(_ generation: Int) -> Bool {
        !isPaused && sessionInUse?.generation == generation
    }

    /// Deadlines and tick timestamps are both floating-point seconds derived from independent additions, so
    /// they are compared with a tolerance far below the ping cadence. Without it a deadline that lands
    /// exactly on a tick can be missed and slip by a whole cadence period.
    private func hasReached(_ deadline: Date?, at currentDate: Date) -> Bool {
        guard let deadline else { return true }
        return currentDate.timeIntervalSince(deadline) >= -deadlineComparisonTolerance
    }

    private func startPreparation(replacing old: SessionInfo?, isRecovery: Bool) -> TickAction {
        // Only the genuine first credentials fetch of a run may park indefinitely — waiting for the device to come
        // online is the offline-start feature. Every later one is bounded, otherwise a parked mid-run
        // `/coverageRequest` silences the measurement with nothing left to retry it.
        let isPreparationBounded = hasLaunchedFirstPreparation
        hasLaunchedFirstPreparation = true
        var causes: RecoveryCauses = []
        if pendingNetworkTypeRecovery { causes.insert(.networkTypeChange) }
        if pendingFailureRecovery { causes.insert(.failureRun) }

        // Any preparation fetches fresh credentials, so every owed recovery is satisfied by it.
        pendingNetworkTypeRecovery = false
        pendingFailureRecovery = false
        consecutiveFailures = 0

        nextGeneration += 1
        let generation = nextGeneration
        state = .preparing(generation: generation, old: old, causes: causes)

        Log.logger.info(
            "UDPPing: Preparing ping session (generation \(generation), recovery: \(isRecovery), keeps previous session: \(old != nil), bounded: \(isPreparationBounded))"
        )
        return .prepare(generation: generation, isPreparationBounded: isPreparationBounded)
    }

    /// `RE01` and `max_coverage_measurement_seconds` are hard cuts: the session in use must stop being used
    /// immediately. They are evaluated before the soft recovery gate so that a rejected session is never
    /// kept alive as the fallback of a recovery attempt.
    private func applyHardCutIfNeeded(at currentDate: Date, sessionMaxDuration: TimeInterval?) {
        guard let sessionInUse else {
            hardCutRequested = false
            return
        }

        let reason: String
        if hardCutRequested {
            hardCutRequested = false
            reason = "server requested reinitialisation (RE01)"
        } else if
            let sessionMaxDuration,
            hasReached(sessionInUse.startedAt.addingTimeInterval(sessionMaxDuration), at: currentDate)
        {
            reason = "session timeout reached (\(sessionMaxDuration)s elapsed since \(sessionInUse.startedAt))"
        } else {
            return
        }

        Log.logger.info("UDPPing: Dropping current ping session: \(reason)")

        switch state {
        case .idle:
            break
        case .active:
            state = .idle
        case .preparing(let generation, _, let causes):
            // Keep the very same candidate — a hard cut must never start a second request.
            state = .preparing(generation: generation, old: nil, causes: causes)
        }
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

    var timeInterval: TimeInterval {
        TimeInterval(milliseconds) / 1000
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
