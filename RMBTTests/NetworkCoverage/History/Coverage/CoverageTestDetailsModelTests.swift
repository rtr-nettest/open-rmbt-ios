//
//  CoverageTestDetailsModelTests.swift
//  RMBTTests
//
//  Created by Jiri Urbasek on 25/09/2025.
//

import XCTest
@testable import RMBT

@MainActor
final class CoverageTestDetailsModelTests: XCTestCase {

    // MARK: - Helpers
    private func makeItem(title: String = UUID().uuidString, value: String = UUID().uuidString) -> RMBTHistoryResultItem {
        RMBTHistoryResultItem(title: title, value: value, classification: -1, hasDetails: false)
    }

    private func makeSUT(timeString: String? = "24.09.25, 10:10:10") -> (CoverageTestDetailsModel, HistoryDetailsProviderSpy) {
        let provider = HistoryDetailsProviderSpy(timeString: timeString)
        let sut = CoverageTestDetailsModel(provider: provider)
        return (sut, provider)
    }

    // MARK: - Tests

    func test_initialState_thenNotLoading_andEmptyItems() {
        let (sut, _) = makeSUT()
        XCTAssertFalse(sut.isLoading)
        XCTAssertTrue(sut.items.isEmpty)
        XCTAssertNil(sut.loadError)
    }

    func test_whenReload_thenSetsLoadingTrueUntilProviderFinishes() {
        let (sut, provider) = makeSUT()
        sut.reload()
        XCTAssertTrue(sut.isLoading)

        // Simulate async completion with items
        let expected = [makeItem(), makeItem()]
        provider.simulateSuccess(with: expected)

        XCTAssertFalse(sut.isLoading)
        XCTAssertEqual(sut.items.count, expected.count)
        XCTAssertNil(sut.loadError)
    }

    func test_whenProviderReturnsEmpty_thenItemsEmpty_andStopsLoading() {
        let (sut, provider) = makeSUT()
        sut.reload()
        provider.simulateSuccess(with: [])

        XCTAssertFalse(sut.isLoading)
        XCTAssertTrue(sut.items.isEmpty)
    }

    func test_title_usesProviderTimeString_orFallback() {
        var (sut, _) = makeSUT(timeString: "01.01.25, 00:00:00")
        XCTAssertEqual(sut.title, "01.01.25, 00:00:00")

        (sut, _) = makeSUT(timeString: nil)
        XCTAssertEqual(sut.title, NSLocalizedString("Test details", comment: ""))
    }
}

// Spy provider implementing HistoryDetailsProvider to control behavior in tests
final class HistoryDetailsProviderSpy: HistoryDetailsProvider {
    var timeStringIn24hFormat: String?
    var fullDetailsItems: [Any]?

    private var capturedSuccess: RMBTBlock?

    init(timeString: String?) {
        self.timeStringIn24hFormat = timeString
    }

    func ensureFullDetails(success: @escaping RMBTBlock) {
        capturedSuccess = success
    }

    func simulateSuccess(with items: [RMBTHistoryResultItem]) {
        fullDetailsItems = items
        capturedSuccess?()
    }
}

