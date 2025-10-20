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
    private let sendResultsService: (String, Date) -> any SendCoverageResultsService
    private let maxResendAge: TimeInterval
    private let dateNow: () -> Date
    init(
        modelContext: ModelContext,
        sendResultsService: @escaping (String, Date) -> some SendCoverageResultsService,
        maxResendAge: TimeInterval,
        dateNow: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.sendResultsService = sendResultsService
        self.maxResendAge = maxResendAge
        self.dateNow = dateNow
    }

    func resendPersistentAreas(isLaunched: Bool) async throws {
        let sessions = try modelContext.fetch(FetchDescriptor<PersistentCoverageSession>())
        let unfinishedUUIDs = Set(sessions.filter { $0.finalizedAt == nil }.map(\.testUUID))

        try deleteOldPersistentFences(ignoring: unfinishedUUIDs)

        let remainingFences = try modelContext.fetch(FetchDescriptor<PersistentFence>())
        guard !remainingFences.isEmpty else {
            try cleanupSessions()
            return
        }

        let groupedFences = Dictionary(grouping: remainingFences, by: \.testUUID)
        let sortedGroups = groupedFences.sorted { groupA, groupB in
            let earliestA = groupA.value.min { $0.timestamp < $1.timestamp }?.timestamp ?? 0
            let earliestB = groupB.value.min { $0.timestamp < $1.timestamp }?.timestamp ?? 0
            return earliestA > earliestB
        }

        let sessionsByUUID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.testUUID, $0) })

        for (testUUID, persistedGroup) in sortedGroups {
            guard shouldResend(for: sessionsByUUID[testUUID], isLaunched: isLaunched) else {
                continue
            }

            let fencesToSend = persistedGroup
                .sorted { $0.timestamp < $1.timestamp }
                .map(makeFence)

            guard let startDate = fencesToSend.first?.dateEntered else { continue }

            let service = sendResultsService(testUUID, startDate)
            do {
                try await service.send(fences: fencesToSend)

                persistedGroup.forEach { modelContext.delete($0) }

                try modelContext.save()
            } catch {
                Log.logger.error("Persisted fences resend failed for \(testUUID): \(error.localizedDescription)")
            }
        }

        try cleanupSessions()
    }

    private func deleteOldPersistentFences(ignoring unfinishedTestUUIDs: Set<String>) throws {
        guard maxResendAge > 0 else { return }
        let cutoffTimestamp = UInt64(max(0, (dateNow().timeIntervalSince1970 - maxResendAge) * 1_000_000))
        let descriptor = FetchDescriptor<PersistentFence>(predicate: #Predicate { $0.timestamp < cutoffTimestamp })
        let oldFences = try modelContext.fetch(descriptor)
        var didDelete = false

        for fence in oldFences where !unfinishedTestUUIDs.contains(fence.testUUID) {
            modelContext.delete(fence)
            didDelete = true
        }

        if didDelete {
            try modelContext.save()
        }
    }

    private func cleanupSessions() throws {
        let sessions = try modelContext.fetch(FetchDescriptor<PersistentCoverageSession>())
        guard !sessions.isEmpty else { return }

        let fences = try modelContext.fetch(FetchDescriptor<PersistentFence>())
        let fencesByUUID = Dictionary(grouping: fences, by: \.testUUID)

        let cutoffTimestamp = UInt64(max(0, (dateNow().timeIntervalSince1970 - maxResendAge) * 1_000_000))
        var didDelete = false

        for session in sessions {
            let hasFences = !(fencesByUUID[session.testUUID]?.isEmpty ?? true)
            if hasFences { continue }

            let referenceTimestamp = session.finalizedAt ?? session.startedAt
            let isOlderThanMaxAge = referenceTimestamp < cutoffTimestamp
            let isFinalized = session.finalizedAt != nil

            if isFinalized || isOlderThanMaxAge {
                modelContext.delete(session)
                didDelete = true
            }
        }

        if didDelete {
            try modelContext.save()
        }
    }

    private func shouldResend(
        for session: PersistentCoverageSession?,
        isLaunched: Bool
    ) -> Bool {
        guard let session else {
            return true
        }
        if session.finalizedAt != nil {
            return true
        }
        return isLaunched
    }

    private func makeFence(from persistedFence: PersistentFence) -> Fence {
        var fence = Fence(
            startingLocation: CLLocation(
                latitude: persistedFence.latitude,
                longitude: persistedFence.longitude
            ),
            dateEntered: Date(timeIntervalSince1970: Double(persistedFence.timestamp) / 1_000_000),
            technology: persistedFence.technology,
            pings: persistedFence.avgPingMilliseconds.map {
                [PingResult(
                    result: .interval(.milliseconds($0)),
                    timestamp: Date(timeIntervalSince1970: Double(persistedFence.timestamp) / 1_000_000)
                )]
            } ?? [],
            radiusMeters: persistedFence.radiusMeters
        )

        if let exitTs = persistedFence.exitTimestamp {
            fence.exit(at: Date(timeIntervalSince1970: Double(exitTs) / 1_000_000))
        }

        return fence
    }
}
