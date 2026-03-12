//
//  CoverageMeasurementSessionInitializerTests.swift
//  RMBTTests
//

import Testing
import Foundation
@testable import RMBT

@Suite("CoverageMeasurementSessionInitializer Tests")
struct CoverageMeasurementSessionInitializerTests {
    @Test("WHEN reinitialized THEN previous loop UUID is sent as loop UUID")
    func whenReinitialized_thenLoopUUIDIsChainedToPreviousLoopUUID() async throws {
        let (sut, apiSpy) = makeSUT(
            testUUIDs: ["T1", "T2"],
            loopUUIDs: ["L1", "L2"]
        )

        // First initiation — no loop_uuid
        _ = try await sut.initiate()
        #expect(apiSpy.capturedLoopUUIDs == [nil])

        // Second initiation — must pass loop_uuid = previous response loop_uuid (L1)
        _ = try await sut.initiate()
        #expect(apiSpy.capturedLoopUUIDs == [nil, "L1"])
    }

    @Test("WHEN starting sessions THEN lastIPVersion reflects server response and count increases")
    func whenStartingSessions_thenIpVersionAndCountUpdate() async throws {
        let (sut, apiSpy) = makeSUT(testUUIDs: ["T1", "T2", "T3"], ipVersions: [4, nil, 6])

        #expect(sut.lastIPVersion == nil)
        #expect(sut.udpPingSessionCount == 0)

        _ = try await sut.initiate() // -> IPv4
        #expect(sut.lastIPVersion == .IPv4)
        #expect(sut.udpPingSessionCount == 1)

        _ = try await sut.initiate() // -> nil
        #expect(sut.lastIPVersion == nil)
        #expect(sut.udpPingSessionCount == 2)

        _ = try await sut.initiate() // -> IPv6
        #expect(sut.lastIPVersion == .IPv6)
        #expect(sut.udpPingSessionCount == 3)
        
        // Sanity: spy should be drained
        #expect(apiSpy.enqueuedTestUUIDs.isEmpty)
    }

    @Test("WHEN reconnecting multiple times THEN session count keeps increasing")
    func whenReconnectingMultipleTimes_thenCounterIncreases() async throws {
        // Simulate five reconnections; IP version always 4
        let (sut, _) = makeSUT(testUUIDs: ["T1","T2","T3","T4","T5","T6"], ipVersions: Array(repeating: 4, count: 6))

        for expected in 1...6 {
            _ = try await sut.initiate()
            #expect(sut.udpPingSessionCount == expected)
            #expect(sut.lastIPVersion == .IPv4)
        }
    }

    @Test("GIVEN new initializer instance THEN counter starts at zero")
    func givenNewInitializer_thenCounterStartsAtZero() async throws {
        let (sut1, _) = makeSUT(testUUIDs: ["A"]) 
        _ = try await sut1.initiate()
        #expect(sut1.udpPingSessionCount == 1)

        // New instance must reset count
        let (sut2, _) = makeSUT(testUUIDs: ["B"]) 
        #expect(sut2.udpPingSessionCount == 0)
    }
}

// MARK: - Test Helpers

private func makeSUT(
    testUUIDs: [String],
    loopUUIDs: [String?] = [],
    ipVersions: [Int?] = []
) -> (CoverageMeasurementSessionInitializer, ControlServerSpy) {
    let spy = ControlServerSpy(
        enqueuedTestUUIDs: testUUIDs,
        enqueuedLoopUUIDs: loopUUIDs,
        enqueuedIpVersions: ipVersions
    )
    let database = UserDatabase(useInMemoryStore: true)
    let factory = NetworkCoverageFactory(
        database: database,
        dateNow: { Date() },
        coverageAPIService: spy
    )
    let sut = factory.makeSessionInitializer(onlineStatusService: nil)

    return (sut, spy)
}

private final class ControlServerSpy: CoverageAPIService {
    var enqueuedTestUUIDs: [String]
    var enqueuedLoopUUIDs: [String?]
    var capturedLoopUUIDs: [String?] = []
    var enqueuedIpVersions: [Int?]

    init(
        enqueuedTestUUIDs: [String],
        enqueuedLoopUUIDs: [String?] = [],
        enqueuedIpVersions: [Int?] = []
    ) {
        self.enqueuedTestUUIDs = enqueuedTestUUIDs
        self.enqueuedLoopUUIDs = enqueuedLoopUUIDs
        self.enqueuedIpVersions = enqueuedIpVersions
    }

    func getCoverageRequest(
        _ request: CoverageRequestRequest,
        loopUUID: String? = nil,
        success: @escaping (_ response: SignalRequestResponse) -> (),
        error failure: @escaping ErrorCallback
    ) {
        capturedLoopUUIDs.append(loopUUID)
        let response = SignalRequestResponse()
        response.testUUID = enqueuedTestUUIDs.removeFirst()
        response.loopUUID = enqueuedLoopUUIDs.isEmpty ? nil : enqueuedLoopUUIDs.removeFirst()
        response.pingHost = "host"
        response.pingPort = "444"
        response.pingToken = "Z7kKKZqSYU/j7nSGbjoRLw=="
        response.ipVersion = enqueuedIpVersions.isEmpty ? nil : enqueuedIpVersions.removeFirst()
        success(response)
    }
}

private final class OfflineThenOnlineControlServerSpy: CoverageAPIService {
    let firstError: Error
    private var didError = false
    init(firstError: Error) { self.firstError = firstError }
    func getCoverageRequest(_ request: CoverageRequestRequest, loopUUID: String?, success: @escaping (SignalRequestResponse) -> (), error failure: @escaping ErrorCallback) {
        if !didError {
            didError = true
            failure(firstError)
            return
        }
        let response = SignalRequestResponse()
        response.testUUID = "ONLINE-UUID"
        response.loopUUID = "ONLINE-LOOP-UUID"
        response.pingHost = "host"
        response.pingPort = "444"
        response.pingToken = "Z7kKKZqSYU/j7nSGbjoRLw=="
        success(response)
    }
}

private final class OnlineStatusServiceStub: OnlineStatusService {
    private var continuation: AsyncStream<Bool>.Continuation!
    func online() -> AsyncStream<Bool> { AsyncStream { c in self.continuation = c } }
    func emit(_ value: Bool) { continuation?.yield(value) }
}
