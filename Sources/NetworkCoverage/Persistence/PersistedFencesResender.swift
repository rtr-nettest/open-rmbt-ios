//
//  PersistedFencesResender.swift
//  RMBT
//
//  Created by Jiri Urbasek on 30.05.2025.
//  Copyright 2025 appscape gmbh. All rights reserved.
//

import Foundation
import SwiftData
import CoreLocation

struct PersistedFencesResender {
    private let modelContext: ModelContext
    private let sendResultsService: (String) -> any SendCoverageResultsService
    private let maxResendAge: TimeInterval
    private let dateNow: () -> Date

    init(
        modelContext: ModelContext,
        sendResultsService: @escaping (String) -> some SendCoverageResultsService,
        maxResendAge: TimeInterval = 7 * 24 * 60 * 60,
        dateNow: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.sendResultsService = sendResultsService
        self.maxResendAge = maxResendAge
        self.dateNow = dateNow
    }

    func resendPersistentAreas() async throws {
        try deleteOldPersistentFences()

        // Fetch remaining persisted fences and send them grouped by testUUID
        let remainingFences = try modelContext.fetch(FetchDescriptor<PersistentFence>())
        let groupedFences = Dictionary(grouping: remainingFences, by: \.testUUID)

        // Sort groups by earliest timestamp in descending order (latest first)
        let sortedGroups = groupedFences.sorted { (group1, group2) in
            let earliestTimestamp1 = group1.value.min { $0.timestamp < $1.timestamp }?.timestamp ?? 0
            let earliestTimestamp2 = group2.value.min { $0.timestamp < $1.timestamp }?.timestamp ?? 0
            return earliestTimestamp1 > earliestTimestamp2 // Descending order
        }

        for (groupTestUUID, persistedFences) in sortedGroups {
            let sortedFences = persistedFences.sorted { $0.timestamp < $1.timestamp }
            let fences = sortedFences.map { persistedFence in
                Fence(
                    startingLocation: CLLocation(
                        latitude: persistedFence.latitude,
                        longitude: persistedFence.longitude
                    ),
                    dateEntered: Date(timeIntervalSince1970: Double(persistedFence.timestamp) / 1_000_000),
                    technology: persistedFence.technology,
                    pings: persistedFence.avgPingMilliseconds.map { [PingResult(result: .interval(.milliseconds($0)), timestamp: Date(timeIntervalSince1970: Double(persistedFence.timestamp) / 1_000_000))] } ?? []
                )
            }

            let groupService = sendResultsService(groupTestUUID)
            do {
                try await groupService.send(fences: fences)

                // Delete sent fences from persistence
                for persistedFence in persistedFences {
                    modelContext.delete(persistedFence)
                }
                try modelContext.save()
            } catch {
                // errors intentionally ignored
            }
        }
    }

    private func deleteOldPersistentFences() throws {
        let cutoffTimestamp = UInt64(max(0, (dateNow().timeIntervalSince1970 - maxResendAge) * 1_000_000))
        try modelContext.delete(model: PersistentFence.self, where: #Predicate { $0.timestamp < cutoffTimestamp })
        try modelContext.save()
    }
}
