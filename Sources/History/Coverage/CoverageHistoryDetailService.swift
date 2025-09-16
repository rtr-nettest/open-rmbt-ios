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
        fenceData.compactMap { data in
            let location = CLLocation(latitude: data.latitude, longitude: data.longitude)

            // FIXME: Need to get timestamp fro server to know when the test was executed
            // Historical data provides offset_ms from test start. We don't have the
            // original test start here, so use a stable reference point (now) just
            // to construct deterministic Date values for UI ordering.
            let now = Date()
            let dateEntered = now
            let technologyString = data.technologyId.radioAccessTechnology

            // Represent average ping using a single PingResult sample so that
            // existing UI that computes averages over pings works as expected.
            let pings: [PingResult]
            if data.avgPingMs > 0 {
                pings = [PingResult(result: .interval(.milliseconds(Int(data.avgPingMs))),
                                     timestamp: dateEntered)]
            } else {
                pings = []
            }

            var fence = Fence(
                startingLocation: location,
                dateEntered: dateEntered,
                technology: technologyString,
                pings: pings,
                radiusMeters: data.radius
            )

            if let durationMs = data.durationMs {
                let exitDate = dateEntered.addingTimeInterval(TimeInterval(durationMs) / 1000.0)
                fence.exit(at: exitDate)
            }

            return fence
        }
    }
}
