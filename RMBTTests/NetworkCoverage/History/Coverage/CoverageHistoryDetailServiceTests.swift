//
//  CoverageHistoryDetailServiceTests.swift
//  RMBTTests
//

import Testing
import ObjectMapper
import SwiftUI
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

    // MARK: - no-coverage coloring (issue #90)

    @Test func whenHistoryFenceHasNoAvgPing_thenFenceIsDrawnGrey() throws {
        // A finalized history fence with a technology but no recorded average ping is a
        // no-coverage point and must be drawn grey.
        let fences = makeSUT().convertFenceData([
            try makeFenceData(technologyId: 13, avgPingMs: nil)
        ])

        let fence = try #require(fences.first)
        #expect(fence.isNoCoverage)
        #expect(Color(fence: fence) == Color(technology: nil))
    }

    @Test func whenHistoryFenceHasAvgPing_thenFenceUsesTechnologyColor() throws {
        let fences = makeSUT().convertFenceData([
            try makeFenceData(technologyId: 13, avgPingMs: 42)
        ])

        let fence = try #require(fences.first)
        #expect(!fence.isNoCoverage)
        #expect(Color(fence: fence) != Color(technology: nil))
    }

    // MARK: - signal (Android-only; synced history)

    @Test func whenSignalPresent_thenFenceCarriesSignal() throws {
        let fences = makeSUT().convertFenceData([
            try makeFenceData(signal: -87)
        ])

        let fence = try #require(fences.first)
        #expect(fence.signal == -87)
    }

    @Test func whenSignalMissing_thenFenceHasNoSignal() throws {
        let fences = makeSUT().convertFenceData([
            try makeFenceData(signal: nil)
        ])

        let fence = try #require(fences.first)
        #expect(fence.signal == nil)
    }

    // MARK: - speed / velocity

    @Test func whenSpeedPresent_thenFenceCarriesVelocity() throws {
        let fences = makeSUT().convertFenceData([
            try makeFenceData(speed: 11.5)
        ])

        let fence = try #require(fences.first)
        #expect(fence.velocityMetersPerSecond == 11.5)
    }

    @Test func whenSpeedMissing_thenFenceHasNoVelocity() throws {
        let fences = makeSUT().convertFenceData([
            try makeFenceData(speed: nil)
        ])

        let fence = try #require(fences.first)
        #expect(fence.velocityMetersPerSecond == nil)
    }

    @Test func whenSpeedNegative_thenFenceHasNoVelocity() throws {
        // CLLocation.speed is negative when the fix carries no valid speed.
        let fences = makeSUT().convertFenceData([
            try makeFenceData(speed: -1)
        ])

        let fence = try #require(fences.first)
        #expect(fence.velocityMetersPerSecond == nil)
    }
}

@Suite("FenceDetail – signal & velocity display")
struct FenceDetailDisplayTests {
    private let formatter = DateFormatter()

    private func fenceDetail(signal: Int? = nil, speed: Double? = nil) throws -> FenceDetail {
        let fence = try #require(
            CoverageHistoryDetailService().convertFenceData([
                try makeFenceData(signal: signal, speed: speed)
            ]).first
        )
        return FenceDetail(fence: fence, selectedItemDateFormatter: formatter)
    }

    // MARK: - signal

    @Test func whenSignalPresent_thenSignalShownInDbm() throws {
        #expect(try fenceDetail(signal: -87).signal == "-87 dBm")
    }

    @Test func whenNoSignal_thenSignalRowIsEmpty() throws {
        #expect(try fenceDetail(signal: nil).signal.isEmpty)
    }

    // MARK: - velocity

    @Test func whenVelocityAboveThreshold_thenShownInRoundedKmh() throws {
        // 11.5 m/s * 3.6 = 41.4 km/h -> rounds to 41
        #expect(try fenceDetail(speed: 11.5).velocity == "41 km/h")
    }

    @Test func whenVelocityNull_thenVelocityRowIsEmpty() throws {
        #expect(try fenceDetail(speed: nil).velocity.isEmpty)
    }

    @Test func whenVelocityBelowThreshold_thenVelocityRowIsEmpty() throws {
        // 0.8 m/s is below the 0.9 m/s walking-noise threshold.
        #expect(try fenceDetail(speed: 0.8).velocity.isEmpty)
    }

    @Test func whenVelocityAtThreshold_thenVelocityShown() throws {
        // 0.9 m/s * 3.6 = 3.24 km/h -> rounds to 3
        #expect(try fenceDetail(speed: 0.9).velocity == "3 km/h")
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
    fenceTime: Int64? = 1_768_141_426_991,
    signal: Int? = nil,
    speed: Double? = nil
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
    if let signal { json["signal"] = signal }
    if let speed { json["speed"] = speed }

    return try Mapper<FenceData>().map(JSON: json)
}
