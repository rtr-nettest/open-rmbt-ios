//
//  RMBTControlServer.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 04.08.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import Foundation
import Alamofire

public typealias IpResponseSuccessCallback = (_ ipResponse: IpResponse) -> Void
public typealias ErrorCallback = (_ error: Error) -> Void
public typealias EmptyCallback = () -> Void

public typealias HistoryFilterType = [String: [String]]

@objc final class RMBTControlServer: NSObject {
    @objc(sharedControlServer) static let shared = RMBTControlServer()
    
    @objc public var uuid: String?
    private var uuidQueue = DispatchQueue(label: "com.netztest.nettest.uuid_queue", attributes: [])
    
    public var baseUrl = "https://netcouch.specure.com/api/v1"
    
    public var statsURL: URL? = URL(string: RMBTHelpers.RMBTLocalize(urlString: RMBTConfig.RMBT_STATS_URL))
    public var mapServerURL: URL?
    public var statisticServerURL: URL?

    public lazy var termsAndConditions: SettingsResponse.Settings.TermsAndConditions = {
        let settings = SettingsResponse.Settings.TermsAndConditions()
        settings.url = RMBTHelpers.RMBTLocalize(urlString: RMBTConfig.RMBT_PRIVACY_TOS_URL)
        settings.version = RMBTTOS.shared.lastAcceptedVersion
        return settings
    }()
    
    public var ipv4: URL?
    public var ipv6: URL?
    public var checkIpv4: URL?
    public var checkIpv6: URL?
    
    private let storeUUIDKey = "uuid_"
    private var uuidKey: String?
    
    @objc public var historyFilters: HistoryFilterType?
    public var openTestBaseURL: String?
    
    private var settings: SettingsResponse.Settings?
    
    private let settingsRequestQueue = DispatchQueue(label: "com.netztest.nettest.settings_request_queue")
    private var pendingSettingsCallbacks: [(success: EmptyCallback, failure: ErrorCallback)] = []
    private var settingsRequestInFlight = false
    
    @objc public var qosTestNames: [AnyHashable: String] {
        return QosMeasurementType.localizedNameDict //settings?.qosMeasurementTypes?.map { $0.testDesc ?? "Unknown" } ?? []
    }
    private lazy var alamofireManager: Alamofire.Session = {
        return ServerHelper.configureAlamofireManager()
    }()
    
    private var lastNewsUid: Int = UserDefaults.lastNewsUidPreference()
}

extension RMBTControlServer {
    // MARK: Settings

        ///
        @objc func getSettings(_ success: @escaping EmptyCallback, error failure: @escaping ErrorCallback) {
            settingsRequestQueue.async {
                self.pendingSettingsCallbacks.append((success: success, failure: failure))
                guard !self.settingsRequestInFlight else { return }
                self.settingsRequestInFlight = true
                self.performSettingsRequest()
            }
        }

        private func performSettingsRequest() {
            let settingsRequest = SettingsRequest()
            settingsRequest.termsAndConditionsAccepted = true
            settingsRequest.termsAndConditionsAccepted_Version = RMBTTOS.shared.lastAcceptedVersion
            settingsRequest.uuid = uuid

            let handleSuccess: (_ response: SettingsResponse) -> Void = { response in
                Log.logger.info("Control server settings fetched.")

                if let set = response.settings?.first {
                    self.settings = set

                    if let newUUID = set.uuid {
                        self.uuid = newUUID
                    }

                    if let uuidKey = self.uuidKey, let u = self.uuid {
                        KeychainHelper.storeNewUUID(uuidKey: uuidKey, uuid: u)
                    }

                    self.historyFilters = set.history

                    set.qosMeasurementTypes?.forEach({ measurementType in
                        if let theType = measurementType.testType, let theDesc = measurementType.testDesc {
                            if let type = QosMeasurementType(rawValue: theType.lowercased()) {
                                QosMeasurementType.localizedNameDict.updateValue(theDesc, forKey:type)
                            }
                        }
                    })

                    if let statistics = set.urls?.statistics,
                       let url = URL(string: statistics) {
                        self.statsURL = url
                    }

                    if let statisticServer = set.urls?.statisticsServer,
                       let url = URL(string: statisticServer) {
                        self.statisticServerURL = url
                    }

                    if let mapServer = set.urls?.mapServer,
                       let url = URL(string: mapServer) {
                        self.mapServerURL = url
                    }

                    if let ipv4Server = set.urls?.ipv4IpOnly,
                       let url = URL(string: "https://\(ipv4Server)\(RMBTConfig.shared.RMBT_CONTROL_SERVER_PATH)") {
                        self.ipv4 = url
                    }

                    if let ipv6Server = set.urls?.ipv6IpOnly,
                       let url = URL(string: "https://\(ipv6Server)\(RMBTConfig.shared.RMBT_CONTROL_SERVER_PATH)") {
                        self.ipv6 = url
                    }

                    if let theOpenTestBase = set.urls?.opendataPrefix {
                        self.openTestBaseURL = theOpenTestBase
                    }

                    if let checkip4 = set.urls?.ipv4IpCheck,
                       let url = URL(string: checkip4) {
                        self.checkIpv4 = url
                    }

                    if let checkip6 = set.urls?.ipv6IpCheck,
                       let url = URL(string: checkip6) {
                        self.checkIpv6 = url
                    }

                    if let tos = set.termsAndConditions {
                        self.termsAndConditions = tos
                    }
                }

                self.completeSettingsRequest(with: .success(()))
            }

            request(.post, path: "/settings", requestObject: settingsRequest, success: handleSuccess, error: { error in
                Log.logger.error("settings error: \(error)")
                self.completeSettingsRequest(with: .failure(error))
            })
        }

        private func completeSettingsRequest(with result: Result<Void, Error>) {
            let callbacks = settingsRequestQueue.sync { () -> [(success: EmptyCallback, failure: ErrorCallback)] in
                self.settingsRequestInFlight = false
                let callbacks = self.pendingSettingsCallbacks
                self.pendingSettingsCallbacks.removeAll()
                return callbacks
            }

            callbacks.forEach { callback in
                switch result {
                case .success:
                    callback.success()
                case .failure(let error):
                    callback.failure(error)
                }
            }
        }
    
    ///
    @objc func updateWithCurrentSettings(
        success successCallback: @escaping EmptyCallback,
        error failure: @escaping (_ error: Error?) -> Void
    ) {

        if (RMBTSettings.shared.debugUnlocked && RMBTSettings.shared.debugControlServerCustomizationEnabled) {
            let scheme = RMBTSettings.shared.debugControlServerUseSSL ? "https" : "http"
            let url = URL(string: RMBTConfig.shared.RMBT_CONTROL_SERVER_URL)
            var hostname = RMBTSettings.shared.debugControlServerHostname ?? url?.host ?? ""
            if (RMBTSettings.shared.debugControlServerPort != 0 && RMBTSettings.shared.debugControlServerPort != 80) {
                hostname = hostname.appending(":\(RMBTSettings.shared.debugControlServerPort)")
            }
            baseUrl = "\(scheme)://\(hostname)\(RMBTConfig.shared.RMBT_CONTROL_SERVER_PATH)"
        } else {
            baseUrl = RMBTConfig.shared.RMBT_CONTROL_SERVER_URL
        }
        
        guard let url = URL(string: baseUrl),
           let host = url.host else { failure(nil); return }
        
        uuidKey = "\(storeUUIDKey)\(host)"

        if self.uuid == nil,
            let key = uuidKey {
            uuid = KeychainHelper.checkStoredUUID(uuidKey: key)
        }
        
        Log.logger.info("Control Server base url = \(self.baseUrl)")
        
        // get settings of control server
        getSettings({
            // check for ip version force
            var baseUrl: URL?
            if RMBTSettings.shared.debugForceIPv6 {
                baseUrl = self.ipv6
            } else if RMBTSettings.shared.forceIPv4 {
                baseUrl = self.ipv4
            }

            if let baseUrl = baseUrl {
                self.baseUrl = baseUrl.absoluteString
                self.mapServerURL = baseUrl.appendingPathComponent("RMBTMapServer")
            }
            self.statsURL = URL(string: RMBTHelpers.RMBTLocalize(urlString: RMBTConfig.RMBT_STATS_URL))
            self.lastNewsUid = UserDefaults.lastNewsUidPreference()

            successCallback()
            
        }) { error in
            
            failure(error)
        }
    }
    
    @objc(getRoamingStatusWithParams:success:) func getRoamingStatus(with params: [AnyHashable: Any], success: @escaping RMBTSuccessBlock) {
        Log.logger.info("Checking roaming status (params = \(params)")
        
        self.ensureClientUuid { _ in
//            [self performWithUUID:^{
//                [self requestWithMethod:@"POST" path:@"status" params:params success:^(id response) {
//                    if (response && response[@"home_country"] && [response[@"home_country"] boolValue] == NO) {
//                        success(@(YES));
//                    } else {
//                        success(@(NO));
//                    }
//                } error:^(NSError *error, NSDictionary *info) {
//                }];
//            } error:^(NSError *error, NSDictionary *info) {
//            }];
        } error: { error in
            Log.logger.error(error)
        }
    }
    
    @objc func getNews(_ success: @escaping (_ response: RMBTNewsResponse) -> Void, error: @escaping ErrorCallback) {
        Log.logger.verbose("Getting news (lastNewsUid=\(lastNewsUid)...")
        let successBlock: (_ response: RMBTNewsResponse) -> Void = { response in
            let maxNews = response.news.max(by: { $0.uid >= $1.uid })
            self.lastNewsUid = Int(maxNews?.uid ?? 0)
            UserDefaults.storeLastNewsUidPreference(lastNewsUidPreference: self.lastNewsUid)
            success(response)
        }
        ensureClientUuid { uuid in
            let newsRequest = NewsRequest(with: Int64(self.lastNewsUid))
            newsRequest.uuid = uuid
            BasicRequestBuilder.addBasicRequestValues(newsRequest)
            self.request(.post, path: "/news", requestObject: newsRequest, success: successBlock, error: error)
        } error: { error in }
    }
    
    @objc func getQoSParams(_ success: @escaping (_ response: QosMeasurmentResponse) -> Void, error: @escaping ErrorCallback) {
        Log.logger.verbose("Getting QoS params...")
        ensureClientUuid(success: { uuid in
            let qosMeasurementRequest = QosMeasurementRequest()

            qosMeasurementRequest.clientUuid = uuid
            qosMeasurementRequest.uuid = uuid
            
            self.request(.post, path: "/qosTestRequest", requestObject: qosMeasurementRequest, success: success, error: error)
        }, error: error)
    }
    
    @objc(getTestParamsWithRequest:success:error:) func getTestParams(with speedMeasurementRequest: SpeedMeasurementRequest_Old, success: @escaping RMBTSuccessBlock, error failure: @escaping (_ error: Error?) -> Void) {
        ensureClientUuid(success: { uuid in
            speedMeasurementRequest.uuid = uuid
            speedMeasurementRequest.ndt = false
            speedMeasurementRequest.time = UInt64(RMBTHelpers.RMBTTimestamp(with: Date()))
            
            let success: (_ response: SpeedMeasurementResponse_Old) -> Void = { response in
                guard let tp = RMBTTestParams(with: response.toJSON()) else {
                    failure(nil)
                    return
                }
                success(tp)
            }
            
            self.request(.post, path: "/testRequest", requestObject: speedMeasurementRequest, success: success, error: failure)
        }, error: failure)
//        NSMutableDictionary *requestParams = [NSMutableDictionary dictionaryWithDictionary:@{
//            @"ndt": @NO,
//            @"time": RMBTTimestampWithNSDate([NSDate date])
//        }];
//
//        [requestParams addEntriesFromDictionary:params];
//
//        [self performWithUUID:^{
//            [self requestWithMethod:@"POST" path:@"testRequest" params:requestParams success:^(NSDictionary *response) {
//                RMBTTestParams *tp = [[RMBTTestParams alloc] initWithResponse:response];
//                if (tp) {
//                    success(tp);
//                } else {
//                    RMBTLog(@"Invalid test parameters: %@", response);
//                    errorCallback();
//                }
//             } error:^(NSError *err, NSDictionary *response) {
//                RMBTLog(@"Fetching test parameters failed with err=%@, response=%@", err, response);
//                errorCallback();
//             }];
//        } error:^(NSError *error, NSDictionary *info) {
//            errorCallback();
//        }];
    }
    
    @objc(getHistoryWithFilters:length:offset:success:error:) func getHistoryWithFilters(
        filters: HistoryFilterType?,
        length: UInt,
        offset: UInt,
        success: @escaping (_ response: HistoryWithFiltersResponse) -> Void,
        error errorCallback: @escaping ErrorCallback
    ) {
        getHistoryWithFilters(
            filters: filters,
            length: length,
            offset: offset,
            includeCoverageFences: RMBTSettings.shared.coverageFeatureEnabled,
            success: success,
            error: errorCallback
        )
    }
    
    @objc(getHistoryWithFilters:length:offset:includeCoverageFences:success:error:) func getHistoryWithFilters(filters: HistoryFilterType?, length: UInt, offset: UInt, includeCoverageFences: Bool, success: @escaping (_ response: HistoryWithFiltersResponse) -> Void, error errorCallback: @escaping ErrorCallback) {

        ensureClientUuid(success: { uuid in
            let req = HistoryWithFiltersRequest()
            BasicRequestBuilder.addBasicRequestValues(req)
            req.uuid = uuid
            req.resultLimit = NSNumber(value: length)
            req.resultOffset = NSNumber(value: offset)
            req.includeCoverageFences = includeCoverageFences
            //
            if let theFilters = filters {
                for filter in theFilters {
                    //
                    if filter.key == "devices" {
                      req.devices = filter.value
                    }
                    //
                    if filter.key == "networks" {
                        req.networks = filter.value
                    }
                }
            }
            
            self.request(.post, path: "/history", requestObject: req, success: success, error: errorCallback)
        }, error: errorCallback)
    }
    
    // TODO: For fullDetails and basicDetails different root keys. (testresultdetail and testresult) so we should separate API calls
    @objc(getHistoryResultWithUUID:fullDetails:success:error:) func getHistoryResultWithUUID(uuid: String, fullDetails: Bool, success: @escaping (_ response: HistoryMeasurementResponse) -> Void, error errorCallback: @escaping ErrorCallback) {
        let key = fullDetails ? "/testresultdetail" : "/testresult"
        
        ensureClientUuid(success: { theUuid in
            
            let r = HistoryWithQOSRequest()
            BasicRequestBuilder.addBasicRequestValues(r)
            r.testUUID = uuid
            
            self.request(.post, path: key, requestObject: r, success: success, error: errorCallback)
            
        }, error: { error in
            Log.logger.debug("\(String(describing: error))")
            
            errorCallback(error)
        })
    }
    
    // TODO: For fullDetails and basicDetails different root keys. (testresultdetail and testresult) so we should separate API calls
    @objc(getFullDetailsHistoryResultWithUUID:success:error:) func getFullDetailsHistoryResultWithUUID(uuid: String, success: @escaping (_ response: FullMapMeasurementResponse) -> Void, error errorCallback: @escaping ErrorCallback) {
        let key = "/testresultdetail"
        
        ensureClientUuid(success: { clientUuid in
            
            let r = HistoryWithQOSRequest()
            BasicRequestBuilder.addBasicRequestValues(r)
            r.testUUID = uuid
            r.clientUUID = clientUuid
            
            self.request(.post, path: key, requestObject: r, success: success, error: errorCallback)
            
        }, error: { error in
            Log.logger.debug("\(String(describing: error))")
            
            errorCallback(error)
        })
    }
    
    @objc(getHistoryOpenDataResultWithUUID:success:error:) func getHistoryOpenDataResult(with uuid: String, success: @escaping (_ response: RMBTOpenDataResponse) -> Void, error: @escaping RMBTErrorBlock) {
        // Default behaviour: only 2xx considered success
        getHistoryOpenDataResult(with: uuid, acceptableStatusCodes: 200..<300, success: success, error: error)
    }

    // Variant that allows customizing acceptable status codes for OpenData endpoint (e.g., include 404)
    func getHistoryOpenDataResult(
        with uuid: String,
        acceptableStatusCodes: some Sequence<Int>,
        success: @escaping (_ response: RMBTOpenDataResponse) -> Void,
        error: @escaping RMBTErrorBlock
    ) {
        ensureClientUuid(
            success: { _ in
                let path = "/opentests/\(uuid)"
                self.request(
                    .get,
                    overrideBaseURL: self.statisticServerURL,
                    path: path,
                    requestObject: nil,
                    acceptableStatusCodes: acceptableStatusCodes,
                    success: success,
                    error: { resultError in
                        error(resultError, nil)
                    })
            },
            error: { resultError in
                error(resultError, nil)
            }
        )
    }
    
    @objc(getHistoryQoSResultWithUUID:success:error:) func getHistoryQOSResultWithUUID(testUuid: String, success: @escaping (_ response: QosMeasurementResultResponse) -> Void, error failure: @escaping ErrorCallback) {
        ensureClientUuid(success: { clientUuid in
            
            let r = HistoryWithQOSRequest()
            r.testUUID = testUuid
            r.clientUUID = clientUuid

            self.request(.post, path: "/qosTestResult?api=2", requestObject: r, success: success, error: failure)
            
        }, error: failure)
        
    }
    
    @objc func submitQOSResult(_ qosResult: QosMeasurementResultRequest, endpoint: String?, success: @escaping (_ response: QosMeasurementSubmitResponse) -> (), error failure: @escaping ErrorCallback) {
        ensureClientUuid(success: { uuid in
//            if qosResult.uuid != nil {
//                qosResult.clientUuid = uuid
                
                if let endpoint = endpoint {
                    var point = endpoint
                    if endpoint.hasPrefix(self.baseUrl) {
                        point.removeFirst(self.baseUrl.count)
                    }
                    self.request(.post, path: point, requestObject: qosResult, success: success, error: failure)
                } else {
                    self.request(.post, path: "/qosResult", requestObject: qosResult, success: success, error: failure)
                }
                
//            } else {
//                failure(NSError(domain: "controlServer", code: 134534, userInfo: nil)) // give error if no uuid was provided by caller
//            }
        }, error: failure)
    }
    
    @objc func submitResult(_ speedMeasurementResult: SpeedMeasurementResult, endpoint: String?, success: @escaping (_ response: SpeedMeasurementSubmitResponse) -> (), error failure: @escaping ErrorCallback) {
        ensureClientUuid(success: { uuid in
            if speedMeasurementResult.uuid != nil {
                speedMeasurementResult.clientUuid = uuid
                
                if let endpoint = endpoint {
                    self.request(.post, path: endpoint, requestObject: speedMeasurementResult, success: success, error: failure)
                } else {
                    self.request(.post, path: "/result", requestObject: speedMeasurementResult, success: success, error: failure)
                }
                
            } else {
                failure(NSError(domain: "controlServer", code: 134534, userInfo: nil)) // give error if no uuid was provided by caller
            }
        }, error: failure)
    }

    func submitCoverageResult(
        _ coverageRequest: SendCoverageResultRequest,
        acceptableStatusCodes: some Sequence<Int>,
        success: @escaping (_ response: CoverageMeasurementSubmitResponse) -> (),
        error failure: @escaping ErrorCallback
    ) {
        ensureClientUuid(
            success: { uuid in
                coverageRequest.clientUUID = uuid
                self.request(
                    .post,
                    path: "/coverageResult",
                    requestObject: coverageRequest,
                    acceptableStatusCodes: acceptableStatusCodes,
                    success: success,
                    error: failure
                )
            },
            error: failure
        )
    }

    func getCoverageRequest(
        _ request: CoverageRequestRequest,
        loopUUID: String? = nil,
        success: @escaping (_ response: SignalRequestResponse) -> (),
        error failure: @escaping ErrorCallback
    ) {
        ensureClientUuid(
            success: { uuid in
                request.clientUUID = uuid
                request.uuid = uuid
                request.loopUUID = loopUUID
                self.request(.post, path: "/coverageRequest", requestObject: request, success: success, error: failure)
            },
            error: failure
        )
    }

    ///
    @objc(getSyncCode:error:) func getSyncCode(success: @escaping (_ response: GetSyncCodeResponse) -> (), error failure: @escaping ErrorCallback) {
        ensureClientUuid(success: { uuid in
            let req = GetSyncCodeRequest()
            req.uuid = uuid
            self.request(.post, path: "/sync", requestObject: req, success: success, error: failure)
        }, error: failure)
    }
    
    ///
    @objc(syncWithCode:success:error:) func syncWithCode(_ code:String, success: @escaping (_ response: SyncCodeResponse) -> (), error failure: @escaping ErrorCallback) {
        ensureClientUuid(success: { uuid in
            let req = SyncCodeRequest()
            req.code = code
            req.uuid = uuid
            self.request(.post, path: "/sync", requestObject: req, success: success, error: failure)
        }, error: failure)
    }
    
    func getIpv4( success successCallback: @escaping IpResponseSuccessCallback, error failure: @escaping (_ error: Error?) -> Void) {
        guard let url = self.checkIpv4 else { failure(nil); return }
        getIpVersion(baseUrl: url.absoluteString, success: successCallback, error: failure)
    }
    
    func getIpv6( success successCallback: @escaping IpResponseSuccessCallback, error failure: @escaping (_ error: Error?) -> Void) {
        guard let url = self.checkIpv6 else { failure(nil); return }
        getIpVersion(baseUrl: url.absoluteString, success: successCallback, error: failure)
    }
    
    func getIpVersion(baseUrl:String, success successCallback: @escaping IpResponseSuccessCallback, error failure: @escaping ErrorCallback) {

        let infoParams = IPRequest_Old()
        infoParams.uuid = self.uuid
        infoParams.plattform = "iOS"
        
        ServerHelper.request(alamofireManager, baseUrl: baseUrl, method: .post, path: "", requestObject: infoParams, success: successCallback , error: failure)
    }
    
    @objc func ensureClientUuid(success successCallback: @escaping (_ uuid: String) -> (), error errorCallback: @escaping ErrorCallback) {
        uuidQueue.async {
            if let uuid = self.uuid {
                successCallback(uuid)
            } else {
                self.uuidQueue.suspend()

                self.getSettings({
                    self.uuidQueue.resume()

                    if let uuid = self.uuid {
                        successCallback(uuid)
                    } else {
                        errorCallback(NSError(domain: "strange error, should never happen, should have uuid by now", code: -1234345, userInfo: nil))
                    }
                }, error: { error in
                    self.uuidQueue.resume()
                    errorCallback(error)
                })
            }
        }
    }

    func getTestExport(into format: TestExportFormat, openTestUUIDs: [String]) async throws -> URL {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 60.0
        sessionConfig.timeoutIntervalForResource = 60.0
        let session = URLSession(configuration: sessionConfig)

        return try await session.download(
            for: format.downloadRequest(
                baseURL: statisticServerURL ?? URL(string: "https://app-cloud.netztest.at/RMBTStatisticServer")!,
                openTestUUIDs: openTestUUIDs,
                maxResults: openTestUUIDs.count > 1 ? min(openTestUUIDs.count, 100) : nil
            )
        ).0
    }

    func clearStoredUUID() {
        baseUrl = RMBTConfig.shared.RMBT_CONTROL_SERVER_URL
        uuidKey = "\(storeUUIDKey)\(URL(string: baseUrl)!.host!)"
        
        KeychainHelper.clearStoredUUID(uuidKey: uuidKey)
        self.uuid = nil
    }
    
    private func requestArray<T: BasicResponse>(_ method: Alamofire.HTTPMethod, path: String, requestObject: BasicRequest?, success: @escaping (_ response: [T]) -> (), error failure: @escaping ErrorCallback) {
        ServerHelper.requestArray(alamofireManager, baseUrl: baseUrl, method: method, path: path, requestObject: requestObject, success: success, error: failure)
    }

    private func request<T: BasicResponse>(
        _ method: Alamofire.HTTPMethod,
        overrideBaseURL: URL? = nil,
        path: String,
        requestObject: BasicRequest?,
        acceptableStatusCodes: some Sequence<Int> = 200..<300,
        success: @escaping  (_ response: T) -> (),
        error failure: @escaping ErrorCallback
    ) {
        ServerHelper.request(
            alamofireManager,
            baseUrl: overrideBaseURL?.absoluteString ?? baseUrl,
            method: method,
            path: path,
            requestObject: requestObject,
            acceptableStatusCodes: acceptableStatusCodes,
            success: success,
            error: failure
        )
    }
    
    private func request<T: BasicResponse>(_ baseUrl: String?, _ method: Alamofire.HTTPMethod, path: String, requestObject: BasicRequest?, success: @escaping  (_ response: T) -> (), error failure: @escaping ErrorCallback) {
        ServerHelper.request(alamofireManager, baseUrl: baseUrl, method: method, path: path, requestObject: requestObject, success: success, error: failure)
    }
    
    private func request<T: BasicResponse>(_ method: Alamofire.HTTPMethod, path: String, requestObjects: [BasicRequest]?, key: String?, success: @escaping  (_ response: T) -> (), error failure: @escaping ErrorCallback) {
        ServerHelper.request(alamofireManager, baseUrl: baseUrl, method: method, path: path, requestObjects: requestObjects, key: key, success: success, error: failure)
    }
    
    @objc func cancelAllRequests() {
        alamofireManager.cancelAllRequests()
    }
}
