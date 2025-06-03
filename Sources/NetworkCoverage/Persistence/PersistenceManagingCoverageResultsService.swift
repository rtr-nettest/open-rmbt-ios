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
    private let persistentAreasResender: PersistentAreasResender

    init(
        modelContext: ModelContext,
        testUUID: @escaping @autoclosure () -> String?,
        sendResultsService: @escaping (String) -> some SendCoverageResultsService,
        resender: PersistentAreasResender
    ) {
        self.modelContext = modelContext
        self.testUUID = testUUID
        self.sendResultsService = sendResultsService
        self.persistentAreasResender = resender
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

        // Resend any remaining persistent areas
        try await persistentAreasResender.resendPersistentAreas()
    }
}
