//
//  UserDatabase.swift
//  RMBT
//
//  Created by Jiri Urbasek on 27.10.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation
import SwiftData

final class UserDatabase {
    static let shared = UserDatabase()

    let container: ModelContainer

    init(useInMemoryStore: Bool = false) {
        let configuration = ModelConfiguration(
            for: PersistentFence.self, PersistentCoverageSession.self,
            isStoredInMemoryOnly: useInMemoryStore
        )
        container = try! ModelContainer(
            for: PersistentFence.self, PersistentCoverageSession.self,
            configurations: configuration
        )
    }

    lazy var modelContext: ModelContext = .init(container)
}

extension UserDatabase {
    /// Deletes all persisted coverage data using SwiftData ModelContext.
    /// Intended for debug-only usage.
    @discardableResult
    func deleteAllPersistedCoverageData() throws -> Int {
        var deleted = 0
        // Delete PersistentFence objects
        do {
            let fenceDescriptor = FetchDescriptor<PersistentFence>()
            let fences = try modelContext.fetch(fenceDescriptor)
            for fence in fences {
                modelContext.delete(fence)
                deleted += 1
            }
        } catch {
            // Bubble up to caller; they can decide what to do in DEBUG
            throw error
        }
        // Delete PersistentCoverageSession objects
        do {
            let sessionDescriptor = FetchDescriptor<PersistentCoverageSession>()
            let sessions = try modelContext.fetch(sessionDescriptor)
            for session in sessions {
                modelContext.delete(session)
                deleted += 1
            }
        } catch {
            throw error
        }
        try modelContext.save()
        return deleted
    }

    func wipeOut() {
#if DEBUG
        do {
            let deleted = try deleteAllPersistedCoverageData()
            Log.logger.debug("Cleared persisted coverage data. Deleted items: \(deleted)")
        } catch {
            Log.logger.error("Failed to clear persisted coverage data: \(String(describing: error))")
        }
#endif
    }
}
