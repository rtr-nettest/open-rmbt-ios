//
//  CoverageHistoryDetailService.swift
//  RMBT
//
//  Created by Jiri Urbasek on 18/08/2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation
import CoreLocation

struct CoverageHistoryDetail {
    let fences: [Fence]
    let testUUID: String
    let startDate: Date?
    let metadata: [String: Any]
}

@Observable class CoverageHistoryDetailService {
    private let controlServer: RMBTControlServer
    
    init(controlServer: RMBTControlServer = .shared) {
        self.controlServer = controlServer
    }
    
    func loadCoverageDetails(for testUUID: String) async throws -> CoverageHistoryDetail {
        return try await withCheckedThrowingContinuation { continuation in
            controlServer.getHistoryOpenDataResult(with: testUUID, success: { response in
                let fences = self.convertFenceData(response.fences)
                let detail = CoverageHistoryDetail(
                    fences: fences,
                    testUUID: testUUID,
                    startDate: nil,
                    metadata: response.json()
                )
                continuation.resume(returning: detail)
            }, error: { error, _ in
                continuation.resume(throwing: error ?? NSError(domain: "CoverageHistoryDetailService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error occurred"]))
            })
        }
    }
    
    internal func convertFenceData(_ fenceData: [FenceData]) -> [Fence] {
        return fenceData.compactMap { data in
            
            let location = CLLocation(latitude: data.latitude, longitude: data.longitude)

            // offset_ms is milliseconds from test start, so we use it as relative time
            // For historical data, we can use a base reference time
            let baseTime = Date().timeIntervalSince1970 - TimeInterval(data.offsetMs) / 1000.0
            let dateEntered = Date(timeIntervalSince1970: baseTime + TimeInterval(data.offsetMs) / 1000.0)
            let technologyString = data.technologyId.radioAccessTechnology

            var fence = Fence(
                startingLocation: location,
                dateEntered: dateEntered,
                technology: technologyString
            )

            if let durationMs = data.durationMs {
                let exitDate = Date(timeIntervalSince1970: baseTime + TimeInterval(data.offsetMs + durationMs) / 1000.0)
                fence.exit(at: exitDate)
            }

            return fence
        }
    }
}
