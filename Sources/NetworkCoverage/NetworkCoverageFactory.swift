//
//  NetworkCoverageFactory.swift
//  RMBT
//
//  Created by Jiri Urbasek on 30.05.2025.
//  Copyright 2025 appscape gmbh. All rights reserved.

import Foundation
import SwiftData

final class UserDatabase {
    static let shared = UserDatabase()

    let container: ModelContainer

    init(useInMemoryStore: Bool = false) {
        let configuration = ModelConfiguration(
            for: PersistentFence.self,
            isStoredInMemoryOnly: useInMemoryStore
        )
        container = try! ModelContainer(
            for: PersistentFence.self,
            configurations: configuration
        )
    }

    lazy var modelContext: ModelContext = .init(container)
}

struct NetworkCoverageFactory {
    static let acceptableSubmitResultsRequestStatusCodes = 200..<300
    static let persistenceMaxAgeInterval: TimeInterval = 7 * 24 * 60 * 60
    static let locationInaccuracyWarningInitialDelay: TimeInterval = 3
    static let insufficientAccuracyAutoStopInterval: TimeInterval = 30 * 60

    private let database: UserDatabase
    private let maxResendAge: TimeInterval
    private let dateNow: () -> Date = Date.init

    init(database: UserDatabase = .shared, maxResendAge: TimeInterval = Self.persistenceMaxAgeInterval) {
        self.database = database
        self.maxResendAge = maxResendAge
    }

    var persistedFencesSender: PersistedFencesResender {
        persistedFencesResender(sendResultsServiceMaker: { testUUID, startDate in
            makeSendResultsService(testUUID: testUUID, startDate: startDate)
        })
    }

    func services(
        testUUID: @escaping @autoclosure () -> String?,
        startDate: @escaping @autoclosure () -> Date?,
        dateNow: @escaping () -> Date,
        sendResultsServiceMaker: @escaping (String, Date?) -> some SendCoverageResultsService
    ) -> (some FencePersistenceService, some SendCoverageResultsService) {
        let resultSender = PersistenceManagingCoverageResultsService(
            modelContext: database.modelContext,
            testUUID: testUUID(),
            sendResultsService: { testUUID in
                sendResultsServiceMaker(testUUID, startDate())
            },
            resender: persistedFencesResender(sendResultsServiceMaker: sendResultsServiceMaker)
        )
        let persistenceService = SwiftDataFencePersistenceService(
            modelContext: database.modelContext,
            testUUID: testUUID()
        )

        return (persistenceService, resultSender)
    }

    @MainActor func makeReadOnlyCoverageViewModel(fences: [Fence] = []) -> NetworkCoverageViewModel {
        NetworkCoverageViewModel(
            fences: fences,
            refreshInterval: 1.0,
            minimumLocationAccuracy: 10.0,
            locationInaccuracyWarningInitialDelay: Self.locationInaccuracyWarningInitialDelay,
            insufficientAccuracyAutoStopInterval: Self.insufficientAccuracyAutoStopInterval,
            updates: { EmptyAsyncSequence().asOpaque() },
            currentRadioTechnology: CTTelephonyRadioTechnologyService(),
            sendResultsService: MockSendCoverageResultsService(),
            persistenceService: MockFencePersistenceService(),
            locale: .current,
            clock: ContinuousClock()
        )
    }

    @MainActor func makeCoverageViewModel(fences: [Fence] = []) -> NetworkCoverageViewModel {
        let sessionInitializer = CoverageMeasurementSessionInitializer(
            now: dateNow,
            controlServer: RMBTControlServer.shared
        )
        let (persistenceService, resultSender) = services(
            testUUID: sessionInitializer.lastTestUUID,
            startDate: sessionInitializer.lastTestStartDate,
            dateNow: dateNow,
            sendResultsServiceMaker: { testUUID, startDate in
                makeSendResultsService(testUUID: testUUID, startDate: startDate)
            }
        )
        let clock = ContinuousClock()

        return NetworkCoverageViewModel(
            fences: fences,
            refreshInterval: 1,
            minimumLocationAccuracy: 2,
            locationInaccuracyWarningInitialDelay: Self.locationInaccuracyWarningInitialDelay,
            insufficientAccuracyAutoStopInterval: Self.insufficientAccuracyAutoStopInterval,
            pingMeasurementService: { PingMeasurementService.pings2(
                clock: clock,
                pingSender: UDPPingSession(
                    sessionInitiator: sessionInitializer,
                    udpConnection: UDPConnection(),
                    timeoutIntervalMs: 1000,
                    now: RMBTHelpers.RMBTCurrentNanos
                ),
                frequency: .milliseconds(100)
            ) },
            locationUpdatesService: RealLocationUpdatesService(now: dateNow, canReportLocations: { sessionInitializer.isInitialized }),
            currentRadioTechnology: CTTelephonyRadioTechnologyService(),
            sendResultsService: resultSender,
            persistenceService: persistenceService,
            clock: clock
        )
    }

    private func persistedFencesResender(
        sendResultsServiceMaker: @escaping (String, Date) -> some SendCoverageResultsService
    ) -> PersistedFencesResender {
        PersistedFencesResender(
            modelContext: database.modelContext,
            sendResultsService: sendResultsServiceMaker,
            maxResendAge: maxResendAge,
            dateNow: dateNow
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

private struct MockFencePersistenceService: FencePersistenceService {
    func save(_ fence: Fence) throws {}
}

private struct EmptyAsyncSequence: AsyncSequence {
    typealias Element = NetworkCoverageViewModel.Update
    
    struct AsyncIterator: AsyncIteratorProtocol {
        mutating func next() async throws -> NetworkCoverageViewModel.Update? { nil }
    }
    
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
}
