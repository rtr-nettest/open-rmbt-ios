//
//  ConnectivityServiceTests.swift
//  RMBTTests
//
//  Created by Jiri Urbasek on 21/10/2025.
//

import XCTest
@testable import RMBT

final class ConnectivityServiceTests: XCTestCase {

    private typealias LocalIPs = (ipv4: String?, ipv6: String?)

    func test_whenIpv4AndIpv6Succeed_thenDeliversLatestConnectivityInfo() {
        let (sut, controlServer, _, initialIps) = makeSUT()

        let info = expectConnectivity(of: sut, refresh: true) {
            controlServer.completeSettingsSuccess()
            controlServer.completeIpv4Success(ip: "203.0.113.4")
            controlServer.completeIpv6Success(ip: "2001:db8::4")
        }

        XCTAssertEqual(info.ipv4.internalIp, initialIps.ipv4)
        XCTAssertEqual(info.ipv4.externalIp, "203.0.113.4")
        XCTAssertEqual(info.ipv6.internalIp, initialIps.ipv6)
        XCTAssertEqual(info.ipv6.externalIp, "2001:db8::4")
        XCTAssertTrue(info.ipv4.connectionAvailable)
        XCTAssertTrue(info.ipv6.connectionAvailable)
    }

    func test_whenIpv4LookupFails_thenMarksIpv4Unavailable_andKeepsIpv6() {
        let (sut, controlServer, _, initialIps) = makeSUT()

        let info = expectConnectivity(of: sut, refresh: true) {
            controlServer.completeSettingsSuccess()
            controlServer.completeIpv4Failure()
            controlServer.completeIpv6Success(ip: "2001:db8::5")
        }

        XCTAssertNil(info.ipv4.externalIp)
        XCTAssertFalse(info.ipv4.connectionAvailable)
        XCTAssertEqual(info.ipv4.internalIp, initialIps.ipv4)
        XCTAssertEqual(info.ipv6.externalIp, "2001:db8::5")
        XCTAssertTrue(info.ipv6.connectionAvailable)
    }

    func test_whenIpv6BecomesUnavailable_thenClearsCachedIpv6Info() {
        let (sut, controlServer, updateLocalIps, initialIps) = makeSUT()

        // Populate initial IPv6 data
        let initialInfo = expectConnectivity(of: sut, refresh: true) {
            controlServer.completeSettingsSuccess()
            controlServer.completeIpv4Success(ip: "203.0.113.6")
            controlServer.completeIpv6Success(ip: "2001:db8::6")
        }
        XCTAssertEqual(initialInfo.ipv6.externalIp, "2001:db8::6")

        // Now IPv6 disappears
        updateLocalIps((ipv4: initialIps.ipv4, ipv6: nil))

        let refreshedInfo = expectConnectivity(of: sut, refresh: true) {
            controlServer.completeSettingsSuccess(at: 1)
            controlServer.completeIpv4Success(ip: "203.0.113.7", at: 1)
            controlServer.completeIpv6Failure(at: 1)
        }

        XCTAssertNil(refreshedInfo.ipv6.internalIp)
        XCTAssertNil(refreshedInfo.ipv6.externalIp)
        XCTAssertFalse(refreshedInfo.ipv6.connectionAvailable)
        XCTAssertEqual(refreshedInfo.ipv4.externalIp, "203.0.113.7")
    }

    func test_whenWifiActive_andOnlyCellularHasIpv6_thenReportsNoIpv6() {
        let (sut, controlServer, _, _) = makeSUT(useLocalOverrides: false)
        sut.updateActiveNetworkType(.wifi)
        sut.observedAddressProvider = {
            [
                "en0": (ipv4: "192.168.0.56", ipv6: nil),
                "pdp_ip0": (ipv4: "10.23.245.48", ipv6: "2001:db8::cell")
            ]
        }

        let info = expectConnectivity(of: sut) {
            controlServer.completeSettingsSuccess()
            controlServer.completeIpv4Success(ip: "203.0.113.11")
            controlServer.completeIpv6Failure()
        }

        XCTAssertEqual(info.ipv4.internalIp, "192.168.0.56")
        XCTAssertEqual(info.ipv4.externalIp, "203.0.113.11")
        XCTAssertTrue(info.ipv4.connectionAvailable)
        XCTAssertNil(info.ipv6.internalIp)
        XCTAssertNil(info.ipv6.externalIp)
        XCTAssertFalse(info.ipv6.connectionAvailable)
    }

    func test_whenCellularActive_prefersCellularInterfacesOverWifi() {
        let (sut, controlServer, _, _) = makeSUT(useLocalOverrides: false)
        sut.updateActiveNetworkType(.cellular)
        sut.observedAddressProvider = {
            [
                "en0": (ipv4: "192.168.0.56", ipv6: "2001:db8::wifi"),
                "pdp_ip0": (ipv4: "10.23.245.48", ipv6: "2001:db8::cell")
            ]
        }

        let info = expectConnectivity(of: sut) {
            controlServer.completeSettingsSuccess()
            controlServer.completeIpv4Success(ip: "198.51.100.3")
            controlServer.completeIpv6Success(ip: "2001:db8::extcell")
        }

        XCTAssertEqual(info.ipv4.internalIp, "10.23.245.48")
        XCTAssertEqual(info.ipv4.externalIp, "198.51.100.3")
        XCTAssertEqual(info.ipv6.internalIp, "2001:db8::cell")
        XCTAssertNotEqual(info.ipv6.internalIp, "2001:db8::wifi")
        XCTAssertEqual(info.ipv6.externalIp, "2001:db8::extcell")
        XCTAssertTrue(info.ipv4.connectionAvailable)
        XCTAssertTrue(info.ipv6.connectionAvailable)
    }

    func test_whenStartingAnotherCheck_thenIgnoresStaleResponses() {
        let (sut, controlServer, updateLocalIps, _) = makeSUT()
        var localIps: LocalIPs = (ipv4: "10.0.0.7", ipv6: "2001:db8::7")
        updateLocalIps(localIps)

        var receivedInfos = [ConnectivityInfo]()
        let expectationFresh = expectation(description: "fresh callback")
        expectationFresh.assertForOverFulfill = true

        sut.checkConnectivity(refresh: true) { info in
            receivedInfos.append(info)
            expectationFresh.fulfill()
        }

        // Start first check requests (index 0)
        controlServer.completeSettingsSuccess()

        // Trigger a second check with different IPs before the first one completes
        localIps = (ipv4: "10.0.0.8", ipv6: "2001:db8::8")
        updateLocalIps(localIps)

        sut.checkConnectivity(refresh: true) { info in
            receivedInfos.append(info)
            expectationFresh.fulfill()
        }

        // Complete stale responses (index 0) - should be ignored
        controlServer.completeIpv4Success(ip: "198.51.100.1", at: 0)
        controlServer.completeIpv6Success(ip: "2001:db8::dead", at: 0)

        XCTAssertTrue(receivedInfos.isEmpty)

        // Complete fresh responses (index 1) - should trigger callback once
        controlServer.completeSettingsSuccess(at: 1)
        controlServer.completeIpv4Success(ip: "198.51.100.2", at: 1)
        controlServer.completeIpv6Success(ip: "2001:db8::1:1", at: 1)

        wait(for: [expectationFresh], timeout: 1.0)

        XCTAssertEqual(receivedInfos.count, 1)
        XCTAssertEqual(receivedInfos.first?.ipv4.internalIp, localIps.ipv4)
        XCTAssertEqual(receivedInfos.first?.ipv4.externalIp, "198.51.100.2")
        XCTAssertEqual(receivedInfos.first?.ipv6.internalIp, localIps.ipv6)
        XCTAssertEqual(receivedInfos.first?.ipv6.externalIp, "2001:db8::1:1")
    }

    func test_whenCallingCheckConnectivity_twiceAfterSuccess_thenReturnsCachedInfoImmediately() {
        let (sut, controlServer, updateLocalIps, initialIps) = makeSUT()
        let firstInfo = expectConnectivity(of: sut, refresh: true) {
            controlServer.completeSettingsSuccess()
            controlServer.completeIpv4Success(ip: "203.0.113.9")
            controlServer.completeIpv6Success(ip: "2001:db8::9")
        }
        XCTAssertEqual(firstInfo.ipv4.externalIp, "203.0.113.9")

        var cachedInfos = [ConnectivityInfo]()
        sut.checkConnectivity { info in
            cachedInfos.append(info)
        }

        XCTAssertEqual(cachedInfos.count, 1)
        XCTAssertEqual(cachedInfos.first?.ipv4.internalIp, initialIps.ipv4)
        XCTAssertEqual(cachedInfos.first?.ipv4.externalIp, "203.0.113.9")
        XCTAssertEqual(cachedInfos.first?.ipv6.internalIp, initialIps.ipv6)
        XCTAssertEqual(cachedInfos.first?.ipv6.externalIp, "2001:db8::9")
        XCTAssertEqual(controlServer.settingsRequests.count, 1)

        // Request an explicit refresh to obtain new connectivity info
        updateLocalIps((ipv4: "10.0.0.10", ipv6: "2001:db8::10"))

        let refreshedInfo = expectConnectivity(of: sut, refresh: true) {
            controlServer.completeSettingsSuccess(at: 1)
            controlServer.completeIpv4Success(ip: "203.0.113.10", at: 1)
            controlServer.completeIpv6Success(ip: "2001:db8::10", at: 1)
        }

        XCTAssertEqual(refreshedInfo.ipv4.internalIp, "10.0.0.10")
        XCTAssertEqual(refreshedInfo.ipv4.externalIp, "203.0.113.10")
        XCTAssertEqual(refreshedInfo.ipv6.internalIp, "2001:db8::10")
        XCTAssertEqual(refreshedInfo.ipv6.externalIp, "2001:db8::10")
    }

    func test_whenCachedDataRequestedWithoutRefresh_thenNoNewControlServerRequests() {
        let (sut, controlServer, _, initialIps) = makeSUT()

        let firstInfo = expectConnectivity(of: sut, refresh: true) {
            controlServer.completeSettingsSuccess()
            controlServer.completeIpv4Success(ip: "203.0.113.12")
            controlServer.completeIpv6Success(ip: "2001:db8::12")
        }
        XCTAssertEqual(firstInfo.ipv4.internalIp, initialIps.ipv4)
        XCTAssertEqual(controlServer.settingsRequests.count, 1)

        var cachedInfos = [ConnectivityInfo]()
        sut.checkConnectivity { info in
            cachedInfos.append(info)
        }

        XCTAssertEqual(cachedInfos.count, 1)
        XCTAssertEqual(cachedInfos.first?.ipv4.externalIp, "203.0.113.12")
        XCTAssertEqual(controlServer.settingsRequests.count, 1, "Expected no additional settings requests when serving cached data")
    }

    func test_whenIpv6ExternalArrivesWithoutLocalAddress_thenRemainsUnavailable() {
        let (sut, controlServer, _, _) = makeSUT(localIps: (ipv4: "192.168.0.56", ipv6: nil))

        let info = expectConnectivity(of: sut, refresh: true) {
            controlServer.completeSettingsSuccess()
            controlServer.completeIpv4Success(ip: "203.0.113.21")
            controlServer.completeIpv6Success(ip: "2001:db8::external")
        }

        XCTAssertNil(info.ipv6.internalIp)
        XCTAssertNil(info.ipv6.externalIp)
        XCTAssertFalse(info.ipv6.connectionAvailable)
    }

    func test_whenNetworkTypeChangesDuringCheck_thenSubsequentResultUsesUpdatedInterfaces() {
        let (sut, controlServer, _, _) = makeSUT(useLocalOverrides: false)
        sut.updateActiveNetworkType(.wifi)

        var observed: [String: (ipv4: String?, ipv6: String?)] = [
            "en0": (ipv4: "192.168.0.56", ipv6: nil),
            "pdp_ip0": (ipv4: "10.23.245.48", ipv6: "2001:db8::cell")
        ]
        sut.observedAddressProvider = { observed }

        sut.checkConnectivity(refresh: true) { _ in
            // first callback intentionally ignored
        }

        // Complete settings for the first check to enqueue ipv4/ipv6 requests
        controlServer.completeSettingsSuccess()

        // Switch to cellular before finishing the first check
        sut.updateActiveNetworkType(.cellular)
        observed = [
            "pdp_ip0": (ipv4: "10.23.245.48", ipv6: "2001:db8::cell")
        ]

        var latestInfo: ConnectivityInfo?
        let exp = expectation(description: "second callback")
        sut.checkConnectivity(refresh: true) { info in
            latestInfo = info
            exp.fulfill()
        }

        // First check responses should be ignored because the checkId has changed
        controlServer.completeIpv4Success(ip: "198.51.100.10", at: 0)
        controlServer.completeIpv6Success(ip: "2001:db8::old", at: 0)

        // Complete the active (second) check
        controlServer.completeSettingsSuccess(at: 1)
        controlServer.completeIpv4Success(ip: "198.51.100.11", at: 1)
        controlServer.completeIpv6Success(ip: "2001:db8::new", at: 1)

        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(latestInfo?.ipv4.internalIp, "10.23.245.48")
        XCTAssertEqual(latestInfo?.ipv6.internalIp, "2001:db8::cell")
        XCTAssertEqual(latestInfo?.ipv4.externalIp, "198.51.100.11")
        XCTAssertEqual(latestInfo?.ipv6.externalIp, "2001:db8::new")
    }

    // MARK: - Helpers

    private func makeSUT(
        localIps: LocalIPs = (ipv4: "10.0.0.2", ipv6: "2001:db8::2"),
        useLocalOverrides: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (ConnectivityService, ControlServerSpy, (LocalIPs) -> Void, LocalIPs) {
        let controlServer = ControlServerSpy()
        let sut = ConnectivityService(controlServer: controlServer)
        var currentIps = localIps
        if useLocalOverrides {
            sut.localIpOverrides = { currentIps }
        }

        addTeardownBlock { [weak sut] in
            XCTAssertNil(sut, "Expected sut to be deallocated. Potential memory leak.", file: file, line: line)
        }

        let updateLocalIps: (LocalIPs) -> Void = { newIps in
            currentIps = newIps
        }

        return (sut, controlServer, updateLocalIps, localIps)
    }

    @discardableResult
    private func expectConnectivity(
        of sut: ConnectivityService,
        refresh: Bool = true,
        after action: () -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> ConnectivityInfo {
        let exp = expectation(description: "connectivity callback")
        var receivedInfo: ConnectivityInfo?
        sut.checkConnectivity(refresh: refresh) { info in
            receivedInfo = info
            exp.fulfill()
        }

        action()

        wait(for: [exp], timeout: 1.0)

        guard let info = receivedInfo else {
            XCTFail("Expected connectivity info", file: file, line: line)
            return ConnectivityInfo()
        }
        return info
    }
}

final class ConnectivityTrackerWiFiTests: XCTestCase {

    func test_whenWiFiSSIDResolves_thenDelegateReceivesConnectivityWithSSID() {
        let (sut, delegate, wifiProvider) = makeSUT()

        let didFetchWiFi = expectation(description: "wifi info fetch invoked")
        wifiProvider.onFetch = { didFetchWiFi.fulfill() }

        let didDetect = expectation(description: "connectivity detected")
        delegate.onDetect = { connectivity in
            guard connectivity.networkType == .wifi else { return }
            XCTAssertEqual(connectivity.networkName, "Mock SSID")
            XCTAssertEqual(connectivity.bssid, "00:00:fb:01")
            didDetect.fulfill()
        }

        sut.reachabilityDidChange(to: .wifi)
        wait(for: [didFetchWiFi], timeout: 1.0)

        wifiProvider.complete(with: (ssid: "Mock SSID", bssid: "0:0:fb:1"))
        wait(for: [didDetect], timeout: 1.0)
    }

    func test_whenWiFiSSIDUnavailable_thenDelegateReceivesConnectivityWithoutSSID() {
        let (sut, delegate, wifiProvider) = makeSUT()

        let didFetchWiFi = expectation(description: "wifi info fetch invoked")
        wifiProvider.onFetch = { didFetchWiFi.fulfill() }

        let didDetect = expectation(description: "connectivity detected")
        delegate.onDetect = { connectivity in
            guard connectivity.networkType == .wifi else { return }
            XCTAssertNil(connectivity.networkName)
            XCTAssertNil(connectivity.bssid)
            didDetect.fulfill()
        }

        sut.reachabilityDidChange(to: .wifi)
        wait(for: [didFetchWiFi], timeout: 1.0)

        wifiProvider.complete(with: nil)
        wait(for: [didDetect], timeout: 1.0)
    }

    func test_whenWiFiCompletionIsStale_thenItIsIgnored() {
        let (sut, delegate, wifiProvider) = makeSUT()

        let didFetchWiFi = expectation(description: "wifi info fetch invoked")
        wifiProvider.onFetch = { didFetchWiFi.fulfill() }

        let didDetectCellular = expectation(description: "cellular detected")
        delegate.onDetect = { connectivity in
            if connectivity.networkType == .cellular {
                didDetectCellular.fulfill()
            }
        }

        let didDetectWiFi = expectation(description: "wifi detected (should not happen)")
        didDetectWiFi.isInverted = true
        delegate.onDetect = { connectivity in
            if connectivity.networkType == .wifi {
                didDetectWiFi.fulfill()
            } else if connectivity.networkType == .cellular {
                didDetectCellular.fulfill()
            }
        }

        sut.reachabilityDidChange(to: .wifi)
        wait(for: [didFetchWiFi], timeout: 1.0)

        sut.reachabilityDidChange(to: .mobile)
        wait(for: [didDetectCellular], timeout: 1.0)

        // This completion belongs to the first reachability update and must be ignored.
        wifiProvider.complete(with: (ssid: "StaleWiFi", bssid: "00:11:22:33:44:55"))

        wait(for: [didDetectWiFi], timeout: 0.3)
    }

    // MARK: - Helpers

    private func makeSUT(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (sut: RMBTConnectivityTracker, delegate: DelegateSpy, wifiProvider: WiFiInfoProviderSpy) {
        let delegate = DelegateSpy()
        let sut = RMBTConnectivityTracker(delegate: delegate, stopOnMixed: false)
        let wifiProvider = WiFiInfoProviderSpy()
        sut.wifiInfoProvider = wifiProvider

        return (sut, delegate, wifiProvider)
    }

    private final class DelegateSpy: NSObject, RMBTConnectivityTrackerDelegate {
        var onDetect: ((RMBTConnectivity) -> Void)?
        var onNoConnectivity: (() -> Void)?

        func connectivityTracker(_ tracker: RMBTConnectivityTracker, didDetect connectivity: RMBTConnectivity) {
            onDetect?(connectivity)
        }

        func connectivityTrackerDidDetectNoConnectivity(_ tracker: RMBTConnectivityTracker) {
            onNoConnectivity?()
        }
    }

    private final class WiFiInfoProviderSpy: WiFiInfoProviding {
        var onFetch: (() -> Void)?
        private var completions: [(WiFiInfo?) -> Void] = []

        func fetchCurrent(completion: @escaping (WiFiInfo?) -> Void) {
            onFetch?()
            completions.append(completion)
        }

        func complete(with info: WiFiInfo?, at index: Int = 0) {
            completions[index](info)
        }
    }
}

// MARK: - Test Doubles

private final class ControlServerSpy: ControlServerProviding {
    fileprivate struct SettingsRequest {
        let success: EmptyCallback
        let failure: ErrorCallback
    }

    fileprivate struct IpRequest {
        let success: IpResponseSuccessCallback
        let failure: (_ error: Error?) -> Void
    }

    private(set) var settingsRequests = [SettingsRequest]()
    private(set) var ipv4Requests = [IpRequest]()
    private(set) var ipv6Requests = [IpRequest]()

    func getSettings(_ success: @escaping EmptyCallback, error failure: @escaping ErrorCallback) {
        settingsRequests.append(SettingsRequest(success: success, failure: failure))
    }

    func getIpv4(success: @escaping IpResponseSuccessCallback, error failure: @escaping (_ error: Error?) -> Void) {
        ipv4Requests.append(IpRequest(success: success, failure: failure))
    }

    func getIpv6(success: @escaping IpResponseSuccessCallback, error failure: @escaping (_ error: Error?) -> Void) {
        ipv6Requests.append(IpRequest(success: success, failure: failure))
    }

    func completeSettingsSuccess(at index: Int = 0) {
        settingsRequests[index].success()
    }

    func completeSettingsFailure(_ error: Error = TestError.any, at index: Int = 0) {
        settingsRequests[index].failure(error)
    }

    func completeIpv4Success(ip: String, at index: Int = 0) {
        ipv4Requests[index].success(makeIpResponse(ip: ip, version: "ipv4"))
    }

    func completeIpv4Failure(_ error: Error? = TestError.any, at index: Int = 0) {
        ipv4Requests[index].failure(error)
    }

    func completeIpv6Success(ip: String, at index: Int = 0) {
        ipv6Requests[index].success(makeIpResponse(ip: ip, version: "ipv6"))
    }

    func completeIpv6Failure(_ error: Error? = TestError.any, at index: Int = 0) {
        ipv6Requests[index].failure(error)
    }

    private func makeIpResponse(ip: String, version: String) -> IpResponse {
        let response = IpResponse()
        response.ip = ip
        response.version = version
        return response
    }
}

private enum TestError: Error {
    case any
}
