//
//  ResenderSessionBasedTests.swift
//  RMBTTests
//

import Testing
import Foundation
import CoreLocation
import SwiftData
@testable import RMBT

@MainActor
struct ResenderSessionBasedTests {
    @Test func whenReinitialized_thenSubmitsTwoSessions_withNegativeOffsetsInFirst() async throws {
        let baseTime = makeDate(offset: 100)
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { baseTime })

        // Create first session with pre-anchor and post-anchor fences
        try await persistence.sessionStarted(at: baseTime.advanced(by: -100))
        try await persistence.save(makeFence(date: baseTime.advanced(by: -90)))
        try await persistence.assignTestUUIDAndAnchor("S1", anchorNow: baseTime.advanced(by: -80))
        try await persistence.save(makeFence(date: baseTime.advanced(by: -70)))
        try await persistence.sessionFinalized(at: baseTime.advanced(by: -60))

        // Create second session
        try await persistence.sessionStarted(at: baseTime.advanced(by: -50))
        try await persistence.assignTestUUIDAndAnchor("S2", anchorNow: baseTime.advanced(by: -49))
        try await persistence.save(makeFence(date: baseTime.advanced(by: -48)))
        try await persistence.sessionFinalized(at: baseTime.advanced(by: -40))

        try await sut.resendPersistentAreas(isLaunched: true)

        try #require(sendSpy.calls.count == 2)
        let firstCall = try #require(sendSpy.calls.first)
        #expect(firstCall.uuid == "S1")
        #expect(firstCall.offsets?.first ?? 0 < 0, "First fence should have negative offset (pre-anchor)")

        let secondCall = try #require(sendSpy.calls.last)
        #expect(secondCall.uuid == "S2")
        #expect(secondCall.offsets?.allSatisfy { $0 >= 0 } == true, "All fences should have positive offsets")
    }

    @Test func whenWarmForeground_thenSubmitsOnlyFinalizedSessions() async throws {
        let now = makeDate(offset: 10_000)
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { now })

        // Create unfinished session (with fences)
        try await persistence.sessionStarted(at: now.advanced(by: -300))
        try await persistence.assignTestUUIDAndAnchor("unfinished", anchorNow: now.advanced(by: -290))
        try await persistence.save(makeFence(date: now.advanced(by: -285)))

        // Create finished session (with fences)
        try await persistence.sessionStarted(at: now.advanced(by: -200))
        try await persistence.assignTestUUIDAndAnchor("finished", anchorNow: now.advanced(by: -190))
        try await persistence.save(makeFence(date: now.advanced(by: -185)))
        try await persistence.sessionFinalized(at: now.advanced(by: -180))

        try await sut.resendPersistentAreas(isLaunched: false)

        #expect(sendSpy.calls.map { $0.uuid } == ["finished"])
    }

    @Test func whenOfflineStart_thenLateAnchorProducesNegativeOffsets() async throws {
        let t0 = makeDate(offset: 0)
        let (sut, sendSpy, persistence) = makeSUT(dateNow: { t0 })

        // Save fences before anchor is set
        try await persistence.sessionStarted(at: t0)
        try await persistence.save(makeFence(date: t0.advanced(by: -5)))
        try await persistence.save(makeFence(date: t0.advanced(by: 3)))
        try await persistence.assignTestUUIDAndAnchor("S1", anchorNow: t0.advanced(by: 1))
        try await persistence.sessionFinalized(at: t0.advanced(by: 10))

        try await sut.resendPersistentAreas(isLaunched: true)

        let offsets = try #require(sendSpy.calls.first?.offsets)
        #expect(offsets.first == -6000, "First fence at t0-5 relative to anchor t0+1")
        #expect(offsets.last == 2000, "Second fence at t0+3 relative to anchor t0+1")
    }

    @Test func whenResending_thenCleansUpEmptyAndOldSessions() async throws {
        let (sut, _, persistence) = makeSUT()
        let now = Date()

        // Create empty session
        try await persistence.sessionStarted(at: now.advanced(by: -10_000))

        // Create old nil-UUID finalized session
        try await persistence.sessionStarted(at: now.advanced(by: -10_000))
        try await persistence.sessionFinalized(at: now.advanced(by: -9_999))

        try await sut.resendPersistentAreas(isLaunched: true)

        let remaining = try await persistence.sessionsToSubmitCold()
        #expect(remaining.isEmpty)
    }
}

// MARK: - Test Helpers

private func makeSUT(
    dateNow: @escaping () -> Date = Date.init
) -> (sut: PersistedFencesResender, sendSpy: SendServiceSpy, persistence: PersistenceServiceActor) {
    let database = UserDatabase(useInMemoryStore: true)
    let persistence = PersistenceServiceActor(modelContainer: database.container)
    let sendSpy = SendServiceSpy()
    let sut = PersistedFencesResender(
        persistence: persistence,
        sendResultsService: { uuid, anchor in
            CapturingSendService(sendSpy: sendSpy, uuid: uuid, anchor: anchor)
        },
        maxResendAge: 7 * 24 * 3600,
        dateNow: dateNow
    )
    return (sut, sendSpy, persistence)
}

private func makeFence(
    lat: CLLocationDegrees = 1.0,
    lon: CLLocationDegrees = 1.0,
    date: Date
) -> Fence {
    Fence(
        startingLocation: CLLocation(
            coordinate: .init(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: 1,
            verticalAccuracy: 1,
            timestamp: date
        ),
        dateEntered: date,
        technology: nil,
        pings: [],
        radiusMeters: 20
    )
}

// MARK: - Test Doubles

private final class SendServiceSpy {
    struct Call {
        let uuid: String
        let anchor: Date
        let offsets: [Int]?
    }

    private(set) var calls: [Call] = []

    func recordSend(uuid: String, anchor: Date, offsets: [Int]?) {
        calls.append(.init(uuid: uuid, anchor: anchor, offsets: offsets))
    }
}

private struct CapturingSendService: SendCoverageResultsService {
    let sendSpy: SendServiceSpy
    let uuid: String
    let anchor: Date

    func send(fences: [Fence]) async throws {
        let request = SendCoverageResultRequest(
            fences: fences,
            testUUID: uuid,
            coverageStartDate: anchor
        )
        let offsets = request.fences.map { $0.offsetMiliseconds }
        sendSpy.recordSend(uuid: uuid, anchor: anchor, offsets: offsets)
    }
}

private struct MockSendService: SendCoverageResultsService {
    func send(fences: [Fence]) async throws {}
}
