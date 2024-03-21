//
//  RMBTTestRunner.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 21.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import CoreLocation

enum RMBTTestRunnerPhase: Int {
    case none = 0
    case fetchingTestParams
    case wait
    case `init`
    case latency
    case down
    case initUp
    case up
    case qos
    case submittingTestResult
}

enum RMBTTestRunnerCancelReason: Int {
    case userRequested
    case noConnection
    case mixedConnectivity
    case errorFetchingTestingParams
    case errorSubmittingTestResult
    case appBackgrounded
}

@inline(__always) func ASSERT_ON_WORKER_QUEUE() { assert(DispatchQueue.getSpecific(key: RMBTTestRunner.kWorkerQueueIdentityKey) != nil, "Running on a wrong queue") }

protocol RMBTTestRunnerDelegate: AnyObject {

    func testRunnerDidStart(_ phase: RMBTTestRunnerPhase)
    func testRunnerDidFinish(_ phase: RMBTTestRunnerPhase)

    /// progress from 0.0 to 1.0
    func testRunnerDidUpdateProgress(_ progress: Float, in phase: RMBTTestRunnerPhase)
    func testRunnerDidMeasurePings(_ pings: [Ping], in phase: RMBTTestRunnerPhase)
    func testRunnerDidCompleteLatencyPhase()
    func testRunnerDidMeasureThroughputs(_ throughputs: [RMBTThroughput], in phase: RMBTTestRunnerPhase)

    /// These delegate methods will be called even before the test starts
    func testRunnerDidDetectConnectivity(_ connectivity: RMBTConnectivity)
    func testRunnerDidDetectLocation(_ location: CLLocation)
    
    func testRunnerDidCompleteWithResult(_ result: RMBTHistoryResult)
    func testRunnerDidCancelTestWithReason(_ cancelReason: RMBTTestRunnerCancelReason)
    
    // QoS-related
    func testRunnerQoSDidStartWithGroups(_ groups: [RMBTQoSTestGroup], _ tests: [RMBTQoSTest])
    func testRunnerQoSGroup(_ group: RMBTQoSTestGroup, didUpdateProgress progress: Float)
    func testRunnerQoSGroup(_ group: RMBTQoSTestGroup, didUpdateProgress progress: Float, in test: RMBTQoSTest)
}

class RMBTTestRunner: NSObject {
    private let delayForPresentationGraphs: TimeInterval = 2
    private static let RMBTQosSkipTimeInterval: Double = 60 * 60 * 2 //2 hours
    private static let RMBTTestRunnerProgressUpdateInterval = 0.1 //seconds
    
    fileprivate static let kWorkerQueueIdentityKey = DispatchSpecificKey<String>()
    private static let kWorkerQueueIdentityValue = "at.rtr.rmbt.testrunner.queue"
    
    private(set) var testParams: RMBTTestParams?
    private(set) var testResult: RMBTTestResult?

    private var workersClientVersion: String?
    
    private var phase: RMBTTestRunnerPhase = .none {
        didSet {
            if (oldValue != .none) {
                DispatchQueue.main.async {
                    self.delegate?.testRunnerDidFinish(oldValue)
                }
            }

            if (phase != .none) {
                if oldValue == .down || oldValue == .up {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delayForPresentationGraphs, execute: {
                        self.delegate?.testRunnerDidStart(self.phase)
                    })
                } else {
                    DispatchQueue.main.async {
                        self.delegate?.testRunnerDidStart(self.phase)
                    }
                }
            }
        }
    }
    private lazy var workerQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "at.rtr.rmbt.testrunner")
        queue.setSpecific(key: RMBTTestRunner.kWorkerQueueIdentityKey, value: RMBTTestRunner.kWorkerQueueIdentityValue)
        return queue
    }()
    
    private var connectivityTracker: RMBTConnectivityTracker?
    
    private weak var delegate: RMBTTestRunnerDelegate?
    
    private var dead: Bool = false
    
    private var workers: [RMBTTestWorker] = []
    private var qosRunner: RMBTQoSTestRunner?
    
    var finishedWorkers: UInt = 0
    var activeWorkers: UInt = 0
    
    var progressStartedAtNanos: UInt64 = 0
    var progressDurationNanos: UInt64 = 0
    var progressCompletionHandler: RMBTBlock?
    
    var downlinkTestStartedAtNanos: UInt64 = 0
    var uplinkTestStartedAtNanos: UInt64 = 0
    var qosTestStartedAtNanos: UInt64 = 0
    var qosTestFinishedAtNanos: UInt64 = 0
    
    // Snapshots of the network interface byte counts at a given phase
    var startInterfaceInfo: RMBTConnectivityInterfaceInfo?
    var uplinkStartInterfaceInfo: RMBTConnectivityInterfaceInfo?
    var uplinkEndInterfaceInfo: RMBTConnectivityInterfaceInfo?
    var downlinkStartInterfaceInfo: RMBTConnectivityInterfaceInfo?
    var downlinkEndInterfaceInfo: RMBTConnectivityInterfaceInfo?
    
    var timer: DispatchSourceTimer?
    
    // Flag indicating that downlink pretest in one of the workers was too slow and we need to
    // continue with a single thread only
    var singleThreaded: Bool = false
    
    deinit {
        cleanup()
    }
    
    init(delegate: RMBTTestRunnerDelegate) {
        self.delegate = delegate

        super.init()
        connectivityTracker = RMBTConnectivityTracker(delegate: self, stopOnMixed: true)
        connectivityTracker?.start()
    }

    func start(with extraParams: [String: Any]? = nil) { // optional extra params like loop info
        workerQueue.async { [weak self] in
            guard let self = self else { return }
            assert(self.phase == .none, "Invalid state")
            assert(!self.dead, "Invalid state")

            // TODO: unify location serialization with test runner and here
            var locationJSON: [String: Any]? = nil

            let location = RMBTLocationTracker.shared.location
            if let l = location {
                locationJSON = l.paramsDictionary()
            }

            var params: [String: Any] = [
                "testCounter": RMBTSettings.shared.testCounter,
                "previousTestStatus": RMBTValueOrString(RMBTSettings.shared.previousTestStatus, RMBTTestStatus.None.rawValue),
                "location": RMBTValueOrNull(locationJSON)
            ]

            if let extraParams = extraParams {
                extraParams.forEach { item in
                    params[item.key] = item.value
                }
            }

            // Notice that we post previous counter (the test before this one) when requesting the params
            RMBTSettings.shared.testCounter += 1
            self.phase = .fetchingTestParams

            let request = SpeedMeasurementRequest_Old()
            request.testCounter = RMBTSettings.shared.testCounter
            request.previousTestStatus = RMBTValueOrString(RMBTSettings.shared.previousTestStatus, RMBTTestStatus.None.rawValue) as? String
            if let l = location {
                request.geoLocation = GeoLocation(location: l)
            }
            if (extraParams != nil) {
                request.loopModeEnabled = true;
                request.loopModeInfo = params["loopmode_info"] as? [String : Any]
            }
            
            RMBTControlServer.shared.getTestParams(with: request) { [weak self] testParams in
                self?.workerQueue.async {
                    guard let self = self else { return }
                    guard let testParams = testParams as? RMBTTestParams else {
                        self.cancel(with: .errorFetchingTestingParams)
                        return
                    }

                    self.continue(with: testParams)
                }
            } error: { [weak self] error in
                self?.workerQueue.async {
                    guard let self = self else { return }
                    self.cancel(with: .errorFetchingTestingParams)
                }
            }
        }
    }
    
    func startQoS() {
        if let token = testParams?.testToken {
            RMBTSettings.shared.previousLaunchQoSDate = Date()
            self.phase = .qos;
            qosRunner = RMBTQoSTestRunner(delegate: self)
            qosRunner?.start(with: token)
        } else {
            self.cancel(with: .errorFetchingTestingParams)
        }
    }
    
    // Run on worker queue
    func `continue`(with testParams: RMBTTestParams) {
        ASSERT_ON_WORKER_QUEUE();

        if (dead) { return } // Cancelled
            
        assert(phase == .fetchingTestParams || phase == .none, "Invalid state")

        self.testParams = testParams
        self.testResult = RMBTTestResult(resolutionNanos: UInt64(RMBTConfig.RMBT_TEST_SAMPLING_RESOLUTION_MS) * NSEC_PER_MSEC)
        self.testResult?.markTestStart()

        self.workers = []
        self.workers.reserveCapacity(Int(testParams.threadCount))
        
        for i in 0..<testParams.threadCount {
            workers.append(RMBTTestWorker(delegate: self, delegateQueue: workerQueue, index: i, testParams: testParams))
        }

        // Start observing app going to background notifications
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidSwitchToBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        
        // Register as observer for location tracker updates
        NotificationCenter.default.addObserver(self, selector: #selector(locationsDidChange), name: NSNotification.RMBTLocationTrackerNotification, object: nil)
        
        // ..and force an update right away
        RMBTLocationTracker.shared.forceUpdate()
        connectivityTracker?.forceUpdate()

        let startInit: RMBTBlock = {
            self.startPhase(.`init`, withAllWorkers: true, performingSelector: #selector(RMBTTestWorker.startDownlinkPretest), expectedDuration: testParams.pretestDuration, completion: nil)
        }

        if (testParams.waitDuration > 0) {
            // Let progress timer run, then start init
            self.startPhase(.`init`, withAllWorkers: false, performingSelector: nil, expectedDuration: testParams.waitDuration, completion: startInit)
        } else {
            startInit()
        }
    }
    
    func cancel(with reason: RMBTTestRunnerCancelReason) {
        ASSERT_ON_WORKER_QUEUE()

        self.cleanup()
        
        workers.forEach({ $0.abort() })
        
        qosRunner?.cancel()
        
        switch reason {
        case .userRequested:
            RMBTSettings.shared.previousTestStatus = RMBTTestStatus.Aborted.rawValue
        case .appBackgrounded:
            RMBTSettings.shared.previousTestStatus = RMBTTestStatus.ErrorBackgrounded.rawValue
        case .errorFetchingTestingParams:
            RMBTSettings.shared.previousTestStatus = RMBTTestStatus.ErrorFetching.rawValue
        case .errorSubmittingTestResult:
            RMBTSettings.shared.previousTestStatus = RMBTTestStatus.ErrorSubmitting.rawValue
        default:
            RMBTSettings.shared.previousTestStatus = RMBTTestStatus.Error.rawValue
        }

        phase = .none
        dead = true

        DispatchQueue.main.async {
            self.delegate?.testRunnerDidCancelTestWithReason(reason)
        }
    }
    
    func cancel() {
        workerQueue.async {
            self.cancel(with: .userRequested)
        }
    }
    
    static func willQoSPerformed() -> Bool {
        // Skip qos
        if !RMBTSettings.shared.qosEnabled {
            return false
        } else if ((RMBTSettings.shared.qosEnabled) && (RMBTSettings.shared.only2Hours)) {
            // Never haven't launched before
            if (RMBTSettings.shared.previousLaunchQoSDate == nil) {
                return true
                // previous launch was 2 hours after
            } else if (fabs(RMBTSettings.shared.previousLaunchQoSDate?.timeIntervalSinceNow ?? 0) > RMBTQosSkipTimeInterval) {
                return true
            } else {
                return false
            }
        }
        return true
    }
    
    func markWorkerAsFinished() -> Bool {
        finishedWorkers += 1
        return finishedWorkers == activeWorkers
    }
    
    private func killTimer() {
        timer?.cancel()
        self.timer = nil
    }
    
    func cleanup() {
        // Stop observing
        connectivityTracker?.stop()
        NotificationCenter.default.removeObserver(self)
        
        self.killTimer()
    }

    private func finishTest() {
        phase = .none
        dead = true

        RMBTSettings.shared.previousTestStatus = RMBTTestStatus.Ended.rawValue

        let historyResult = RMBTHistoryResult(response: ["test_uuid": self.testParams?.testUUID ?? ""])
        DispatchQueue.main.async {
            self.delegate?.testRunnerDidCompleteWithResult(historyResult)
        }
    }

    func submitTestResult(willContinueTest: Bool = true, onSuccess: @escaping () -> Void = { }) {
        if !willContinueTest {
            cleanup() // Stop observing now, test is finished
        }

        workerQueue.async { [weak self] in
            guard let self else { return }

            if !willContinueTest {
                phase = .submittingTestResult
            }

            if (self.dead) { return } // cancelled

            let result = self.resultWithDictionary(self.resultDictionary())
            AbstractBasicRequestBuilder.addBasicRequestValues(result)
            result.clientVersion = self.workersClientVersion

            RMBTControlServer.shared.submitResult(result, endpoint: nil) { [weak self] response in
                self?.workerQueue.async {
                    guard let self else { return }

                    if !willContinueTest {
                        self.finishTest()
                    }
                    onSuccess()
                }
            } error: { [weak self] error in
                self?.workerQueue.async {
                    self?.cancel(with: .errorSubmittingTestResult)
                }
            }
        }
    }

    func submitQoSResult(_ qosResult: [[String : Any]]) {
        cleanup() // Stop observing now, test is finished

        workerQueue.async { [weak self] in
            guard let self else { return }

            let qosResult = qosResultDictionary(from: qosResult)
            let hasQos = (qosResult?.count ?? 0 > 0 && self.testParams?.resultQoSURLString != nil)

            guard hasQos else {
                finishTest()
                return
            }

            let qosResultRequest = QosMeasurementResultRequest(withJSON: qosResult ?? [:])
            AbstractBasicRequestBuilder.addBasicRequestValues(qosResultRequest)
            qosResultRequest.clientVersion = self.workersClientVersion

            RMBTControlServer.shared.submitQOSResult(qosResultRequest, endpoint: testParams?.resultQoSURLString) { [weak self] response in
                self?.workerQueue.async { [weak self] in
                    guard let self else { return }

                    finishTest()
                }
            } error: { [weak self] error in
                self?.workerQueue.async {
                    self?.cancel(with: .errorSubmittingTestResult)
                }
            }
        }
    }

    private func qosResultDictionary(from qosResults: [[String : Any]]) -> [String: Any]? {
        if qosResults.count > 0 {
            return [
                "test_token": testParams?.testToken ?? "",
                "qos_result": qosResults
            ]
        } else {
            return nil
        }
    }
    
    func resultWithDictionary(_ dictionary: [String: Any]) -> SpeedMeasurementResult {
        return SpeedMeasurementResult(withJSON: dictionary)
    }

    func resultDictionary() -> [String: Any] {
        var result = testResult?.resultDictionary() ?? [:]
        
        result["test_token"] = testParams?.testToken
        result["uuid"] = testParams?.testUUID

        // Collect total transfers from all threads
        var sumBytesDownloaded: UInt64 = 0
        var sumBytesUploaded: UInt64 = 0
        
        for w in workers {
            sumBytesDownloaded += w.totalBytesDownloaded
            sumBytesUploaded += w.totalBytesUploaded
        }

        assert(sumBytesDownloaded > 0, "Total bytes <= 0");
        assert(sumBytesUploaded > 0, "Total bytes <= 0");

        let firstWorker = workers[0]
        
        
        result["test_total_bytes_download"] = sumBytesDownloaded
        result["test_total_bytes_upload"] = sumBytesUploaded
        result["test_encryption"] = firstWorker.negotiatedEncryptionString
        result["test_ip_local"] = RMBTValueOrNull(firstWorker.localIp)
        result["test_ip_server"] = RMBTValueOrNull(firstWorker.serverIp)
        
        if let downlinkStartInterfaceInfo = self.downlinkStartInterfaceInfo,
           let downlinkEndInterfaceInfo = self.downlinkEndInterfaceInfo {
            let interfaceBytesResultTestdl = self.interfaceBytesResultDictionary(with:  downlinkStartInterfaceInfo,                                                      endInfo: downlinkEndInterfaceInfo, prefix: "testdl")
            
            interfaceBytesResultTestdl.forEach { item in
                result[item.key] = item.value
            }
        }
        
        if let uplinkStartInterfaceInfo = self.uplinkStartInterfaceInfo,
           let uplinkEndInterfaceInfo = self.uplinkEndInterfaceInfo {
            let interfaceBytesResultTestul = self.interfaceBytesResultDictionary(with:  uplinkStartInterfaceInfo,                                                      endInfo: uplinkEndInterfaceInfo, prefix: "testul")
            
            interfaceBytesResultTestul.forEach { item in
                result[item.key] = item.value
            }
        }
        
        if let startInterfaceInfo = self.startInterfaceInfo,
           let uplinkEndInterfaceInfo = self.uplinkEndInterfaceInfo {
            
            let interfaceBytesResultTest = self.interfaceBytesResultDictionary(with:  startInterfaceInfo,                                                      endInfo: uplinkEndInterfaceInfo, prefix: "test")
            
            interfaceBytesResultTest.forEach { item in
                result[item.key] = item.value
            }
        }

        // Add relative time_(dl/ul)_ns timestamps:
        let startNanos: UInt64 = testResult?.testStartNanos ?? 0

        result["time_dl_ns"] = downlinkTestStartedAtNanos - startNanos
        result["time_ul_ns"] = uplinkTestStartedAtNanos - startNanos
        
        if (qosTestStartedAtNanos > 0) {
            result["time_qos_ns"] = qosTestStartedAtNanos - startNanos
            if (qosTestFinishedAtNanos > qosTestStartedAtNanos) {
                result["test_nsec_qos"] = qosTestFinishedAtNanos - qosTestStartedAtNanos
            } else {
                assert(false)
            }
        }

        return result
    }
    
    private func interfaceBytesResultDictionary(with startInfo: RMBTConnectivityInterfaceInfo, endInfo: RMBTConnectivityInterfaceInfo, prefix: String) -> [String: Any] {
        return [
            String(format:"%@_if_bytes_download", prefix): RMBTConnectivity.countTraffic(.received, between:startInfo, and:endInfo),
            String(format:"%@_if_bytes_upload", prefix): RMBTConnectivity.countTraffic(.sent, between:startInfo, and:endInfo)
        ]
    }
    
    private func startPhase(_ phase: RMBTTestRunnerPhase, withAllWorkers allWorkers: Bool, performingSelector selector: Selector?,
                            expectedDuration duration: TimeInterval, completion completionHandler: EmptyCallback?) {
        ASSERT_ON_WORKER_QUEUE()

        self.phase = phase

        finishedWorkers = 0;
        progressStartedAtNanos = RMBTHelpers.RMBTCurrentNanos()
        progressDurationNanos = UInt64(duration) * NSEC_PER_SEC

        self.killTimer()

        assert(completionHandler == nil || duration > 0)

        if (duration > 0) {
            progressCompletionHandler = completionHandler
            timer = DispatchSource.makeTimerSource()
            timer?.schedule(deadline: .now(), repeating: RMBTTestRunner.RMBTTestRunnerProgressUpdateInterval, leeway: .seconds(50))
            timer?.setEventHandler(handler: { [weak self] in
                guard let self = self else { return }
                let elapsedNanos = RMBTHelpers.RMBTCurrentNanos() - self.progressStartedAtNanos
                
                if (elapsedNanos > self.progressDurationNanos) {
                    // We've reached end of interval...
                    // ..send 1.0 progress one last time..
                    DispatchQueue.main.async {
                        self.delegate?.testRunnerDidUpdateProgress(1.0, in: phase)
                    }
                
                    self.killTimer()

                    // ..and perform completion handler, if any.
                    if (self.progressCompletionHandler != nil) {
                        self.workerQueue.async {
                            self.progressCompletionHandler?()
                            self.progressCompletionHandler = nil
                        }
                    }
                } else {
                    let p = Float(elapsedNanos) / Float(self.progressDurationNanos)
                    assert(p <= 1.0, "Invalid percentage")
                    DispatchQueue.main.async {
                        self.delegate?.testRunnerDidUpdateProgress(p, in: phase)
                    }
                }
            })
            
            timer?.resume()
        }
        
        guard let selector = selector else { return }

        if (allWorkers) {
            activeWorkers = UInt(workers.count)
            workers.forEach { $0.perform(selector)}
        } else {
            activeWorkers = 1
            (workers as NSArray).subarray(with: NSRange(location: 0, length: 1)).forEach({ _ = ($0 as AnyObject).perform(selector) })
        }
    }
    
    // MARK: - App state tracking
    
    @objc func applicationDidSwitchToBackground(_ notification: Notification) {
        Log.logger.error("App backgrounded, aborting \(notification)")
        workerQueue.async {
            self.cancel(with: .appBackgrounded)
        }
    }

    // MARK: - Tracking location
    
    @objc func locationsDidChange(_ notification: Notification) {
        var lastLocation: CLLocation?
        
        guard let locations = notification.userInfo?["locations"] as? [CLLocation] else { return }
        
        for l in locations {
            if (CLLocationCoordinate2DIsValid(l.coordinate)) {
                lastLocation = l
                testResult?.addLocation(l)
                
                Log.logger.error("Location updated to (\(l.coordinate.longitude),\(l.coordinate.latitude),+/- \(l.horizontalAccuracy)m, \(l.timestamp)")
            }
        }

        if let l = lastLocation {
            DispatchQueue.main.async {
                self.delegate?.testRunnerDidDetectLocation(l)
            }
        }
    }
}

extension RMBTTestRunner: RMBTConnectivityTrackerDelegate {
    func connectivityTracker(_ tracker: RMBTConnectivityTracker, didDetect connectivity: RMBTConnectivity) {
        workerQueue.async {
            if (self.testResult?.lastConnectivity() == nil) {
                self.startInterfaceInfo = connectivity.getInterfaceInfo()
            }
            if (self.phase != .none) {
                self.testResult?.addConnectivity(connectivity)
            }
        }
        
        DispatchQueue.main.async {
            self.delegate?.testRunnerDidDetectConnectivity(connectivity)
        }
    }
    
    func connectivityTrackerDidDetectNoConnectivity(_ tracker: RMBTConnectivityTracker) {
        // Ignore for now, let connection time out
    }
    
    func connectivityTracker(_ tracker: RMBTConnectivityTracker, didStopAndDetectIncompatibleConnectivity connectivity: RMBTConnectivity) {
        DispatchQueue.main.async {
            self.delegate?.testRunnerDidDetectConnectivity(connectivity)
        }
      
        workerQueue.async {
            if (self.phase != .none) {
                self.cancel(with: .mixedConnectivity)
            }
        }
    }
}

extension RMBTTestRunner: RMBTTestWorkerDelegate {
    func testWorker(_ worker: RMBTTestWorker, fetchClientVersion clientVersion: String?) {
        self.workersClientVersion = clientVersion
    }
    
    func testWorker(_ worker: RMBTTestWorker, didFinishDownlinkPretestWithChunksCount chunks: UInt) {
        ASSERT_ON_WORKER_QUEUE()
        assert(phase == .`init`, "Invalid state");
        assert(!dead, "Invalid state");

        Log.logger.debug("Thread \(worker.index): finished download pretest (chunks = \(chunks)")
        
        if (!singleThreaded && chunks <= testParams?.pretestMinChunkCountForMultithreading ?? 0) {
            singleThreaded = true
        }
        if (self.markWorkerAsFinished()) {
            if (singleThreaded) {
                Log.logger.debug("Downloaded <= \(String(describing: testParams?.pretestMinChunkCountForMultithreading)) chunks in the pretest, continuing with single thread.")
                
                activeWorkers = (testParams?.threadCount ?? 1) - 1
                finishedWorkers = 0
                
                let threadCount = testParams?.threadCount ?? 1
                for i in 1..<threadCount {
                    workers[Int(i)].stop()
                }
                testResult?.startDownload(with: 1)
            } else {
                testResult?.startDownload(with: testParams?.threadCount ?? 0)
                
                self.startPhase(.latency, withAllWorkers: false, performingSelector: #selector(RMBTTestWorker.startLatencyTest), expectedDuration: 0, completion: nil)
            }
        }
    }
    
    func testWorker(_ worker: RMBTTestWorker, didMeasureLatencyWithServerNanos serverNanos: UInt64, clientNanos: UInt64) {
        ASSERT_ON_WORKER_QUEUE()
        assert(phase == .latency, "Invalid state")
        assert(!dead, "Invalid state")

        Log.logger.debug("Thread \(worker.index): pong (server = \(serverNanos), client = \(clientNanos)")
        
        testResult?.addPingWithServerNanos(serverNanos, clientNanos: clientNanos)

        let duration = Double(RMBTHelpers.RMBTCurrentNanos() - worker.pingStartTestNanos) / Double(NSEC_PER_SEC)
        let durationP: Float = Float(duration / worker.pingTestDuration)
        let pingP = Float(testResult?.pings.count ?? 0) / Float(testParams?.pingCount ?? 1)
        let p = min(durationP, pingP)
        DispatchQueue.main.async {
            self.delegate?.testRunnerDidMeasurePings(self.testResult?.pings ?? [], in: self.phase)
            self.delegate?.testRunnerDidUpdateProgress(p, in: self.phase)
        }
    }
    
    func testWorkerDidFinishLatencyTest(_ worker: RMBTTestWorker) {
        ASSERT_ON_WORKER_QUEUE()
        assert(phase == .latency, "Invalid state")
        assert(!dead, "Invalid state")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.delegate?.testRunnerDidCompleteLatencyPhase()
        }

        if (self.markWorkerAsFinished()) {
            workerQueue.asyncAfter(deadline: .now() + 1.2) {
                self.startPhase(.down, withAllWorkers: true, performingSelector: #selector(RMBTTestWorker.startDownlinkTest), expectedDuration: self.testParams?.testDuration ?? 0, completion: nil)
            }
        }
    }
    
    func testWorker(_ worker: RMBTTestWorker, didStartDownlinkTestAtNanos nanos: UInt64) -> UInt64 {
        ASSERT_ON_WORKER_QUEUE()
        assert(phase == .down, "Invalid state");
        assert(!dead, "Invalid state");

        if (downlinkTestStartedAtNanos == 0) {
            downlinkStartInterfaceInfo = testResult?.lastConnectivity()?.getInterfaceInfo()
            downlinkTestStartedAtNanos = nanos
        }

        Log.logger.debug("Thread \(worker.index): started downlink test with delay\(nanos - downlinkTestStartedAtNanos)")

        return downlinkTestStartedAtNanos
    }
    
    func testWorker(_ worker: RMBTTestWorker, didDownloadLength length: UInt64, atNanos nanos: UInt64) {
        ASSERT_ON_WORKER_QUEUE()
        assert(phase == .down, "Invalid state");
        assert(!dead, "Invalid state");

        let measuredThroughputs = testResult?.addLength(length, atNanos:nanos, for:worker.index)
        if let throughputs = measuredThroughputs {
            DispatchQueue.main.async {
                self.delegate?.testRunnerDidMeasureThroughputs(throughputs, in: .down)
            }
        }
    }
    
    func testWorkerDidFinishDownlinkTest(_ worker: RMBTTestWorker) {
        ASSERT_ON_WORKER_QUEUE()
        assert(phase == .down, "Invalid state");
        assert(!dead, "Invalid state");

        if (self.markWorkerAsFinished()) {
            Log.logger.debug("Downlink test finished")

            downlinkEndInterfaceInfo = testResult?.lastConnectivity()?.getInterfaceInfo()

            let measuredThroughputs = testResult?.flush()

            testResult?.totalDownloadHistory.log()

            if let throughputs = (measuredThroughputs) {
                DispatchQueue.main.async {
                    self.delegate?.testRunnerDidMeasureThroughputs(throughputs, in: .down)
                }
            }
            
            startPhase(.initUp, withAllWorkers: true, performingSelector: #selector(RMBTTestWorker.startUplinkPretest), expectedDuration: testParams?.pretestDuration ?? 0, completion: nil)
        }
    }
    
    func testWorker(_ worker: RMBTTestWorker, didFinishUplinkPretestWithChunkCount chunks: UInt) {
        ASSERT_ON_WORKER_QUEUE()
        assert(phase == .initUp, "Invalid state");
        assert(!dead, "Invalid state");

        Log.logger.debug("Thread \(worker.index): finished uplink pretest (chunks = \(chunks)")
        if (self.markWorkerAsFinished()) {
            Log.logger.debug("Uplink pretest finished")
            testResult?.startUpload()
            self.startPhase(.up, withAllWorkers: true, performingSelector: #selector(RMBTTestWorker.startUplinkTest), expectedDuration: testParams?.testDuration ?? 0, completion: nil)
        }
    }
    
    func testWorker(_ worker: RMBTTestWorker, didStartUplinkTestAtNanos nanos: UInt64) -> UInt64 {
        ASSERT_ON_WORKER_QUEUE()
        assert(phase == .up, "Invalid state");
        assert(!dead, "Invalid state");

        var delay: UInt64
        if (uplinkTestStartedAtNanos == 0) {
            uplinkTestStartedAtNanos = nanos
            delay = 0
            uplinkStartInterfaceInfo = testResult?.lastConnectivity()?.getInterfaceInfo()
        } else {
            delay = nanos - uplinkTestStartedAtNanos
        }

        Log.logger.debug("Thread \(worker.index): started uplink test with delay \(delay)")

        return delay
    }
    
    func testWorker(_ worker: RMBTTestWorker, didUploadLength length: UInt64, atNanos nanos: UInt64) {
        ASSERT_ON_WORKER_QUEUE()
        assert(phase == .up, "Invalid state");
        assert(!dead, "Invalid state");

        let measuredThroughputs = testResult?.addLength(length, atNanos: nanos, for: worker.index)
        
        if let throughputs = measuredThroughputs {
            DispatchQueue.main.async {
                self.delegate?.testRunnerDidMeasureThroughputs(throughputs, in: .up)
            }
        }
    }
    
    func testWorkerDidFinishUplinkTest(_ worker: RMBTTestWorker) {
        ASSERT_ON_WORKER_QUEUE()
        assert(phase == .up, "Invalid state");
        assert(!dead, "Invalid state");

        if (self.markWorkerAsFinished()) {
            self.killTimer()
            
            uplinkEndInterfaceInfo = testResult?.lastConnectivity()?.getInterfaceInfo()

            let measuredThroughputs = testResult?.flush()
            Log.logger.debug("Uplink test finished.")
            
            testResult?.totalUploadHistory.log()

            if let throughputs = measuredThroughputs {
                DispatchQueue.main.async {
                    self.delegate?.testRunnerDidMeasureThroughputs(throughputs, in: .up)
                }
            }
            if (!RMBTTestRunner.willQoSPerformed()) {
                // Just for logs
                if (!RMBTSettings.shared.qosEnabled) {
                    Log.logger.debug("Skipping QoS per user setting")
                } else if ((RMBTSettings.shared.qosEnabled) && (RMBTSettings.shared.only2Hours) && (fabs(RMBTSettings.shared.previousLaunchQoSDate?.timeIntervalSinceNow ?? 0) > RMBTTestRunner.RMBTQosSkipTimeInterval)) {
                    Log.logger.debug("Skipping QoS per user setting. Previous qos was launched less 2 hours")
                }

                submitTestResult(willContinueTest: false)
            } else {
                submitTestResult { [weak self] in
                    self?.startQoS()
                }
            }
        }
    }
    
    func testWorkerDidStop(_ worker: RMBTTestWorker) {
        ASSERT_ON_WORKER_QUEUE()
        assert(phase == .`init`, "Invalid state")
        assert(!dead, "Invalid state")

        Log.logger.debug("Thread \(worker.index): stopped")
        
        if let index = workers.firstIndex(of: worker) {
            workers.remove(at: index)
        }
        
        if (self.markWorkerAsFinished()) {
            // We stopped all but one workers because of slow connection. Proceed to latency with single worker.
            self.startPhase(.latency, withAllWorkers: false, performingSelector: #selector(RMBTTestWorker.startLatencyTest), expectedDuration: 0, completion: nil)
        }
    }
    
    func testWorkerDidFail(_ worker: RMBTTestWorker) {
        ASSERT_ON_WORKER_QUEUE()
        assert(!dead, "Invalid state");
        self.cancel(with: .noConnection)
    }
    
    
}

extension RMBTTestRunner: RMBTQoSTestRunnerDelegate {
    func qosRunnerDidFail() {
        self.qosRunnerDidComplete(with: [])
    }
    
    func qosRunnerDidStart(with testGroups: [RMBTQoSTestGroup], tests: [RMBTQoSTest]) {
        Log.logger.debug("Started QoS with groups: \(testGroups)")
        qosTestStartedAtNanos = RMBTHelpers.RMBTCurrentNanos()
        DispatchQueue.main.async {
            self.delegate?.testRunnerQoSDidStartWithGroups(testGroups, tests)
        }
    }
    
    func qosRunnerDidUpdateProgress(_ progress: Float, in group: RMBTQoSTestGroup, totalProgress: Float) {
        Log.logger.debug("Group: \(group): Progress \(progress): Total \(totalProgress)")
        DispatchQueue.main.async {
            self.delegate?.testRunnerDidUpdateProgress(totalProgress, in: .qos)
            self.delegate?.testRunnerQoSGroup(group, didUpdateProgress: progress)
        }
    }
    
    func qosRunnerDidUpdateProgress(_ testProgress: Float, test: RMBTQoSTest, in group: RMBTQoSTestGroup) {
        DispatchQueue.main.async {
            self.delegate?.testRunnerQoSGroup(group, didUpdateProgress: testProgress, in: test)
        }
    }
    
    func qosRunnerDidComplete(with results: [[String : Any]]) {
        Log.logger.debug("QoS finished.")
        qosTestFinishedAtNanos = RMBTHelpers.RMBTCurrentNanos()
        self.submitQoSResult(results)
    }
}
