//
//  CoverageMeasurementSessionInitializer.swift
//  RMBT
//
//  Created by Jiri Urbasek on 24.02.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation

enum IPVersion {
    case IPv4
    case IPv6

    var description: String {
        switch self {
        case .IPv4: return "IPv4"
        case .IPv6: return "IPv6"
        }
    }
}

protocol CoverageAPIService {
    func getCoverageRequest(
        _ request: CoverageRequestRequest,
        loopUUID: String?,
        success: @escaping (_ response: SignalRequestResponse) -> (),
        error failure: @escaping ErrorCallback
    )
}

extension RMBTControlServer: CoverageAPIService {}

// MARK: - Core Session Initializer

/// Core initializer responsible for API communication and state management only.
class CoreSessionInitializer {
    struct SessionCredentials {
        struct UDPPingCredentails {
            let pingToken: String
            let pingHost: String
            let pingPort: String
            let ipVersion: IPVersion?
        }
        let testID: String
        let loopID: String?
        let udpPing: UDPPingCredentails
    }

    private let now: () -> Date
    private let coverageAPIService: any CoverageAPIService

    private(set) var lastTestUUID: String?
    private(set) var lastLoopUUID: String?
    private(set) var lastTestStartDate: Date?
    private(set) var maxCoverageSessionDuration: TimeInterval?
    private(set) var maxCoverageMeasurementDuration: TimeInterval?
    private(set) var lastIPVersion: IPVersion?
    private(set) var udpPingSessionCount: Int = 0

    var isInitialized: Bool {
        lastTestUUID != nil && lastTestStartDate != nil
    }

    init(now: @escaping () -> Date, coverageAPIService: some CoverageAPIService) {
        self.now = now
        self.coverageAPIService = coverageAPIService
    }

    func startNewSession(loopID: String? = nil) async throws -> SessionCredentials {
        Log.logger.info("Starting new session, loopID: \(loopID ?? "nil")")
        let response = try await request(loopID: loopID)

        // The HTTP bridge below is not cancellation-aware, so a caller that gave up on this attempt (e.g. the ping
        // loop's bounded recovery preparation) can still be waiting here when the server answers. Recording that
        // response would publish a session nobody is going to use.
        try Task.checkCancellation()

        lastTestUUID = response.testUUID
        lastLoopUUID = response.loopUUID
        lastTestStartDate = now()
        if let maxSessionSec = response.maxCoverageSessionSeconds {
            maxCoverageSessionDuration = TimeInterval(maxSessionSec)
        }
        if let maxMeasurementSec = response.maxCoverageMeasurementSeconds {
            maxCoverageMeasurementDuration = TimeInterval(maxMeasurementSec)
        }
        let ipVersion: IPVersion? = switch response.ipVersion {
        case 4: .IPv4
        case 6: .IPv6
        default: nil
        }

        lastIPVersion = ipVersion
        udpPingSessionCount += 1

        Log.logger.info("Session initialized: testUUID=\(response.testUUID), ipVersion=\(ipVersion?.description ?? "nil"), sessionCount=\(udpPingSessionCount)")

        return SessionCredentials(
            testID: response.testUUID,
            loopID: response.loopUUID,
            udpPing: .init(
                pingToken: response.pingToken,
                pingHost: response.pingHost,
                pingPort: response.pingPort,
                ipVersion: ipVersion
            )
        )
    }

    /// Cancellation-aware bridge over the callback API. The HTTP request itself cannot be cancelled, but the *task*
    /// must be: a caller that bounds this call (the ping loop's recovery preparation) has to be able to give up
    /// without waiting for the server. A callback arriving after cancellation is dropped.
    private func request(loopID: String?) async throws -> SignalRequestResponse {
        // Nothing to gain from firing a request the caller has already given up on.
        try Task.checkCancellation()

        let resumeOnce = OneShotContinuation<SignalRequestResponse>()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                resumeOnce.install(continuation)
                guard !Task.isCancelled else {
                    resumeOnce.resume(throwing: CancellationError())
                    return
                }
                coverageAPIService.getCoverageRequest(
                    CoverageRequestRequest(time: Int(now().timeIntervalSince1970 * 1000), measurementType: "dedicated"),
                    loopUUID: loopID
                ) { response in
                    resumeOnce.resume(returning: response)
                } error: { error in
                    Log.logger.error("API request failed: \(error.localizedDescription)")
                    resumeOnce.resume(throwing: error)
                }
            }
        } onCancel: {
            resumeOnce.resume(throwing: CancellationError())
        }
    }
}


/// Resumes a `CheckedContinuation` exactly once, whichever of several racing sources gets there first, and tolerates
/// being resumed before the continuation is installed (a cancellation handler can run before the operation body).
final class OneShotContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var pendingResult: Result<Value, any Error>?
    private var isFinished = false

    private enum InstallOutcome {
        case deliver(Result<Value, any Error>)
        case stored
        case alreadyInstalled
    }

    func install(_ continuation: CheckedContinuation<Value, any Error>) {
        let outcome: InstallOutcome = lock.withLock {
            guard self.continuation == nil else { return .alreadyInstalled }
            if let pendingResult {
                isFinished = true
                self.pendingResult = nil
                return .deliver(pendingResult)
            }
            guard !isFinished else { return .alreadyInstalled }
            self.continuation = continuation
            return .stored
        }

        switch outcome {
        case .deliver(let result):
            continuation.resume(with: result)
        case .stored:
            break
        case .alreadyInstalled:
            // Resuming nothing would strand this continuation, which hangs the caller forever. Installing twice is
            // always a programming error, so fail loudly instead.
            preconditionFailure("OneShotContinuation was installed more than once")
        }
    }

    func resume(returning value: Value) {
        resume(with: .success(value))
    }

    func resume(throwing error: any Error) {
        resume(with: .failure(error))
    }

    private func resume(with result: Result<Value, any Error>) {
        let continuation: CheckedContinuation<Value, any Error>? = lock.withLock {
            guard !isFinished else { return nil }
            guard let installed = self.continuation else {
                // Resumed before the continuation existed — hand the first result over at install time. Later
                // results are dropped, so whoever got here first wins even in this window.
                if pendingResult == nil { pendingResult = result }
                return nil
            }
            isFinished = true
            self.continuation = nil
            return installed
        }
        continuation?.resume(with: result)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

// MARK: - Persistence-Aware Decorator

/// Decorator that adds persistence management and resending functionality.
class PersistenceAwareSessionInitializer {
    private let wrapped: CoreSessionInitializer
    private let resendBeforeNewSession: @Sendable () async throws -> Void

    var lastTestUUID: String? { wrapped.lastTestUUID }
    var lastLoopUUID: String? { wrapped.lastLoopUUID }
    var lastTestStartDate: Date? { wrapped.lastTestStartDate }
    var maxCoverageSessionDuration: TimeInterval? { wrapped.maxCoverageSessionDuration }
    var maxCoverageMeasurementDuration: TimeInterval? { wrapped.maxCoverageMeasurementDuration }
    var lastIPVersion: IPVersion? { wrapped.lastIPVersion }
    var udpPingSessionCount: Int { wrapped.udpPingSessionCount }
    var isInitialized: Bool { wrapped.isInitialized }

    /// `resendBeforeNewSession` must capture the factory's full configuration; otherwise
    /// tests injecting a stub `CoverageAPIService` silently fall back to the production
    /// shared control server here.
    init(
        wrapped: CoreSessionInitializer,
        resendBeforeNewSession: @escaping @Sendable () async throws -> Void
    ) {
        self.wrapped = wrapped
        self.resendBeforeNewSession = resendBeforeNewSession
    }

    func startNewSession(loopID: String? = nil) async throws -> CoreSessionInitializer.SessionCredentials {
        // Before starting new session, try to resend failed-to-be-sent Signal Measurement Results, if any
        Log.logger.info("Attempting to resend persistent areas before starting new session")
        try? await resendBeforeNewSession()

        // `try?` above swallows cancellation along with everything else, so a caller that already gave up on this
        // attempt (the ping loop's bounded preparation) would otherwise still go on to issue `/coverageRequest`.
        try Task.checkCancellation()

        return try await wrapped.startNewSession(loopID: loopID)
    }
}

// MARK: - Online-Aware Decorator

/// Decorator that adds online status checking, retry logic, and event streaming.
class OnlineAwareSessionInitializer {
    private let wrapped: PersistenceAwareSessionInitializer
    private let onlineStatusService: OnlineStatusService?
    private let now: () -> Date
    private let retryDelay: Duration

    var lastTestUUID: String? { wrapped.lastTestUUID }
    var lastLoopUUID: String? { wrapped.lastLoopUUID }
    var lastTestStartDate: Date? { wrapped.lastTestStartDate }
    var maxCoverageSessionDuration: TimeInterval? { wrapped.maxCoverageSessionDuration }
    var maxCoverageMeasurementDuration: TimeInterval? { wrapped.maxCoverageMeasurementDuration }
    var lastIPVersion: IPVersion? { wrapped.lastIPVersion }
    var udpPingSessionCount: Int { wrapped.udpPingSessionCount }
    var isInitialized: Bool { wrapped.isInitialized }

    // Event stream for session lifecycle notifications
    private var eventsStream: AsyncStream<SessionInitializedUpdate>?
    private var eventsContinuation: AsyncStream<SessionInitializedUpdate>.Continuation?

    func sessionInitializedEvents() -> AsyncStream<SessionInitializedUpdate> {
        if let s = eventsStream { return s }
        var continuation: AsyncStream<SessionInitializedUpdate>.Continuation!
        let stream = AsyncStream<SessionInitializedUpdate> { c in continuation = c }
        eventsStream = stream
        eventsContinuation = continuation
        return stream
    }

    init(
        wrapped: PersistenceAwareSessionInitializer,
        onlineStatusService: OnlineStatusService?,
        now: @escaping () -> Date,
        retryDelay: Duration = .seconds(1)
    ) {
        self.wrapped = wrapped
        self.onlineStatusService = onlineStatusService
        self.now = now
        self.retryDelay = retryDelay
    }

    func startNewSession(loopID: String? = nil) async throws -> CoreSessionInitializer.SessionCredentials {
        do {
            let credentials = try await wrapped.startNewSession(loopID: loopID)
            try Task.checkCancellation()
            emitInitialized(credentials)
            return credentials
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard let service = onlineStatusService else { throw error }
            Log.logger.info("Session start failed, waiting for online status...")
            // Keep retrying on every reachability `true` until cancelled or success.
            // Off→on flips during a failed retry re-arm the loop instead of giving up.
            for await isOnline in service.online() {
                try Task.checkCancellation()
                guard isOnline else { continue }
                Log.logger.info("Online status detected, retrying session start after \(retryDelay)")
                try await Task.sleep(for: retryDelay)
                do {
                    let credentials = try await wrapped.startNewSession(loopID: loopID)
                    try Task.checkCancellation()
                    emitInitialized(credentials)
                    return credentials
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    Log.logger.info("Retry failed, waiting for next online signal: \(error.localizedDescription)")
                    continue
                }
            }
            throw error
        }
    }

    private func emitInitialized(_ credentials: CoreSessionInitializer.SessionCredentials) {
        Log.logger.info("Emitting session initialized event: sessionID=\(credentials.testID)")
        eventsContinuation?.yield(SessionInitializedUpdate(timestamp: now(), sessionID: credentials.testID))
    }
}

// MARK: - Legacy Type Alias

/// Legacy name for backwards compatibility - points to the fully decorated initializer
typealias CoverageMeasurementSessionInitializer = OnlineAwareSessionInitializer

import ObjectMapper

class CoverageRequestRequest: BasicRequest {
    var time: Int
    var measurementType: String
    var clientUUID: String?
    var loopUUID: String?

    init(time: Int, measurementType: String) {
        self.time = time
        self.measurementType = measurementType
        super.init()
    }

    required init?(map: Map) {
        fatalError("init(map:) has not been implemented")
    }

    override func mapping(map: Map) {
        super.mapping(map: map)

        clientUUID <- map["client_uuid"]
        time <- map["time"]
        measurementType <- map["measurement_type_flag"]
        loopUUID <- map["loop_uuid"]
    }
}

class SignalRequestResponse: BasicResponse {
    var testUUID: String = ""
    var loopUUID: String?
    var pingToken: String = ""
    var pingHost: String = ""
    var pingPort: String = ""
    var ipVersion: Int?
    var maxCoverageSessionSeconds: Int?
    var maxCoverageMeasurementSeconds: Int?

    override func mapping(map: Map) {
        super.mapping(map: map)

        testUUID <- map["test_uuid"]
        loopUUID <- map["loop_uuid"]
        pingToken <- map["ping_token"]
        pingHost <- map["ping_host"]
        pingPort <- map["ping_port"]
        ipVersion <- map["ip_version"]
        maxCoverageSessionSeconds <- map["max_coverage_session_seconds"]
        maxCoverageMeasurementSeconds <- map["max_coverage_measurement_seconds"]
    }
}
