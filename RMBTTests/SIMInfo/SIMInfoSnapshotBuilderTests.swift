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

    @Test("WHEN no services are present THEN every count is zero and no cellular is reported")
    func whenNoServices_thenAllCountsZeroAndNoCellular() {
        let summary = SIMInfoSnapshotBuilder.makeSummary(from: makeSnapshot())

        #expect(summary.reliableServiceCount == 0)
        #expect(summary.subscriberServiceCount == 0)
        #expect(summary.totalServiceCount == 0)
        #expect(summary.hasCellularService == false)
        #expect(summary.exposesMultipleReliableServices == false)
    }

    @Test(
        "WHEN the reliable radio API exposes N services THEN reliable count and multiplicity reflect N",
        arguments: [
            ([String: String](), 0, false, false),
            ([oneServiceID: CTRadioAccessTechnologyLTE], 1, false, true),
            ([oneServiceID: CTRadioAccessTechnologyNR, twoServiceID: CTRadioAccessTechnologyLTE], 2, true, true)
        ]
    )
    func whenRadioServicesVary_thenReliableCountAndMultiplicityMatch(
        radioTechnologyByService: [String: String],
        expectedReliableCount: Int,
        expectedExposesMultiple: Bool,
        expectedHasCellular: Bool
    ) {
        let summary = SIMInfoSnapshotBuilder.makeSummary(
            from: makeSnapshot(radioTechnologyByService: radioTechnologyByService)
        )

        #expect(summary.reliableServiceCount == expectedReliableCount)
        #expect(summary.exposesMultipleReliableServices == expectedExposesMultiple)
        #expect(summary.hasCellularService == expectedHasCellular)
    }

    @Test("WHEN the reliable API exposes one service but the deprecated carrier API exposes two THEN reliable count stays one and the carrier-only service is flagged low confidence")
    func whenDeprecatedCarrierAddsExtraService_thenNotCountedAsReliable() throws {
        let snapshot = makeSnapshot(
            radioTechnologyByService: [oneServiceID: CTRadioAccessTechnologyLTE],
            carrierByService: [oneServiceID: placeholderCarrier, twoServiceID: placeholderCarrier],
            dataServiceIdentifier: oneServiceID
        )

        let summary = SIMInfoSnapshotBuilder.makeSummary(from: snapshot)
        #expect(summary.reliableServiceCount == 1)
        #expect(summary.subscriberServiceCount == 2)
        #expect(summary.totalServiceCount == 2)
        #expect(summary.exposesMultipleReliableServices == false)
        #expect(summary.subscriberCountDiffersFromReliable == true)

        let items = SIMInfoSnapshotBuilder.makeItems(from: snapshot)
        #expect(items.map(\.isReportedByReliableAPI) == [true, false])
    }

    @Test("WHEN only a data service identifier is present with empty dictionaries THEN it still counts as cellular")
    func whenOnlyDataServiceIdentifier_thenStillCellular() throws {
        let snapshot = makeSnapshot(dataServiceIdentifier: oneServiceID)

        let summary = SIMInfoSnapshotBuilder.makeSummary(from: snapshot)
        #expect(summary.hasCellularService == true)
        #expect(summary.reliableServiceCount == 1)

        let item = try #require(SIMInfoSnapshotBuilder.makeItems(from: snapshot).first)
        #expect(item.serviceIdentifier == oneServiceID)
        #expect(item.isDataService == true)
        #expect(item.isReportedByReliableAPI == true)
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
        let snapshot = makeSnapshot(carrierByService: [oneServiceID: placeholderCarrier])

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

    // MARK: - Carrier placeholder detection

    @Test(
        "WHEN carrier fields are inspected THEN iOS 16.4 placeholders are detected and real values are not",
        arguments: [
            (placeholderCarrier, true),
            (realCarrier, false),
            (CarrierDetails(carrierName: "A1", mobileCountryCode: "65535", mobileNetworkCode: "65535"), false),
            (CarrierDetails(), true)
        ]
    )
    func whenCarrierInspected_thenPlaceholderDetected(carrier: CarrierDetails, expectedPlaceholder: Bool) {
        #expect(carrier.looksLikePlaceholder == expectedPlaceholder)
    }
}

// MARK: - SIMInfoViewModel

@MainActor
@Suite("SIMInfoViewModel")
struct SIMInfoViewModelTests {

    @Test("WHEN initialized THEN it exposes the summary and items derived from the provider snapshot")
    func whenInitialized_thenExposesProviderSnapshot() {
        let (sut, _) = makeSUT(snapshot: dualServiceSnapshot)

        #expect(sut.summary.reliableServiceCount == 2)
        #expect(sut.items.map(\.serviceIdentifier) == [oneServiceID, twoServiceID])
    }

    @Test("WHEN refreshed THEN it re-reads the provider and reflects the latest snapshot")
    func whenRefreshed_thenReflectsLatestSnapshot() {
        let (sut, provider) = makeSUT(snapshot: dualServiceSnapshot)
        let callsAfterInit = provider.currentSnapshotCallCount

        provider.snapshot = singleServiceSnapshot
        sut.refresh()

        #expect(provider.currentSnapshotCallCount == callsAfterInit + 1)
        #expect(sut.summary.reliableServiceCount == 1)
        #expect(sut.items.map(\.serviceIdentifier) == [oneServiceID])
    }

    @Test("WHEN observing and the provider signals a change THEN the items refresh automatically")
    func whenObservingAndProviderChanges_thenItemsRefresh() {
        let (sut, provider) = makeSUT(snapshot: singleServiceSnapshot)
        sut.startObserving()

        provider.simulateChange(to: dualServiceSnapshot)

        #expect(sut.items.map(\.serviceIdentifier) == [oneServiceID, twoServiceID])
    }

    @Test("WHEN observing stops THEN the provider is told to stop and later changes are ignored")
    func whenStopObserving_thenProviderStopsAndIgnoresLaterChanges() {
        let (sut, provider) = makeSUT(snapshot: singleServiceSnapshot)
        sut.startObserving()

        sut.stopObserving()
        provider.simulateChange(to: dualServiceSnapshot)

        #expect(provider.stopObservingCallCount == 1)
        #expect(sut.items.map(\.serviceIdentifier) == [oneServiceID])
    }
}

// MARK: - makeSUT & Factories

@MainActor
private func makeSUT(snapshot: CellularSnapshot) -> (SIMInfoViewModel, CellularSnapshotProviderSpy) {
    let provider = CellularSnapshotProviderSpy(snapshot: snapshot)
    let sut = SIMInfoViewModel(provider: provider)
    return (sut, provider)
}

private func makeSnapshot(
    radioTechnologyByService: [String: String] = [:],
    carrierByService: [String: CarrierDetails] = [:],
    dataServiceIdentifier: String? = nil
) -> CellularSnapshot {
    CellularSnapshot(
        radioTechnologyByService: radioTechnologyByService,
        carrierByService: carrierByService,
        dataServiceIdentifier: dataServiceIdentifier
    )
}

// Opaque CoreTelephony-style service identifiers, named for intent.
private let oneServiceID = "0000000100000001"
private let twoServiceID = "0000000100000002"

private let placeholderCarrier = CarrierDetails(carrierName: "--", mobileCountryCode: "65535", mobileNetworkCode: "65535")
private let realCarrier = CarrierDetails(
    carrierName: "A1 Telekom",
    mobileCountryCode: "232",
    mobileNetworkCode: "01",
    isoCountryCode: "at",
    allowsVOIP: true
)

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
