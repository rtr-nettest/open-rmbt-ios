//
//  PersistedFencesResender.swift
//  RMBT
//
//  Created by Jiri Urbasek on 30.05.2025.
//  Copyright 2025 appscape gmbh. All rights reserved.
//

import Foundation
import CoreLocation

struct PersistedFencesResender {
    private let persistence: PersistenceServiceActor
    private let sendResultsService: (String, Date) -> any SendCoverageResultsService
    private let maxResendAge: TimeInterval
    private let dateNow: () -> Date

    init(
        persistence: PersistenceServiceActor,
        sendResultsService: @escaping (String, Date) -> some SendCoverageResultsService,
        maxResendAge: TimeInterval,
        dateNow: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.sendResultsService = sendResultsService
        self.maxResendAge = maxResendAge
        self.dateNow = dateNow
    }

    func resendPersistentAreas(isLaunched: Bool) async throws {
        Log.logger.info("Starting resend operation, mode: \(isLaunched ? "cold start" : "warm start")")
        try? await persistence.cleanupOldSessionsAndOrphans(maxAge: maxResendAge, now: dateNow(), isLaunched: isLaunched)

        let sessions: [PersistentCoverageSession] = try await {
            if isLaunched {
                return try await persistence.sessionsToSubmitCold()
            } else {
                return try await persistence.sessionsToSubmitWarm()
            }
        }()

        Log.logger.info("Found \(sessions.count) session(s) to resend")

        // Submit oldest first (FIFO order)
        for (index, session) in sessions.reversed().enumerated() {
            let startedAtDate = Date(timeIntervalSince1970: Double(session.startedAt) / 1_000_000)
            let anchorAtDate = session.anchorAt.map { Date(timeIntervalSince1970: Double($0) / 1_000_000) }
            let finalizedAtDate = session.finalizedAt.map { Date(timeIntervalSince1970: Double($0) / 1_000_000) }

            Log.logger.info("Session[\(index)]: testUUID=\(session.testUUID ?? "nil"), loopUUID=\(session.loopUUID ?? "nil"), fenceCount=\(session.fences.count), startedAt=\(startedAtDate), anchorAt=\(anchorAtDate?.description ?? "nil"), finalizedAt=\(finalizedAtDate?.description ?? "nil")")

            guard let uuid = session.testUUID, let anchorAt = session.anchorAt else {
                Log.logger.warning("Skipping session without UUID or anchor: testUUID=\(session.testUUID ?? "nil"), anchorAt=\(session.anchorAt?.description ?? "nil")")
                continue
            }
            let fencesToSend = session.fences.map(makeFence).sorted(by: { $0.dateEntered < $1.dateEntered })
            let anchorDate = Date(timeIntervalSince1970: Double(anchorAt) / 1_000_000)
            Log.logger.info("Resending session: uuid=\(uuid), fenceCount=\(fencesToSend.count)")
            let service = sendResultsService(uuid, anchorDate)
            do {
                try await service.send(fences: fencesToSend)
                try await persistence.delete([session])
                Log.logger.info("[Successfully resent and deleted session: \(uuid)")
            } catch {
                Log.logger.error("Resend failed for \(uuid): \(error.localizedDescription)")
            }
        }
        Log.logger.info("Resend operation completed")
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
