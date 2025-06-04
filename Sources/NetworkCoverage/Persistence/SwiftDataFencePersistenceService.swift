import Foundation
import SwiftData

final class SwiftDataFencePersistenceService: FencePersistenceService {
    private let modelContext: ModelContext
    private let testUUID: () -> String?

    init(modelContext: ModelContext, testUUID: @escaping @autoclosure () -> String?) {
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

    func clearAll() throws {
        try modelContext.delete(model: PersistentFence.self)
        try modelContext.save()
    }
}
