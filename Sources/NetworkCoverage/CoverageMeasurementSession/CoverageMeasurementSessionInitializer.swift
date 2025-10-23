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

        lastTestUUID = response.testUUID
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
            loopID: loopID,
            udpPing: .init(
                pingToken: response.pingToken,
                pingHost: response.pingHost,
                pingPort: response.pingPort,
                ipVersion: ipVersion
            )
        )
    }

    private func request(loopID: String?) async throws -> SignalRequestResponse {
        try await withCheckedThrowingContinuation { continuation in
            coverageAPIService.getCoverageRequest(
                CoverageRequestRequest(time: Int(now().timeIntervalSince1970 * 1000), measurementType: "dedicated"),
                loopUUID: loopID
            ) { response in
                continuation.resume(returning: response)
            } error: { error in
                Log.logger.error("API request failed: \(error.localizedDescription)")
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Persistence-Aware Decorator

/// Decorator that adds persistence management and resending functionality.
class PersistenceAwareSessionInitializer {
    private let wrapped: CoreSessionInitializer
    private let database: UserDatabase

    var lastTestUUID: String? { wrapped.lastTestUUID }
    var lastTestStartDate: Date? { wrapped.lastTestStartDate }
    var maxCoverageSessionDuration: TimeInterval? { wrapped.maxCoverageSessionDuration }
    var maxCoverageMeasurementDuration: TimeInterval? { wrapped.maxCoverageMeasurementDuration }
    var lastIPVersion: IPVersion? { wrapped.lastIPVersion }
    var udpPingSessionCount: Int { wrapped.udpPingSessionCount }
    var isInitialized: Bool { wrapped.isInitialized }

    init(wrapped: CoreSessionInitializer, database: UserDatabase) {
        self.wrapped = wrapped
        self.database = database
    }

    func startNewSession(loopID: String? = nil) async throws -> CoreSessionInitializer.SessionCredentials {
        // Before starting new session, try to resend failed-to-be-sent coverage test results, if any
        Log.logger.info("Attempting to resend persistent areas before starting new session")
        try? await NetworkCoverageFactory(database: database).persistedFencesSender.resendPersistentAreas(isLaunched: false)

        return try await wrapped.startNewSession(loopID: loopID)
    }
}

// MARK: - Online-Aware Decorator

/// Decorator that adds online status checking, retry logic, and event streaming.
class OnlineAwareSessionInitializer {
    private let wrapped: PersistenceAwareSessionInitializer
    private let onlineStatusService: OnlineStatusService?
    private let now: () -> Date

    var lastTestUUID: String? { wrapped.lastTestUUID }
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

    init(wrapped: PersistenceAwareSessionInitializer, onlineStatusService: OnlineStatusService?, now: @escaping () -> Date) {
        self.wrapped = wrapped
        self.onlineStatusService = onlineStatusService
        self.now = now
    }

    func startNewSession(loopID: String? = nil) async throws -> CoreSessionInitializer.SessionCredentials {
        var credentials: CoreSessionInitializer.SessionCredentials?

        do {
            credentials = try await wrapped.startNewSession(loopID: loopID)
        } catch {
            // Offline-aware retry if an OnlineStatusService was provided.
            if let service = onlineStatusService {
                Log.logger.info("Session start failed, waiting for online status...")
                // Wait for a 'true' emission
                for await isOnline in service.online() {
                    if isOnline {
                        Log.logger.info("Online status detected, retrying session start")
                        credentials = try await wrapped.startNewSession(loopID: loopID)
                        break
                    }
                }
            } else {
                throw error
            }
        }

        guard let credentials else {
            throw NSError(domain: "CoverageInitializer", code: -1)
        }

        // Emit session initialized event for consumers (ViewModel)
        Log.logger.info("Emitting session initialized event: sessionID=\(credentials.testID)")
        eventsContinuation?.yield(SessionInitializedUpdate(timestamp: now(), sessionID: credentials.testID))

        return credentials
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
    var pingToken: String = ""
    var pingHost: String = ""
    var pingPort: String = ""
    var ipVersion: Int?
    var maxCoverageSessionSeconds: Int?
    var maxCoverageMeasurementSeconds: Int?

    override func mapping(map: Map) {
        super.mapping(map: map)

        testUUID <- map["test_uuid"]
        pingToken <- map["ping_token"]
        pingHost <- map["ping_host"]
        pingPort <- map["ping_port"]
        ipVersion <- map["ip_version"]
        maxCoverageSessionSeconds <- map["max_coverage_session_seconds"]
        maxCoverageMeasurementSeconds <- map["max_coverage_measurement_seconds"]
    }
}
