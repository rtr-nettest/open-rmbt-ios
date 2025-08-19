//
//  CoverageHistoryTests.swift
//  RMBTTests
//
//  Created by Jiri Urbasek on 18/08/2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Testing
@testable import RMBT
import CoreLocation

@MainActor struct CoverageHistoryTests {
    
    @Test func testHistoryItemCoverageMapping() throws {
        // Test that HistoryItem correctly maps coverage fields
        let jsonData: [String: Any] = [
            "test_uuid": "test-123",
            "open_test_uuid": "open-123",
            "time": 1692360000000,
            "time_string": "Aug 18 12:00",
            "is_coverage_fences": true,
            "fences_count": 5,
            "loop_uuid": "loop-456"
        ]
        
        let historyItem = HistoryItem(JSON: jsonData)
        
        #expect(historyItem?.testUuid == "test-123")
        #expect(historyItem?.openTestUuid == "open-123")
        #expect(historyItem?.isCoverageFences == true)
        #expect(historyItem?.fencesCount == 5)
        #expect(historyItem?.loopUuid == "loop-456")
        #expect(historyItem?.timeString == "Aug 18 12:00")
    }
    
    @Test func testRMBTHistoryCoverageResultInitialization() throws {
        let historyItem = HistoryItem()
        historyItem.testUuid = "test-123"
        historyItem.openTestUuid = "open-123"
        historyItem.time = 1692360000000
        historyItem.timeString = "Aug 18 12:00"
        historyItem.networkType = "LTE"
        historyItem.loopUuid = "loop-456"
        historyItem.isCoverageFences = true
        historyItem.fencesCount = 3
        
        let coverageResult = RMBTHistoryCoverageResult(historyItem: historyItem)
        
        #expect(coverageResult.uuid == "test-123")
        #expect(coverageResult.openTestUuid == "open-123")
        #expect(coverageResult.loopUuid == "loop-456")
        #expect(coverageResult.timeString == "Aug 18 12:00")
        #expect(coverageResult.networkTypeServerDescription == "LTE")
        #expect(coverageResult.historyItem.fencesCount == 3)
        #expect(coverageResult.historyItem.isCoverageFences == true)
    }
    
    @Test func testFenceDataMapping() throws {
        let jsonData: [String: Any] = [
            "fence_id": "fence-123",
            "technology_id": 7,
            "technology": "5G/NRNSA",
            "longitude": 13.37696845562318,
            "latitude": 49.74805411063806,
            "offset_ms": 1000,
            "duration_ms": 5000,
            "radius": 10.5
        ]
        
        let fenceData = FenceData(JSON: jsonData)
        
        #expect(fenceData?.fenceId == "fence-123")
        #expect(fenceData?.technologyId == 7)
        #expect(fenceData?.technology == "5G/NRNSA")
        #expect(fenceData?.longitude == 13.37696845562318)
        #expect(fenceData?.latitude == 49.74805411063806)
        #expect(fenceData?.offsetMs == 1000)
        #expect(fenceData?.durationMs == 5000)
        #expect(fenceData?.radius == 10.5)
    }
}

class MockCoverageHistoryDetailService: CoverageHistoryDetailService {
    var shouldThrowError = false
    var mockFences: [Fence] = []
    
    override func loadCoverageDetails(for testUUID: String) async throws -> CoverageHistoryDetail {
        if shouldThrowError {
            throw URLError(.badServerResponse)
        }
        
        return CoverageHistoryDetail(
            fences: mockFences,
            testUUID: testUUID,
            startDate: nil,
            metadata: [:]
        )
    }
}

@MainActor struct CoverageHistoryDetailServiceTests {
    
    @Test func testFenceDataConversion() throws {
        let service = CoverageHistoryDetailService()
        
        let jsonData: [String: Any] = [
            "fence_id": "fence-1",
            "latitude": 49.748,
            "longitude": 13.377,
            "offset_ms": 1000,
            "duration_ms": 5000,
            "technology": "5G"
        ]
        
        guard let fenceData = FenceData(JSON: jsonData) else {
            Issue.record("Failed to create FenceData from JSON")
            return
        }
        
        let fences = service.convertFenceData([fenceData])
        
        #expect(fences.count == 1)
        let fence = fences[0]
        #expect(fence.startingLocation.coordinate.latitude == 49.748)
        #expect(fence.startingLocation.coordinate.longitude == 13.377)
        #expect(fence.technology == "5G")
        #expect(fence.dateExited != nil)
    }
}

