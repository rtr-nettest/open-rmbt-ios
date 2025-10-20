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
        // Send current fences using the main service
        if let currentTestUUID = testUUID() {
            let mainService = sendResultsService(currentTestUUID)
            try await mainService.send(fences: fences)

            try modelContext.delete(model: PersistentFence.self, where: #Predicate { $0.testUUID == currentTestUUID })
            try modelContext.save()
        } else {
            throw ServiceError.missingTestUUID
        }

        // Resend any remaining persistent fences
        try await persistentAreasResender.resendPersistentAreas(isLaunched: true)
    }
}
