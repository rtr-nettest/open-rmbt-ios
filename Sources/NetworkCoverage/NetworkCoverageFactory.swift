//
//  NetworkCoverageFactory.swift
//  RMBT
//
//  Created by Jiri Urbasek on 30.05.2025.
//  Copyright 2025 appscape gmbh. All rights reserved.

import Foundation
import SwiftData
import AsyncAlgorithms

final class UserDatabase {
    static let shared = UserDatabase()

    let container: ModelContainer

    init(useInMemoryStore: Bool = false) {
        let configuration = ModelConfiguration(
            for: PersistentFence.self, PersistentCoverageSession.self,
            isStoredInMemoryOnly: useInMemoryStore
        )
        container = try! ModelContainer(
            for: PersistentFence.self, PersistentCoverageSession.self,
            configurations: configuration
        )
    }

    lazy var modelContext: ModelContext = .init(container)
}

struct NetworkCoverageFactory {
    // MARK: - Constants
    static let acceptableSubmitResultsRequestStatusCodes = 200..<300
    static let persistenceMaxAgeInterval: TimeInterval = 7 * 24 * 60 * 60
    static let locationInaccuracyWarningInitialDelay: TimeInterval = 3
    static let insufficientAccuracyAutoStopInterval: TimeInterval = 30 * 60

    private let database: UserDatabase
    private let maxResendAge: TimeInterval
    private let dateNow: () -> Date

    init(
        database: UserDatabase = .shared,
        maxResendAge: TimeInterval = Self.persistenceMaxAgeInterval,
        dateNow: @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.maxResendAge = maxResendAge
        self.dateNow = dateNow
    }

    var persistedFencesSender: PersistedFencesResender {
        let persistenceActor = PersistenceServiceActor(modelContainer: database.container)
        return PersistedFencesResender(
            persistence: persistenceActor,
            sendResultsService: { testUUID, startDate in
                self.makeSendResultsService(testUUID: testUUID, startDate: startDate)
            },
            maxResendAge: maxResendAge,
            dateNow: dateNow
        )
    }

    func makeResender(
        sendResultsServiceMaker: @escaping (String, Date?) -> some SendCoverageResultsService
    ) -> PersistedFencesResender {
        let persistence = PersistenceServiceActor(modelContainer: database.container)
        return PersistedFencesResender(
            persistence: persistence,
            sendResultsService: { uuid, start in sendResultsServiceMaker(uuid, start) },
            maxResendAge: maxResendAge,
            dateNow: dateNow
        )
    }

    func services(
        testUUID: @escaping @autoclosure () -> String?,
        startDate: @escaping @autoclosure () -> Date?,
        dateNow: @escaping () -> Date,
        sendResultsServiceMaker: @escaping (String, Date?) -> some SendCoverageResultsService
    ) -> (some FencePersistenceService, some SendCoverageResultsService) {
        let persistenceActor = PersistenceServiceActor(modelContainer: database.container)
        let resultSender = PersistenceManagingCoverageResultsService(
            modelContext: database.modelContext,
            testUUID: testUUID(),
            sendResultsService: { testUUID in
                sendResultsServiceMaker(testUUID, startDate())
            },
            resender: makeResender(sendResultsServiceMaker: sendResultsServiceMaker)
        )

        return (persistenceActor, resultSender)
    }

    @MainActor func makeReadOnlyCoverageViewModel(fences: [Fence] = []) -> NetworkCoverageViewModel {
#if targetEnvironment(simulator)
        // Simulator: use the mocked radio technology service to get meaningful values from CoreTelephony APIs.
        let radioTechnologyService = SimulatorRadioTechnologyService()
#else
        let radioTechnologyService = CTTelephonyRadioTechnologyService()
#endif
        return NetworkCoverageViewModel(
            fences: fences,
            refreshInterval: 1.0,
            minimumLocationAccuracy: 10.0,
            locationInaccuracyWarningInitialDelay: Self.locationInaccuracyWarningInitialDelay,
            insufficientAccuracyAutoStopInterval: Self.insufficientAccuracyAutoStopInterval,
            updates: { EmptyAsyncSequence().asOpaque() },
            currentRadioTechnology: radioTechnologyService,
            sendResultsService: MockSendCoverageResultsService(),
            persistenceService: MockFencePersistenceService(),
            locale: .current,
            clock: ContinuousClock(),
            maxTestDuration: { 1 }
        )
    }

    func makeSessionInitializer(onlineStatusService: OnlineStatusService? = nil) -> OnlineAwareSessionInitializer {
        let core = CoreSessionInitializer(
            now: dateNow,
            coverageAPIService: RMBTControlServer.shared
        )
        let withPersistence = PersistenceAwareSessionInitializer(
            wrapped: core,
            database: database
        )
        let withOnline = OnlineAwareSessionInitializer(
            wrapped: withPersistence,
            onlineStatusService: onlineStatusService,
            now: dateNow
        )
        return withOnline
    }

    @MainActor func makeCoverageViewModel(fences: [Fence] = []) -> NetworkCoverageViewModel {
        let sessionInitializer = makeSessionInitializer()
        let (persistenceService, resultSender) = services(
            testUUID: sessionInitializer.lastTestUUID,
            startDate: sessionInitializer.lastTestStartDate,
            dateNow: dateNow,
            sendResultsServiceMaker: { testUUID, startDate in
                makeSendResultsService(testUUID: testUUID, startDate: startDate)
            }
        )
        let clock = ContinuousClock()

#if targetEnvironment(simulator)
        let networkConnectionUpdatesService = SimulatorNetworkConnectionTypeUpdatesService(now: dateNow)
        // Simulator: inject the mocked radio technology to complement simulated connection types.
        let radioTechnologyService = SimulatorRadioTechnologyService()
#else
        let networkConnectionUpdatesService = ReachabilityNetworkConnectionTypeUpdatesService(now: dateNow)
        let radioTechnologyService = CTTelephonyRadioTechnologyService()
#endif

        let pingSeq = { PingMeasurementService.pings2(
            clock: clock,
            pingSender: UDPPingSession(
                sessionInitiator: sessionInitializer,
                udpConnection: UDPConnection(),
                timeoutIntervalMs: 1000,
                now: RMBTHelpers.RMBTCurrentNanos
            ),
            frequency: .milliseconds(100),
            sessionMaxDuration: { sessionInitializer.maxCoverageMeasurementDuration }
        ) }

        // Allow location updates regardless of initialization to support offline start
        let locationService = RealLocationUpdatesService(now: dateNow, canReportLocations: { true })


        return NetworkCoverageViewModel(
            fences: fences,
            refreshInterval: 1,
            minimumLocationAccuracy: 5,
            locationInaccuracyWarningInitialDelay: Self.locationInaccuracyWarningInitialDelay,
            insufficientAccuracyAutoStopInterval: Self.insufficientAccuracyAutoStopInterval,
            updates: {
                let merged = merge(
                    pingSeq().map { NetworkCoverageViewModel.Update.ping($0) },
                    locationService.locations().map { NetworkCoverageViewModel.Update.location($0) }
                )
                let withNetwork = merge(
                    merged,
                    networkConnectionUpdatesService
                        .networkConnectionTypes()
                        .map { NetworkCoverageViewModel.Update.networkType($0) }
                )
                let sessionEvents = sessionInitializer
                    .sessionInitializedEvents()
                    .map { NetworkCoverageViewModel.Update.sessionInitialized($0) }

                let all = merge(withNetwork, sessionEvents).map { (u: NetworkCoverageViewModel.Update) in u }
                return _AsyncSequenceWrapper(base: all)
            },
            currentRadioTechnology: radioTechnologyService,
            sendResultsService: resultSender,
            persistenceService: persistenceService,
            locale: .autoupdatingCurrent,
            clock: clock,
            maxTestDuration: { sessionInitializer.maxCoverageSessionDuration ?? 4*60*60 /* 4 hours */ },
            ipVersionProvider: { sessionInitializer.lastIPVersion },
            connectionsCountProvider: { max(1, sessionInitializer.udpPingSessionCount) }
        )
    }

    private func makeSendResultsService(testUUID: String, startDate: Date?) -> some SendCoverageResultsService {
        ControlServerCoverageResultsService(
            controlServer: RMBTControlServer.shared,
            testUUID: testUUID,
            startDate: startDate
        )
    }
}

// MARK: - Mock Services

private struct MockSendCoverageResultsService: SendCoverageResultsService {
    func send(fences: [Fence]) async throws {}
}

private actor MockFencePersistenceService: FencePersistenceService {
    func save(_ fence: Fence) throws {}
    func sessionStarted(at date: Date) throws {}
    func sessionFinalized(at date: Date) throws {}
    func beginSession(startedAt: Date, loopUUID: String?) throws {}
    func assignTestUUIDAndAnchor(_ uuid: String, anchorNow: Date) throws {}
    func finalizeCurrentSession(at date: Date) throws {}
    func deleteFinalizedNilUUIDSessions() throws {}
}

private struct EmptyAsyncSequence: AsyncSequence {
    typealias Element = NetworkCoverageViewModel.Update
    
    struct AsyncIterator: AsyncIteratorProtocol {
        mutating func next() async throws -> NetworkCoverageViewModel.Update? { nil }
    }
    
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
}
