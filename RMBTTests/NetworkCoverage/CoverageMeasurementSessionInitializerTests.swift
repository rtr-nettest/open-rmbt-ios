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

    @Test("WHEN /coverageRequest fails AND OnlineStatusService later emits true THEN session retries successfully")
    func whenFirstAttemptFailsAndGoesOnline_thenRetrySucceeds() async throws {
        let spy = OfflineThenOnlineControlServerSpy(
            firstError: NSError(domain: "test", code: -1009)
        )
        let database = UserDatabase(useInMemoryStore: true)
        let factory = NetworkCoverageFactory(
            database: database,
            dateNow: { Date() },
            coverageAPIService: spy
        )
        let onlineStub = OnlineStatusServiceStub()
        let sut = factory.makeSessionInitializer(onlineStatusService: onlineStub, retryDelay: .zero)

        let initiationTask = Task { try await sut.startNewSession() }

        await onlineStub.waitUntilSubscribed()
        onlineStub.emit(true)

        let credentials = try await initiationTask.value
        #expect(credentials.testID == "ONLINE-UUID")
        #expect(sut.lastTestUUID == "ONLINE-UUID")
    }

    @Test("WHEN online retry fails AND reachability flips on→off→on THEN session is started on the second online signal")
    func whenRetryFailsAndReachabilityFlips_thenSucceedsOnSecondOnlineSignal() async throws {
        let spy = FlakyControlServerSpy(failCount: 2, finalTestUUID: "EVENTUAL-UUID")
        let database = UserDatabase(useInMemoryStore: true)
        let factory = NetworkCoverageFactory(
            database: database,
            dateNow: { Date() },
            coverageAPIService: spy
        )
        let onlineStub = OnlineStatusServiceStub()
        let sut = factory.makeSessionInitializer(onlineStatusService: onlineStub, retryDelay: .zero)

        let initiationTask = Task { try await sut.startNewSession() }

        await onlineStub.waitUntilSubscribed()
        onlineStub.emit(true)              // first retry — still fails
        await spy.waitForCallCount(2)      // observed: failing retry landed at the API
        onlineStub.emit(false)
        onlineStub.emit(true)              // second retry — succeeds

        let credentials = try await initiationTask.value
        #expect(credentials.testID == "EVENTUAL-UUID")
        #expect(spy.callCount == 3) // 1 initial fail + 2 retries
    }

    @Test("WHEN /coverageRequest fails AND no OnlineStatusService THEN error is rethrown")
    func whenFirstAttemptFailsWithoutOnlineService_thenThrows() async throws {
        let underlying = NSError(domain: "test", code: -1009)
        let spy = OfflineThenOnlineControlServerSpy(firstError: underlying)
        let database = UserDatabase(useInMemoryStore: true)
        let factory = NetworkCoverageFactory(
            database: database,
            dateNow: { Date() },
            coverageAPIService: spy
        )
        let sut = factory.makeSessionInitializer(onlineStatusService: nil)

        await #expect(throws: NSError.self) {
            _ = try await sut.startNewSession()
        }
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

private final class OfflineThenOnlineControlServerSpy: CoverageAPIService, @unchecked Sendable {
    private let firstError: Error
    private let lock = NSLock()
    private var _didError = false
    private var _callCount = 0
    private var _capturedLoopUUIDs: [String?] = []

    init(firstError: Error) { self.firstError = firstError }

    var callCount: Int { lock.withLock { _callCount } }
    var capturedLoopUUIDs: [String?] { lock.withLock { _capturedLoopUUIDs } }

    func getCoverageRequest(_ request: CoverageRequestRequest, loopUUID: String?, success: @escaping (SignalRequestResponse) -> (), error failure: @escaping ErrorCallback) {
        let shouldFail: Bool = lock.withLock {
            _callCount += 1
            _capturedLoopUUIDs.append(loopUUID)
            if !_didError {
                _didError = true
                return true
            }
            return false
        }
        if shouldFail {
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

/// Fails the first `failCount` calls, then succeeds with `finalTestUUID`.
/// Exposes `waitForCallCount(_:)` so tests can synchronize on attempt boundaries
/// instead of guessing with `Task.sleep`.
private final class FlakyControlServerSpy: CoverageAPIService, @unchecked Sendable {
    private let lock = NSLock()
    private let failCount: Int
    private let finalTestUUID: String
    private var _callCount = 0
    private var _waiters: [(target: Int, cont: CheckedContinuation<Void, Never>)] = []

    init(failCount: Int, finalTestUUID: String) {
        self.failCount = failCount
        self.finalTestUUID = finalTestUUID
    }

    var callCount: Int { lock.withLock { _callCount } }

    /// Suspends until `callCount >= target`. Resumes on the very call that pushes the
    /// counter past the target, before the spy invokes its callback.
    func waitForCallCount(_ target: Int) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if _callCount >= target {
                lock.unlock()
                cont.resume()
            } else {
                _waiters.append((target, cont))
                lock.unlock()
            }
        }
    }

    func getCoverageRequest(_ request: CoverageRequestRequest, loopUUID: String?, success: @escaping (SignalRequestResponse) -> (), error failure: @escaping ErrorCallback) {
        let (shouldFail, toResume): (Bool, [CheckedContinuation<Void, Never>]) = lock.withLock {
            _callCount += 1
            let ready = _waiters.filter { $0.target <= _callCount }
            _waiters.removeAll { $0.target <= _callCount }
            return (_callCount <= failCount, ready.map(\.cont))
        }
        toResume.forEach { $0.resume() }
        if shouldFail {
            failure(NSError(domain: "test", code: -1009))
            return
        }
        let response = SignalRequestResponse()
        response.testUUID = finalTestUUID
        response.pingHost = "host"
        response.pingPort = "444"
        response.pingToken = "Z7kKKZqSYU/j7nSGbjoRLw=="
        success(response)
    }
}

private final class OnlineStatusServiceStub: OnlineStatusService, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Bool>.Continuation?
    private var pendingEmissions: [Bool] = []
    private var subscribedContinuations: [CheckedContinuation<Void, Never>] = []

    func online() -> AsyncStream<Bool> {
        AsyncStream { c in
            self.lock.lock()
            self.continuation = c
            let buffered = self.pendingEmissions
            self.pendingEmissions.removeAll()
            let waiters = self.subscribedContinuations
            self.subscribedContinuations.removeAll()
            self.lock.unlock()
            buffered.forEach { c.yield($0) }
            waiters.forEach { $0.resume() }
        }
    }

    func emit(_ value: Bool) {
        lock.lock()
        if let continuation {
            lock.unlock()
            continuation.yield(value)
        } else {
            pendingEmissions.append(value)
            lock.unlock()
        }
    }

    func waitUntilSubscribed() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if continuation != nil {
                lock.unlock()
                cont.resume()
            } else {
                subscribedContinuations.append(cont)
                lock.unlock()
            }
        }
    }
}
