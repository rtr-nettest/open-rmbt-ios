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

class CoverageHistoryDetailService {
    private let controlServer: RMBTControlServer
    
    init(controlServer: RMBTControlServer = .shared) {
        self.controlServer = controlServer
    }
    
    func loadCoverageDetails(for testUUID: String) async throws -> CoverageHistoryDetail {
        return try await withCheckedThrowingContinuation { continuation in
            // For now, create a simple mock implementation since the API method doesn't exist yet
            // TODO: Replace with actual API call when getHistoryOpenDataResult is implemented
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                let mockFences: [Fence] = []
                let detail = CoverageHistoryDetail(
                    fences: mockFences,
                    testUUID: testUUID,
                    startDate: nil,
                    metadata: [:]
                )
                continuation.resume(returning: detail)
            }
        }
    }
    
    internal func convertFenceData(_ fenceData: [FenceData]) -> [Fence] {
        return fenceData.compactMap { data in
            // Validate data before conversion
            guard let lat = data.latitude,
                  let lng = data.longitude,
                  let offsetMs = data.offsetMs,
                  lat >= -90 && lat <= 90,
                  lng >= -180 && lng <= 180 else {
                return nil
            }
            
            let location = CLLocation(latitude: lat, longitude: lng)
            let dateEntered = Date(timeIntervalSince1970: TimeInterval(offsetMs) / 1000.0)
            let technology = data.technology
            
            var fence = Fence(
                startingLocation: location,
                dateEntered: dateEntered,
                technology: technology
            )
            
            if let durationMs = data.durationMs {
                let exitDate = Date(timeIntervalSince1970: TimeInterval(offsetMs + durationMs) / 1000.0)
                fence.exit(at: exitDate)
            }
            
            return fence
        }
    }
}