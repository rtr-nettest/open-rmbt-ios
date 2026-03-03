//
//  CoverageHistoryDetailServiceTests.swift
//  RMBTTests
//

import Testing
import ObjectMapper
@testable import RMBT

@Suite("CoverageHistoryDetailService – convertFenceData")
struct CoverageHistoryDetailServiceTests {

    // MARK: - fence_time

    @Test func whenFenceTimePresent_thenDateEnteredMatchesFenceTime() throws {
        let fenceTimeMs: Int64 = 1_768_141_426_991
        let expectedDate = Date(timeIntervalSince1970: Double(fenceTimeMs) / 1000.0)

        let fences = makeSUT().convertFenceData([
            try makeFenceData(fenceTime: fenceTimeMs)
        ])

        let fence = try #require(fences.first)
        #expect(fence.dateEntered == expectedDate)
    }

    @Test func whenFenceTimeMissing_thenDateEnteredDefaultsToCurrentDate() throws {
        let before = Date()
        let fences = makeSUT().convertFenceData([
            try makeFenceData(fenceTime: nil)
        ])
        let after = Date()

        let fence = try #require(fences.first)
        #expect(fence.dateEntered >= before && fence.dateEntered <= after)
    }

    // MARK: - avg_ping_ms

    @Test func whenAvgPingPresent_thenFenceHasPingValue() throws {
        let pingMs: Double = 42.0

        let fences = makeSUT().convertFenceData([
            try makeFenceData(avgPingMs: pingMs)
        ])

        let fence = try #require(fences.first)
        #expect(fence.averagePing == 42)
    }

    @Test func whenAvgPingMissing_thenFenceHasNoPing() throws {
        let fences = makeSUT().convertFenceData([
            try makeFenceData(avgPingMs: nil)
        ])

        let fence = try #require(fences.first)
        #expect(fence.averagePing == nil)
    }

    @Test func whenAvgPingZero_thenFenceHasNoPing() throws {
        let fences = makeSUT().convertFenceData([
            try makeFenceData(avgPingMs: 0)
        ])

        let fence = try #require(fences.first)
        #expect(fence.averagePing == nil)
    }

    // MARK: - duration_ms

    @Test func whenDurationPresent_thenFenceHasExitDate() throws {
        let fenceTimeMs: Int64 = 1_768_141_426_991
        let durationMs = 4000

        let fences = makeSUT().convertFenceData([
            try makeFenceData(durationMs: durationMs, fenceTime: fenceTimeMs)
        ])

        let fence = try #require(fences.first)
        let expectedExit = Date(timeIntervalSince1970: Double(fenceTimeMs) / 1000.0 + 4.0)
        #expect(fence.dateExited == expectedExit)
    }

    @Test func whenDurationMissing_thenFenceHasNoExitDate() throws {
        let fences = makeSUT().convertFenceData([
            try makeFenceData(durationMs: nil)
        ])

        let fence = try #require(fences.first)
        #expect(fence.dateExited == nil)
    }
}

// MARK: - makeSUT & Factories

private func makeSUT() -> CoverageHistoryDetailService {
    CoverageHistoryDetailService()
}

private func makeFenceData(
    technologyId: Int = 13,
    latitude: Double = 47.017,
    longitude: Double = 15.510,
    offsetMs: Int = 14698,
    durationMs: Int? = nil,
    radius: Double = 42,
    avgPingMs: Double? = 4.2,
    fenceTime: Int64? = 1_768_141_426_991
) throws -> FenceData {
    var json: [String: Any] = [
        "technology_id": technologyId,
        "latitude": latitude,
        "longitude": longitude,
        "offset_ms": offsetMs,
        "radius": radius
    ]
    if let durationMs { json["duration_ms"] = durationMs }
    if let avgPingMs { json["avg_ping_ms"] = avgPingMs }
    if let fenceTime { json["fence_time"] = fenceTime }

    return try Mapper<FenceData>().map(JSON: json)
}
