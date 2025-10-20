import Foundation
import SwiftData

final class SwiftDataFencePersistenceService: FencePersistenceService {
    private let modelContext: ModelContext
    private let testUUID: () -> String?

    init(modelContext: ModelContext, testUUID: @escaping () -> String?) {
        self.modelContext = modelContext
        self.testUUID = testUUID
    }

    func save(_ fence: Fence) throws {
        if let testUUID = testUUID() {
            let persistentArea = PersistentFence(from: fence, testUUID: testUUID)
            modelContext.insert(persistentArea)
            try modelContext.save()
        }
    }

    func sessionStarted(at date: Date) throws {
        guard let testUUID = testUUID() else { return }
        try upsertSession(testUUID: testUUID) { session in
            session.startedAt = date.microsecondsTimestamp
            session.finalizedAt = nil
        }
    }

    func sessionFinalized(at date: Date) throws {
        guard let testUUID = testUUID() else { return }
        try upsertSession(testUUID: testUUID) { session in
            let timestamp = date.microsecondsTimestamp
            if session.startedAt == 0 {
                session.startedAt = timestamp
            }
            session.finalizedAt = timestamp
        }
    }

    func clearAll() throws {
        try modelContext.delete(model: PersistentFence.self)
        try modelContext.save()
    }

    private func upsertSession(
        testUUID: String,
        apply changes: (PersistentCoverageSession) -> Void
    ) throws {
        let descriptor = FetchDescriptor<PersistentCoverageSession>(
            predicate: #Predicate { $0.testUUID == testUUID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            changes(existing)
        } else {
            let placeholder = PersistentCoverageSession(
                testUUID: testUUID,
                startedAt: 0
            )
            changes(placeholder)
            modelContext.insert(placeholder)
        }
        try modelContext.save()
    }
}

private extension Date {
    var microsecondsTimestamp: UInt64 {
        let microseconds = timeIntervalSince1970 * 1_000_000
        guard microseconds > 0 else { return 0 }
        return UInt64(microseconds)
    }
}
