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

    @inlinable var modelContext: ModelContext { .init(container) }
}

struct NetworkCoverageFactory {
    private let database: UserDatabase

    init(database: UserDatabase) {
        self.database = database
    }

    @MainActor func makeCoverageViewModel(areas: [LocationArea] = []) -> NetworkCoverageViewModel {
        let dateNow: () -> Date = Date.init
        let sessionInitializer = CoverageMeasurementSessionInitializer(
            now: dateNow,
            controlServer: RMBTControlServer.shared
        )
        let resultSender = PersistenceManagingCoverageResultsService(
            modelContext: database.modelContext,
            testUUID: sessionInitializer.lastTestUUID,
            sendResultsService: ControlServerCoverageResultsService(
                controlServer: RMBTControlServer.shared,
                testUUID: sessionInitializer.lastTestUUID
            )
        )
        let persistenceService = SwiftDataFencePersistenceService(
            modelContext: database.modelContext,
            testUUID: sessionInitializer.lastTestUUID
        )

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
