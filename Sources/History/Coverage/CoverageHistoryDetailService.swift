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
            // Some statistic servers may return 404 with a valid JSON body for opentests.
            // Allow 404 as a successful status for this specific call to remain backward compatible elsewhere.
            controlServer.getHistoryOpenDataResult(with: testUUID, acceptableStatusCodes: Array(200..<300) + [404], success: { response in
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

            // fence_time should always be present for new data; fallback to now for legacy entries
            let dateEntered = data.fenceTime
                .map { Date(timeIntervalSince1970: Double($0) / 1000.0) } ?? Date()
            let technologyString = data.technologyId.radioAccessTechnology

            // Represent average ping using a single PingResult sample so that
            // existing UI that computes averages over pings works as expected.
            let pings: [PingResult]
            if let avgPing = data.avgPingMs, avgPing > 0 {
                pings = [PingResult(result: .interval(.milliseconds(Int(avgPing))),
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
