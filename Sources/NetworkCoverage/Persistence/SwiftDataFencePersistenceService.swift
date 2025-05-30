import Foundation
import SwiftData

final class SwiftDataFencePersistenceService: FencePersistenceService {
    private let modelContext: ModelContext
    private let testUUID: () -> String?

    init(modelContext: ModelContext, testUUID: @escaping @autoclosure () -> String?) {
        self.modelContext = modelContext
        self.testUUID = testUUID
    }

    func save(_ area: LocationArea) throws {
        if let testUUID = testUUID() {
            let persistentArea = PersistentLocationArea(from: area, testUUID: testUUID)
            modelContext.insert(persistentArea)
            try modelContext.save()
        }
    }

    func clearAll() throws {
        try modelContext.delete(model: PersistentLocationArea.self)
        try modelContext.save()
    }
}
