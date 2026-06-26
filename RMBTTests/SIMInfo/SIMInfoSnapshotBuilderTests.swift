//
//  SIMInfoSnapshotBuilderTests.swift
//  RMBTTests
//

import Testing
import CoreTelephony
@testable import RMBT

@Suite("SIMInfoSnapshotBuilder")
struct SIMInfoSnapshotBuilderTests {

    // MARK: - Summary

    @Test("WHEN no services are present THEN the count is zero and no cellular is reported")
    func whenNoServices_thenCountZeroAndNoCellular() {
        let summary = SIMInfoSnapshotBuilder.makeSummary(from: makeSnapshot())

        #expect(summary.serviceCount == 0)
        #expect(summary.hasCellularService == false)
        #expect(summary.exposesMultipleServices == false)
    }

    @Test(
        "WHEN the radio API exposes N services THEN the count and multiplicity reflect N",
        arguments: [
            ([String: String](), 0, false, false),
            ([oneServiceID: CTRadioAccessTechnologyLTE], 1, false, true),
            ([oneServiceID: CTRadioAccessTechnologyNR, twoServiceID: CTRadioAccessTechnologyLTE], 2, true, true)
        ]
    )
    func whenRadioServicesVary_thenCountAndMultiplicityMatch(
        radioTechnologyByService: [String: String],
        expectedCount: Int,
        expectedExposesMultiple: Bool,
        expectedHasCellular: Bool
    ) {
        let summary = SIMInfoSnapshotBuilder.makeSummary(
            from: makeSnapshot(radioTechnologyByService: radioTechnologyByService)
        )

        #expect(summary.serviceCount == expectedCount)
        #expect(summary.exposesMultipleServices == expectedExposesMultiple)
        #expect(summary.hasCellularService == expectedHasCellular)
    }

    @Test("WHEN only a data service identifier is present with empty dictionaries THEN it still counts as cellular")
    func whenOnlyDataServiceIdentifier_thenStillCellular() throws {
        let snapshot = makeSnapshot(dataServiceIdentifier: oneServiceID)

        let summary = SIMInfoSnapshotBuilder.makeSummary(from: snapshot)
        #expect(summary.hasCellularService == true)
        #expect(summary.serviceCount == 1)

        let item = try #require(SIMInfoSnapshotBuilder.makeItems(from: snapshot).first)
        #expect(item.serviceIdentifier == oneServiceID)
        #expect(item.isDataService == true)
        #expect(item.isRegistered == false)
    }

    // MARK: - Per-service technology

    @Test(
        "WHEN a service has a known radio technology THEN it maps to a friendly label and generation",
        arguments: [
            (CTRadioAccessTechnologyGPRS, "2G/GSM", "2G"),
            (CTRadioAccessTechnologyEdge, "2G/EDGE", "2G"),
            (CTRadioAccessTechnologyWCDMA, "3G/UMTS", "3G"),
            (CTRadioAccessTechnologyHSDPA, "3G/HSDPA", "3G"),
            (CTRadioAccessTechnologyLTE, "4G/LTE", "4G"),
            (CTRadioAccessTechnologyNRNSA, "5G/NRNSA", "5G"),
            (CTRadioAccessTechnologyNR, "5G/NR", "5G")
        ]
    )
    func whenKnownTechnology_thenMapsToFriendlyLabelAndGeneration(
        rawTechnology: String,
        expectedLabel: String,
        expectedGeneration: String
    ) throws {
        let snapshot = makeSnapshot(
            radioTechnologyByService: [oneServiceID: rawTechnology],
            dataServiceIdentifier: oneServiceID
        )

        let item = try #require(SIMInfoSnapshotBuilder.makeItems(from: snapshot).first)
        #expect(item.technologyLabel == expectedLabel)
        #expect(item.generationLabel == expectedGeneration)
        #expect(item.isRegistered == true)
    }

    @Test("WHEN a service has empty technology THEN it is not registered and has no technology")
    func whenEmptyTechnology_thenNotRegistered() throws {
        let snapshot = makeSnapshot(radioTechnologyByService: [oneServiceID: ""])

        let item = try #require(SIMInfoSnapshotBuilder.makeItems(from: snapshot).first)
        #expect(item.isRegistered == false)
        #expect(item.technologyLabel == nil)
        #expect(item.generationLabel == nil)
    }

    @Test("WHEN the radio technology constant is unknown THEN the raw value is shown and the service is registered")
    func whenUnknownTechnology_thenRawValueShown() throws {
        let snapshot = makeSnapshot(
            radioTechnologyByService: [oneServiceID: "SomeFutureTech"],
            dataServiceIdentifier: oneServiceID
        )

        let item = try #require(SIMInfoSnapshotBuilder.makeItems(from: snapshot).first)
        #expect(item.technologyLabel == "SomeFutureTech")
        #expect(item.isRegistered == true)
    }

    // MARK: - Data service identification (the core dual-SIM claim)

    @Test("WHEN two services have different technologies THEN only the data service is flagged as data while the standby service keeps its own technology")
    func whenTwoServices_thenOnlyDataServiceFlagged() {
        let snapshot = makeSnapshot(
            radioTechnologyByService: [
                oneServiceID: CTRadioAccessTechnologyNR,
                twoServiceID: CTRadioAccessTechnologyLTE
            ],
            dataServiceIdentifier: twoServiceID
        )

        let items = SIMInfoSnapshotBuilder.makeItems(from: snapshot)

        // Deterministic order is [oneServiceID, twoServiceID]; only the data service (LTE) is flagged,
        // and the standby service keeps its own, different technology.
        #expect(items.map(\.serviceIdentifier) == [oneServiceID, twoServiceID])
        #expect(items.map(\.technologyLabel) == ["5G/NR", "4G/LTE"])
        #expect(items.map(\.isDataService) == [false, true])
    }

    @Test("WHEN there is no data service identifier THEN no service is flagged as data")
    func whenNoDataServiceIdentifier_thenNoneFlagged() {
        let snapshot = makeSnapshot(
            radioTechnologyByService: [
                oneServiceID: CTRadioAccessTechnologyLTE,
                twoServiceID: CTRadioAccessTechnologyNR
            ]
        )

        let items = SIMInfoSnapshotBuilder.makeItems(from: snapshot)
        #expect(items.allSatisfy { $0.isDataService == false })
    }

    // MARK: - Ordering & naming

    @Test("WHEN multiple services are present THEN they are ordered deterministically and named positionally")
    func whenMultipleServices_thenDeterministicOrderAndPositionalNames() {
        let snapshot = makeSnapshot(
            radioTechnologyByService: [
                twoServiceID: CTRadioAccessTechnologyLTE,
                oneServiceID: CTRadioAccessTechnologyNR
            ],
            dataServiceIdentifier: oneServiceID
        )

        let items = SIMInfoSnapshotBuilder.makeItems(from: snapshot)

        #expect(items.map(\.serviceIdentifier) == [oneServiceID, twoServiceID])
        #expect(items.map(\.displayName) == ["Cellular service 1", "Cellular service 2"])
    }
}

// MARK: - ConnectivityHeuristic (best-effort airplane-mode / offline hint)

@Suite("ConnectivityHeuristic")
struct ConnectivityHeuristicTests {

    @Test("WHEN the network path has not been evaluated yet THEN the hint is undetermined")
    func whenPathNotEvaluated_thenUndetermined() {
        #expect(ConnectivityHeuristic.airplaneModeHint(hasNetworkPath: nil, hasCellularRadio: false) == .undetermined)
        #expect(ConnectivityHeuristic.airplaneModeHint(hasNetworkPath: nil, hasCellularRadio: true) == .undetermined)
    }

    @Test("WHEN a network path is available THEN the device is reported connected regardless of the radio")
    func whenNetworkPathAvailable_thenConnected() {
        #expect(ConnectivityHeuristic.airplaneModeHint(hasNetworkPath: true, hasCellularRadio: true) == .connected)
        #expect(ConnectivityHeuristic.airplaneModeHint(hasNetworkPath: true, hasCellularRadio: false) == .connected)
    }

    @Test("WHEN there is no network path but the cellular radio is up THEN it is not flagged as airplane mode")
    func whenNoPathButRadioUp_thenNotAirplaneMode() {
        #expect(ConnectivityHeuristic.airplaneModeHint(hasNetworkPath: false, hasCellularRadio: true) == .noPathButRadioPresent)
    }

    @Test("WHEN there is no network path and no cellular radio THEN airplane mode / offline is the best-effort guess")
    func whenNoPathAndNoRadio_thenLikelyAirplaneMode() {
        #expect(ConnectivityHeuristic.airplaneModeHint(hasNetworkPath: false, hasCellularRadio: false) == .likelyAirplaneModeOrOffline)
    }

    @Test("WHEN any service reports a non-empty radio technology THEN the cellular radio is considered active")
    func whenServiceReportsTechnology_thenRadioActive() {
        let snapshot = CellularSnapshot(radioTechnologyByService: [oneServiceID: CTRadioAccessTechnologyLTE])
        #expect(ConnectivityHeuristic.hasCellularRadio(in: snapshot) == true)
    }

    @Test("WHEN no service reports a non-empty radio technology THEN the cellular radio is considered inactive")
    func whenNoServiceReportsTechnology_thenRadioInactive() {
        #expect(ConnectivityHeuristic.hasCellularRadio(in: CellularSnapshot()) == false)
        #expect(ConnectivityHeuristic.hasCellularRadio(in: CellularSnapshot(radioTechnologyByService: [oneServiceID: ""])) == false)
    }
}

// MARK: - CTTelephonyCellularSnapshotProvider (live observation lifecycle)

@MainActor
@Suite("CTTelephonyCellularSnapshotProvider")
struct CTTelephonyCellularSnapshotProviderTests {

    // A private NotificationCenter keeps each test isolated from the system and from parallel tests.
    @Test("WHEN observeChanges is registered repeatedly THEN a single radio-technology change fires exactly one callback")
    func whenObserveChangesRegisteredTwice_thenSingleCallbackPerChange() async {
        let center = NotificationCenter()
        let provider = CTTelephonyCellularSnapshotProvider(notificationCenter: center)

        // expectedCount: 1 fails if the prior registration leaked and double-fires.
        await confirmation("change handler fires once", expectedCount: 1) { fired in
            provider.observeChanges { fired() }
            provider.observeChanges { fired() }   // must replace, not stack, the observer

            center.post(name: .CTServiceRadioAccessTechnologyDidChange, object: nil)
            // Let the main-queue notification block and the @MainActor hop both run.
            try? await Task.sleep(for: .milliseconds(100))
            provider.stopObserving()
        }
    }

    @Test("WHEN observation is stopped THEN a later radio-technology change fires no callback")
    func whenStopped_thenLaterChangeIgnored() async {
        let center = NotificationCenter()
        let provider = CTTelephonyCellularSnapshotProvider(notificationCenter: center)

        await confirmation("change handler never fires after stop", expectedCount: 0) { fired in
            provider.observeChanges { fired() }
            provider.stopObserving()

            center.post(name: .CTServiceRadioAccessTechnologyDidChange, object: nil)
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

// MARK: - SIMInfoViewModel

@MainActor
@Suite("SIMInfoViewModel")
struct SIMInfoViewModelTests {

    @Test("WHEN initialized THEN it exposes the summary and items derived from the provider snapshot")
    func whenInitialized_thenExposesProviderSnapshot() {
        let (sut, _, _) = makeSUT(snapshot: dualServiceSnapshot)

        #expect(sut.summary.serviceCount == 2)
        #expect(sut.items.map(\.serviceIdentifier) == [oneServiceID, twoServiceID])
    }

    @Test("WHEN refreshed THEN it re-reads the provider and reflects the latest snapshot")
    func whenRefreshed_thenReflectsLatestSnapshot() {
        let (sut, provider, _) = makeSUT(snapshot: dualServiceSnapshot)
        let callsAfterInit = provider.currentSnapshotCallCount

        provider.snapshot = singleServiceSnapshot
        sut.refresh()

        #expect(provider.currentSnapshotCallCount == callsAfterInit + 1)
        #expect(sut.summary.serviceCount == 1)
        #expect(sut.items.map(\.serviceIdentifier) == [oneServiceID])
    }

    @Test("WHEN observing and the provider signals a change THEN the items refresh automatically")
    func whenObservingAndProviderChanges_thenItemsRefresh() {
        let (sut, provider, _) = makeSUT(snapshot: singleServiceSnapshot)
        sut.startObserving()

        provider.simulateChange(to: dualServiceSnapshot)

        #expect(sut.items.map(\.serviceIdentifier) == [oneServiceID, twoServiceID])
    }

    @Test("WHEN observing stops THEN both the provider and the path monitor are told to stop and later changes are ignored")
    func whenStopObserving_thenProviderAndPathMonitorStop() {
        let (sut, provider, pathMonitor) = makeSUT(snapshot: singleServiceSnapshot)
        sut.startObserving()

        sut.stopObserving()
        provider.simulateChange(to: dualServiceSnapshot)

        #expect(provider.stopObservingCallCount == 1)
        #expect(pathMonitor.stopMonitoringCallCount == 1)
        #expect(sut.items.map(\.serviceIdentifier) == [oneServiceID])
    }

    @Test("WHEN the path monitor has not evaluated yet THEN the airplane-mode hint is undetermined")
    func whenPathNotEvaluated_thenHintUndetermined() {
        let (sut, _, _) = makeSUT(snapshot: singleServiceSnapshot, hasNetworkPath: nil)

        #expect(sut.airplaneModeHint == .undetermined)
    }

    @Test("WHEN there is no network path and no cellular radio THEN the hint becomes likely airplane mode after a path change")
    func whenNoPathAndNoRadio_thenHintLikelyAirplaneMode() {
        let (sut, _, pathMonitor) = makeSUT(snapshot: noServiceSnapshot, hasNetworkPath: nil)
        sut.startObserving()

        pathMonitor.simulatePathChange(hasNetworkPath: false)

        #expect(sut.airplaneModeHint == .likelyAirplaneModeOrOffline)
    }

    @Test("WHEN a network path becomes available THEN the hint reports connected")
    func whenNetworkPathAvailable_thenHintConnected() {
        let (sut, _, pathMonitor) = makeSUT(snapshot: noServiceSnapshot, hasNetworkPath: nil)
        sut.startObserving()

        pathMonitor.simulatePathChange(hasNetworkPath: true)

        #expect(sut.airplaneModeHint == .connected)
    }
}

// MARK: - makeSUT & Factories

@MainActor
private func makeSUT(
    snapshot: CellularSnapshot,
    hasNetworkPath: Bool? = true
) -> (SIMInfoViewModel, CellularSnapshotProviderSpy, NetworkPathMonitoringSpy) {
    let provider = CellularSnapshotProviderSpy(snapshot: snapshot)
    let pathMonitor = NetworkPathMonitoringSpy(hasNetworkPath: hasNetworkPath)
    let sut = SIMInfoViewModel(provider: provider, pathMonitor: pathMonitor)
    return (sut, provider, pathMonitor)
}

private func makeSnapshot(
    radioTechnologyByService: [String: String] = [:],
    dataServiceIdentifier: String? = nil
) -> CellularSnapshot {
    CellularSnapshot(
        radioTechnologyByService: radioTechnologyByService,
        dataServiceIdentifier: dataServiceIdentifier
    )
}

// Opaque CoreTelephony-style service identifiers, named for intent.
private let oneServiceID = "0000000100000001"
private let twoServiceID = "0000000100000002"

private let noServiceSnapshot = CellularSnapshot()

private let singleServiceSnapshot = CellularSnapshot(
    radioTechnologyByService: [oneServiceID: CTRadioAccessTechnologyLTE],
    dataServiceIdentifier: oneServiceID
)

private let dualServiceSnapshot = CellularSnapshot(
    radioTechnologyByService: [
        oneServiceID: CTRadioAccessTechnologyNR,
        twoServiceID: CTRadioAccessTechnologyLTE
    ],
    dataServiceIdentifier: oneServiceID
)

// MARK: - Test Doubles

/// Stands in for the live CoreTelephony provider. Returns a controllable snapshot and lets tests
/// drive the live-update callback deterministically via `simulateChange`.
private final class CellularSnapshotProviderSpy: CellularSnapshotProviding {
    var snapshot: CellularSnapshot
    private(set) var currentSnapshotCallCount = 0
    private(set) var stopObservingCallCount = 0
    private var changeHandler: (@MainActor () -> Void)?

    init(snapshot: CellularSnapshot) {
        self.snapshot = snapshot
    }

    func currentSnapshot() -> CellularSnapshot {
        currentSnapshotCallCount += 1
        return snapshot
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        changeHandler = handler
    }

    func stopObserving() {
        stopObservingCallCount += 1
        changeHandler = nil
    }

    @MainActor
    func simulateChange(to newSnapshot: CellularSnapshot) {
        snapshot = newSnapshot
        changeHandler?()
    }
}

/// Stands in for the live `NWPathMonitor`. Exposes a controllable path status and lets tests drive
/// the change callback deterministically via `simulatePathChange`.
@MainActor
private final class NetworkPathMonitoringSpy: NetworkPathMonitoring {
    private(set) var hasNetworkPath: Bool?
    private(set) var stopMonitoringCallCount = 0
    private var onChange: (@MainActor () -> Void)?

    init(hasNetworkPath: Bool?) {
        self.hasNetworkPath = hasNetworkPath
    }

    func startMonitoring(_ onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func stopMonitoring() {
        stopMonitoringCallCount += 1
        onChange = nil
    }

    func simulatePathChange(hasNetworkPath: Bool) {
        self.hasNetworkPath = hasNetworkPath
        onChange?()
    }
}
