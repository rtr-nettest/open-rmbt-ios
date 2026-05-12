import Foundation

protocol SessionAnchoringService {
    func anchorOfflineSession() async throws -> (testUUID: String, anchorAt: Date)
}

struct CoverageRequestSessionAnchoring: SessionAnchoringService {
    let coverageAPIService: any CoverageAPIService
    let now: () -> Date

    func anchorOfflineSession() async throws -> (testUUID: String, anchorAt: Date) {
        let initializer = CoreSessionInitializer(now: now, coverageAPIService: coverageAPIService)
        let credentials = try await initializer.startNewSession()
        return (credentials.testID, now())
    }
}
