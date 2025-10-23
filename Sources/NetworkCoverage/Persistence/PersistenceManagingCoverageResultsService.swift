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
    private let persistentAreasResender: PersistedFencesResender

    init(
        modelContext: ModelContext,
        testUUID: @escaping @autoclosure () -> String?,
        sendResultsService: @escaping (String) -> some SendCoverageResultsService,
        resender: PersistedFencesResender
    ) {
        self.modelContext = modelContext
        self.testUUID = testUUID
        self.sendResultsService = sendResultsService
        self.persistentAreasResender = resender
    }

    func send(fences: [Fence]) async throws {
        guard let currentTestUUID = testUUID() else {
            Log.logger.error("Cannot send fences: missing test UUID")
            throw ServiceError.missingTestUUID
        }

        Log.logger.info("Sending \(fences.count) fence(s) for testUUID: \(currentTestUUID)")

        // Send current fences using the main service
        let mainService = sendResultsService(currentTestUUID)
        do {
            try await mainService.send(fences: fences)
            Log.logger.info("Successfully sent fences, deleting session: \(currentTestUUID)")

            // Remove the just-submitted session by its UUID
            try modelContext.delete(model: PersistentCoverageSession.self, where: #Predicate { $0.testUUID == currentTestUUID })
            try modelContext.save()
            Log.logger.info("Deleted session from database: \(currentTestUUID)")
        } catch {
            Log.logger.error("Failed to send fences for \(currentTestUUID): \(error.localizedDescription). Session remains in database for retry.")
            throw error
        }

        Log.logger.info("Triggering resend of remaining persistent fences")

        // Resend any remaining persistent fences
        try await persistentAreasResender.resendPersistentAreas(isLaunched: false)
    }
}
