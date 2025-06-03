//
//  PersistenceManagingCoverageResultsService.swift
//  RMBT
//
//  Created by Jiri Urbasek on 30.05.2025.
//  Copyright 2025 appscape gmbh. All rights reserved.
//

import Foundation
import SwiftData
import CoreLocation

struct PersistenceManagingCoverageResultsService: SendCoverageResultsService {
    enum ServiceError: Error {
        case missingTestUUID
    }

    private let modelContext: ModelContext
    private let sendResultsService: (String) -> any SendCoverageResultsService
    private let testUUID: () -> String?

    init(
        modelContext: ModelContext,
        testUUID: @escaping @autoclosure () -> String?,
        sendResultsService: @escaping (String) -> some SendCoverageResultsService
    ) {
        self.modelContext = modelContext
        self.testUUID = testUUID
        self.sendResultsService = sendResultsService
    }

    func send(areas: [LocationArea]) async throws {
        // Send current areas using the main service
        if let currentTestUUID = testUUID() {
            let mainService = sendResultsService(currentTestUUID)
            try await mainService.send(areas: areas)

            // Delete persisted areas with matching testUUID
            let descriptor = FetchDescriptor<PersistentLocationArea>(
                predicate: #Predicate { $0.testUUID == currentTestUUID }
            )
            let areasToDelete = try modelContext.fetch(descriptor)
            for area in areasToDelete {
                modelContext.delete(area)
            }
            try modelContext.save()
        } else {
            throw ServiceError.missingTestUUID
        }

        // Fetch remaining persisted areas and send them grouped by testUUID
        let remainingAreas = try modelContext.fetch(FetchDescriptor<PersistentLocationArea>())
        let groupedAreas = Dictionary(grouping: remainingAreas, by: \.testUUID)

        // Sort groups by earliest timestamp in descending order (latest first)
        let sortedGroups = groupedAreas.sorted { (group1, group2) in
            let earliestTimestamp1 = group1.value.min { $0.timestamp < $1.timestamp }?.timestamp ?? 0
            let earliestTimestamp2 = group2.value.min { $0.timestamp < $1.timestamp }?.timestamp ?? 0
            return earliestTimestamp1 > earliestTimestamp2 // Descending order
        }

        for (groupTestUUID, persistentAreas) in sortedGroups {
            let sortedAreas = persistentAreas.sorted { $0.timestamp < $1.timestamp }
            let locationAreas = sortedAreas.map { persistentArea in
                LocationArea(
                    startingLocation: CLLocation(
                        latitude: persistentArea.latitude,
                        longitude: persistentArea.longitude
                    ),
                    dateEntered: Date(timeIntervalSince1970: Double(persistentArea.timestamp) / 1_000_000),
                    technology: persistentArea.technology,
                    pings: persistentArea.avgPingMilliseconds.map { [PingResult(result: .interval(.milliseconds($0)), timestamp: Date(timeIntervalSince1970: Double(persistentArea.timestamp) / 1_000_000))] } ?? []
                )
            }

            let groupService = sendResultsService(groupTestUUID)
            do {
                try await groupService.send(areas: locationAreas)

                // Delete sent areas from persistence
                for persistentArea in persistentAreas {
                    modelContext.delete(persistentArea)
                }
                try modelContext.save()
            } catch {
                // errors intentionally ignored
            }
        }
    }
}
