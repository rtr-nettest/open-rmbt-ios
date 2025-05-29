import Foundation
import SwiftData

final class SwiftDataFencePersistenceService: FencePersistenceService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func save(_ area: LocationArea) throws {
        let persistentArea = PersistentLocationArea(from: area)
        modelContext.insert(persistentArea)
        try modelContext.save()
    }

    func clearAll() throws {
        try modelContext.delete(model: PersistentLocationArea.self)
        try modelContext.save()
    }
}