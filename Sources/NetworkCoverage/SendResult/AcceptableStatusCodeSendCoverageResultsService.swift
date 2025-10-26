import Foundation
import Alamofire

struct AcceptableStatusCodeSendCoverageResultsService<Base: SendCoverageResultsService>: SendCoverageResultsService {
    private let base: Base
    private let acceptableStatusCodes: Set<Int>
    private let logger = Log.logger

    init(base: Base, acceptableStatusCodes: some Sequence<Int>) {
        self.base = base
        self.acceptableStatusCodes = Set(acceptableStatusCodes + [406])
    }

    func send(fences: [Fence]) async throws {
        do {
            try await base.send(fences: fences)
        } catch {
            guard
                let afError = error.asAFError,
                let statusCode = afError.responseCode,
                acceptableStatusCodes.contains(statusCode)
            else {
                throw error
            }

            logger.info("Treating HTTP \(statusCode) response as success for coverage submission despite serialization error.")
        }
    }
}
