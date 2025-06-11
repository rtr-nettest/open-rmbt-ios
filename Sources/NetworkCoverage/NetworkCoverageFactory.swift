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

    private let database: UserDatabase
    private let maxResendAge: TimeInterval
    private let dateNow: () -> Date = Date.init

    init(database: UserDatabase = .shared, maxResendAge: TimeInterval = Self.persistenceMaxAgeInterval) {
        self.database = database
        self.maxResendAge = maxResendAge
    }

    var persistedFencesSender: PersistedFencesResender {
        persistedFencesResender(sendResultsServiceMaker: makeSendResultsService(testUUID:))
    }

    func services(
        testUUID: @escaping @autoclosure () -> String?,
        dateNow: @escaping () -> Date, 
        sendResultsServiceMaker: @escaping (String) -> some SendCoverageResultsService
    ) -> (some FencePersistenceService, some SendCoverageResultsService) {
        let resultSender = PersistenceManagingCoverageResultsService(
            modelContext: database.modelContext,
            testUUID: testUUID(),
            sendResultsService: sendResultsServiceMaker,
            resender: persistedFencesResender(sendResultsServiceMaker: sendResultsServiceMaker)
        )
        let persistenceService = SwiftDataFencePersistenceService(
            modelContext: database.modelContext,
            testUUID: testUUID()
        )

        return (persistenceService, resultSender)
    }

    @MainActor func makeCoverageViewModel(fences: [Fence] = []) -> NetworkCoverageViewModel {
        let sessionInitializer = CoverageMeasurementSessionInitializer(
            now: dateNow,
            controlServer: RMBTControlServer.shared
        )
        let (persistenceService, resultSender) = services(
            testUUID: sessionInitializer.lastTestUUID,
            dateNow: dateNow,
            sendResultsServiceMaker: makeSendResultsService(testUUID:)
        )

        return NetworkCoverageViewModel(
            fences: fences,
            refreshInterval: 1,
            minimumLocationAccuracy: 10,
            pingMeasurementService: { PingMeasurementService.pings2(
                clock: ContinuousClock(),
                pingSender: UDPPingSession(
                    sessionInitiator: sessionInitializer,
                    udpConnection: UDPConnection(),
                    timeoutIntervalMs: 1000,
                    now: RMBTHelpers.RMBTCurrentNanos
                ),
                frequency: .milliseconds(100)
            ) },
            locationUpdatesService: RealLocationUpdatesService(now: dateNow),
            currentRadioTechnology: CTTelephonyRadioTechnologyService(),
            sendResultsService: resultSender,
            persistenceService: persistenceService
        )
    }

    private func persistedFencesResender(
        sendResultsServiceMaker: @escaping (String) -> some SendCoverageResultsService
    ) -> PersistedFencesResender {
        PersistedFencesResender(
            modelContext: database.modelContext,
            sendResultsService: sendResultsServiceMaker,
            maxResendAge: maxResendAge,
            dateNow: dateNow
        )
    }

    private func makeSendResultsService(testUUID: String) -> some SendCoverageResultsService {
        ControlServerCoverageResultsService(
            controlServer: RMBTControlServer.shared,
            testUUID: testUUID
        )
    }
}
