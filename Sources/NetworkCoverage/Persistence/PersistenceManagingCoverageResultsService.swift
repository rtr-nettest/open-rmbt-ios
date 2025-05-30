//
//  PersistenceManagingCoverageResultsService.swift
//  RMBT
//
//  Created by Jiri Urbasek on 30.05.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation
import SwiftData

struct PersistenceManagingCoverageResultsService: SendCoverageResultsService {
    private let modelContext: ModelContext
    private let sendResultsService: any SendCoverageResultsService
    private let testUUID: () -> String?

    init(
        modelContext: ModelContext,
        testUUID: @escaping @autoclosure () -> String?,
        sendResultsService: some SendCoverageResultsService
    ) {
        self.modelContext = modelContext
        self.testUUID = testUUID
        self.sendResultsService = sendResultsService
    }

    func send(areas: [LocationArea]) async throws {
        try await sendResultsService.send(areas: areas)

        if let currentTestUUID = testUUID() {
            let descriptor = FetchDescriptor<PersistentLocationArea>(
                predicate: #Predicate { $0.testUUID == currentTestUUID }
            )
            let areasToDelete = try modelContext.fetch(descriptor)
            for area in areasToDelete {
                modelContext.delete(area)
            }
            try modelContext.save()
        }
    }
}
