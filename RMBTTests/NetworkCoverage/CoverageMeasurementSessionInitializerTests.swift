//
//  CoverageMeasurementSessionInitializerTests.swift
//  RMBTTests
//

import Testing
import Foundation
@testable import RMBT

@Suite("CoverageMeasurementSessionInitializer Tests")
struct CoverageMeasurementSessionInitializerTests {
    @Test("WHEN reinitialized THEN previous test UUID is sent as loop UUID")
    func whenReinitialized_thenLoopUUIDIsChainedToPreviousTestUUID() async throws {
        let (sut, apiSpy) = makeSUT(testUUIDs: ["T1", "T2"]) 

        // First initiation — no loop_uuid
        _ = try await sut.initiate()
        #expect(apiSpy.capturedLoopUUIDs == [nil])

        // Second initiation — must pass loop_uuid = previous test_uuid (T1)
        _ = try await sut.initiate()
        #expect(apiSpy.capturedLoopUUIDs == [nil, "T1"])
    }
}

// MARK: - Test Helpers

private func makeSUT(testUUIDs: [String]) -> (CoverageMeasurementSessionInitializer, ControlServerSpy) {
    let spy = ControlServerSpy(enqueuedTestUUIDs: testUUIDs)
    let sut = CoverageMeasurementSessionInitializer(now: { Date() }, coverageAPIService: spy)
    return (sut, spy)
}

private final class ControlServerSpy: CoverageAPIService {
    var enqueuedTestUUIDs: [String]
    var capturedLoopUUIDs: [String?] = []

    init(enqueuedTestUUIDs: [String]) { self.enqueuedTestUUIDs = enqueuedTestUUIDs }

    func getCoverageRequest(
        _ request: CoverageRequestRequest,
        loopUUID: String? = nil,
        success: @escaping (_ response: SignalRequestResponse) -> (),
        error failure: @escaping ErrorCallback
    ) {
        capturedLoopUUIDs.append(loopUUID)
        let response = SignalRequestResponse()
        response.testUUID = enqueuedTestUUIDs.removeFirst()
        response.pingHost = "host"
        response.pingPort = "444"
        response.pingToken = "Z7kKKZqSYU/j7nSGbjoRLw=="
        success(response)
    }
}
