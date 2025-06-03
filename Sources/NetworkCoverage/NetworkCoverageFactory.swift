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
            for: PersistentLocationArea.self,
            isStoredInMemoryOnly: useInMemoryStore
        )
        container = try! ModelContainer(
            for: PersistentLocationArea.self,
            configurations: configuration
        )
    }

    lazy var modelContext: ModelContext = .init(container)
}

struct NetworkCoverageFactory {
    private let database: UserDatabase

    init(database: UserDatabase) {
        self.database = database
    }

    func services(
        testUUID: @escaping @autoclosure () -> String?,
        sendResultsServiceMaker: @escaping (String) -> some SendCoverageResultsService
    ) -> (some FencePersistenceService, some SendCoverageResultsService) {
        let resultSender = PersistenceManagingCoverageResultsService(
            modelContext: database.modelContext,
            testUUID: testUUID(),
            sendResultsService: sendResultsServiceMaker
        )
        let persistenceService = SwiftDataFencePersistenceService(
            modelContext: database.modelContext,
            testUUID: testUUID()
        )

        return (persistenceService, resultSender)
    }

    @MainActor func makeCoverageViewModel(areas: [LocationArea] = []) -> NetworkCoverageViewModel {
        let dateNow: () -> Date = Date.init
        let sessionInitializer = CoverageMeasurementSessionInitializer(
            now: dateNow,
            controlServer: RMBTControlServer.shared
        )
        let (persistenceService, resultSender) = services(testUUID: sessionInitializer.lastTestUUID) { testUUID in
            ControlServerCoverageResultsService(
                controlServer: RMBTControlServer.shared,
                testUUID: testUUID
            )
        }

        return NetworkCoverageViewModel(
            areas: areas,
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
}
