//
//  RMBTTestViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 17.09.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import Foundation
import UIKit
import CoreLocation

@objc protocol RMBTTestViewControllerDelegate: AnyObject {
    func testViewController(_ controller: RMBTTestViewController, didFinishWithTest result: RMBTHistoryResult?)
    func testViewController(_ controller: RMBTTestViewController, didFinishLoopWithTest result: RMBTHistoryResult?)
    func runTestInLoopMode()
}

final class RMBTTestViewController: RMBTBaseTestViewController {
    private let actionsSegue = "actions_segue"
    private var locationTracker = RMBTLocationTracker()
    
    enum State {
        case test
        case qos
        case waiting
    }
    
    var state: State = .test
    
    var loopModeInfo: RMBTLoopInfo? {
        didSet {
            if isViewLoaded {
                updateLoopModeInfo()
            }
        }
    }
    
    var networkName: String? {
        didSet {
            self.currentView.networkName = networkName
        }
    }
    
    var networkType: String? {
        didSet {
            self.currentView.networkType = networkType
        }
    }
    
    var networkTypeEnum: RMBTNetworkType? {
        didSet {
            self.currentView.networkTypeEnum = networkTypeEnum
        }
    }
    
    var networkTypeTechnology: RMBTNetworkTypeConstants.NetworkType? {
        didSet {
            self.currentView.networkTypeTechnology = networkTypeTechnology
        }
    }
    
    var networkTypeImage: UIImage? {
        didSet {
            self.currentView.networkTypeImage = networkTypeImage
        }
    }
    
    var technology: String? {
        didSet {
            self.currentView.technology = technology
        }
    }
    
    var status: String? {
        didSet {
            self.currentView.status = status
        }
    }
    
    var progress: UInt = 0 {
        didSet {
            self.currentView.progress = progress
        }
    }
    
    var speed: UInt32 = 0 {
        didSet {
            self.currentView.speed = speed
        }
    }
    
    var pingColor: UIColor = UIColor.white {
        didSet {
            self.currentView.pingColor = pingColor
        }
    }
    
    var ping: String? {
        didSet {
            self.currentView.ping = ping
        }
    }
    
    var downColor: UIColor = UIColor.white {
        didSet {
            self.currentView.downColor = downColor
        }
    }
    
    var down: String? {
        didSet {
            self.currentView.down = down
        }
    }
    
    var upColor: UIColor = UIColor.white {
        didSet {
            self.currentView.upColor = upColor
        }
    }
    
    var up: String? {
        didSet {
            self.currentView.up = up
        }
    }
    
    var phase: RMBTTestRunnerPhase = .none {
        didSet {
            self.currentView.phase = phase
        }
    }
    
    var isShowSpeedSuffix: Bool = false {
        didSet {
            self.currentView.isShowSpeedSuffix = isShowSpeedSuffix
        }
    }
    
    var qosCounterText: String? {
        didSet {
            self.currentView.qosCounterText = qosCounterText
        }
    }
    
    private lazy var tickDelayForGraph: TimeInterval = {
        let minValue = 1.0 / 24.0
        if TimeInterval(RMBTConfig.RMBT_TEST_SAMPLING_RESOLUTION_MS) / TimeInterval(NSEC_PER_SEC) < minValue {
            return minValue
        } else {
            return TimeInterval(RMBTConfig.RMBT_TEST_SAMPLING_RESOLUTION_MS) / TimeInterval(NSEC_PER_SEC)
        }
    }()
    
    var delayForGraph: TimeInterval = 0.5
    var delayForPingGraph: TimeInterval = 0.0
    var startSpeedPhaseDate: Date = Date()

    weak var graphTickTimer: Timer? {
        didSet {
            if oldValue?.isValid == true {
                oldValue?.invalidate()
            }
        }
    }
    
    var speedValues: [RMBTThroughput] = [] {
        didSet {
            self.currentView.clearSpeedGraph()
            
            // Make draw with delay. Filter periods that not include to duration minus delay
            let speedValues = speedValues.filter({
                return TimeInterval($0.endNanos) / TimeInterval(NSEC_PER_SEC) + delayForGraph < Date().timeIntervalSince(startSpeedPhaseDate)
            })
            
            for t in speedValues {
                let kbps = Int(t.kilobitsPerSecond())
                let l = RMBTSpeedLogValue(Double(kbps))
                self.currentView.addSpeed(CGFloat(l), at: TimeInterval(t.endNanos) / TimeInterval(NSEC_PER_SEC))
            }
        }
    }
    
    var pingValues: [RMBTHistoryPing] = [] {
        didSet {
            self.currentView.clearPingGraph()
            
            let currentTime = RMBTHelpers.RMBTCurrentNanos()
            
            // Make draw with delay. Filter periods that not include to duration minus delay
            var pingValues = self.pingValues.filter({
                let absoluteTime = testStartTime() + UInt64($0.timeElapsed)
                return (absoluteTime + UInt64((TimeInterval(NSEC_PER_SEC) * delayForPingGraph)) < currentTime)
            })
            if let lastPing = pingValues.last {
                let absoluteTime = testStartTime() + UInt64(lastPing.timeElapsed)
                if currentTime - absoluteTime > UInt64(tickDelayForGraph * TimeInterval(NSEC_PER_SEC)) {
                    let timeElapsed = currentTime - UInt64(delayForPingGraph * TimeInterval(NSEC_PER_SEC)) - testStartTime()
                    pingValues.append(RMBTHistoryPing(pingMs: lastPing.pingMs, timeElapsed: Int(timeElapsed)))
                }
            }
            
            for ping in pingValues {
                self.currentView.addPing(ping.pingMs, at: TimeInterval(ping.timeElapsed))
            }
        }
    }
    
    func addPingValue(_ ping: RMBTHistoryPing) {
        let currentTime = RMBTHelpers.RMBTCurrentNanos()
        
        if let lastPing = pingValues.last {
            let absoluteTime = testStartTime() + UInt64(lastPing.timeElapsed)
            if currentTime - absoluteTime > UInt64(tickDelayForGraph * TimeInterval(NSEC_PER_MSEC)) {
                var timeElapsed = currentTime - testStartTime()
                if ping.timeElapsed < timeElapsed {
                    timeElapsed = UInt64(ping.timeElapsed - 1)
                }
                pingValues.append(RMBTHistoryPing(pingMs: lastPing.pingMs, timeElapsed: Int(timeElapsed)))
            }
        }
        
        pingValues.append(ping)
    }

    var speedGauge: Double = 0 {
        didSet {
            self.currentView.speedGauge = speedGauge
        }
    }
    
    var progressGauge: Double = 0 {
        didSet {
            self.currentView.progressGauge = progressGauge
        }
    }
    
    var alertView: UIAlertController?

    private lazy var qosProgressViewController: RMBTQoSProgressViewController = {
        let vc = UIStoryboard(name: "TestStoryboard", bundle: nil).instantiateViewController(withIdentifier: "RMBTQoSProgressViewController")
        if let view = vc.view {
            self.currentView.setQosView(view)
        }
        return vc as! RMBTQoSProgressViewController
    }()
    
    private lazy var loopModeWaitingViewController: RMBTLoopModeWaitingViewController = {
        let vc = UIStoryboard(name: "TestStoryboard", bundle: nil).instantiateViewController(withIdentifier: "RMBTLoopModeWaitingViewController")
        if let view = vc.view {
            self.currentView.setWaitingView(view)
        }
        return vc as! RMBTLoopModeWaitingViewController
    }()
    
    @objc weak var delegate: RMBTTestViewControllerDelegate?
    
    // This will hide the network name label in case of cellular connection
    @objc var roaming = false
    
    var isInfoCollapsed = true {
        didSet {
            self.currentView.isInfoCollapsed = isInfoCollapsed
        }
    }
    
    var isQOSState = false {
        didSet {
            self.currentView.isQOSState = isQOSState
        }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }
    
    private lazy var landscapeView: RMBTTestLandscapeView = {
        let view = RMBTTestLandscapeView.view()
        self.initView(view)
        return view
    }()
    
    private lazy var portraitView: RMBTTestPortraitView = {
        let view = RMBTTestPortraitView.view()
        self.initView(view)
        return view
    }()
    
    private var currentView: RMBTTestPortraitView {
        let size = UIApplication.shared.windowSize
        if size.width > size.height {
            return self.landscapeView
        } else {
            return self.portraitView
        }
    }
    
    func updateLoopModeInfo() {
        self.currentView.isLoopMode = loopModeInfo != nil
        self.currentView.currentTest = loopModeInfo?.current ?? 0
        self.currentView.totalTests = loopModeInfo?.total ?? 0
    }
    
    func initView(_ view: RMBTTestPortraitView) {
        view.onCloseHandler = { [weak self] in
            self?.tapped()
        }
    }
    
    private func updateOrientation(to size: CGSize) {
        let newView: UIView
        if size.width > size.height {
            newView = self.landscapeView
        } else {
            newView = self.portraitView
        }
        
        guard let superview = self.view.superview else {
            self.view = newView
            newView.bounds.size = size
            return
        }
        newView.frame = self.view.frame
        UIView.transition(with: superview, duration: 0.3, options: [.transitionCrossDissolve]) {
            self.view = newView
            newView.bounds.size = size
        } completion: { _ in
            self.updateStates()
            self.currentView.startAnimation()
        }
    }
    
    func updateStates() {
        self.currentView.isLoopMode = self.loopModeInfo != nil
        self.currentView.networkName = self.networkName
        self.currentView.networkType = self.networkType
        self.currentView.networkTypeEnum = self.networkTypeEnum
        self.currentView.networkTypeTechnology = self.networkTypeTechnology
        self.currentView.networkTypeImage = self.networkTypeImage
        self.currentView.technology = self.technology
        self.currentView.status = self.status
        self.currentView.progress = self.progress
        self.currentView.speed = self.speed
        self.currentView.ping = self.ping
        self.currentView.down = self.down
        self.currentView.up = self.up
        self.currentView.pingColor = self.pingColor
        self.currentView.downColor = self.downColor
        self.currentView.upColor = self.upColor
        self.currentView.isInfoCollapsed = self.isInfoCollapsed
        self.currentView.isQOSState = self.isQOSState
        self.currentView.currentTest = self.loopModeInfo?.current ?? 0
        self.currentView.totalTests = self.loopModeInfo?.total ?? 0
        self.currentView.phase = self.phase
        self.currentView.isShowSpeedSuffix = self.isShowSpeedSuffix
        self.currentView.qosCounterText = self.qosCounterText
        self.currentView.setQosView(self.qosProgressViewController.view)
        self.currentView.setWaitingView(self.loopModeWaitingViewController.view)
        self.currentView.speedGauge = self.speedGauge
        self.currentView.progressGauge = self.progressGauge
        
        // Update graph
        let speedValues = self.speedValues
        self.speedValues = []
        self.speedValues = speedValues
        
        // Update ping graph
        let pingValues = self.pingValues
        self.pingValues = []
        self.pingValues = pingValues
        
        switch state {
        case .test:
            self.currentView.showQoSUI(false)
            self.currentView.loopModeWaitingView.isHidden = true
        case .qos:
            self.currentView.showQoSUI(true)
            self.currentView.loopModeWaitingView.isHidden = true
        case .waiting:
            self.currentView.showWaitingUI()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        updateLoopModeInfo()
        
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        // Only clear connectivity and location labels once at start to avoid blinking during test restart
        self.networkName = ""
        self.networkType = "-"
        
        self.updateOrientation(to: UIApplication.shared.windowSize)
        
        self.view.layoutSubviews()
        self.startTest()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.currentView.updateDetailInfoView()
        self.currentView.startAnimation()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        self.updateOrientation(to: size)
    }
    
    @objc private func didBecomeActive(_ sender: Any) {
        currentView.startAnimation()
    }
    
    @objc func startTest() {
        let activeMeasurementId = RMBTSettings.shared.activeMeasurementId
        guard activeMeasurementId == nil || (loopModeInfo?.loopUuid != nil && activeMeasurementId == loopModeInfo?.loopUuid) else {
            return
        }
        RMBTSettings.shared.activeMeasurementId = loopModeInfo != nil ? loopModeInfo!.loopUuid : ""
        self.startDate = Date()
        self.lastTestFirstGoodLocation = self.locationTracker.location
        self.loopModeInfo?.increment()
        
        self.state = .test
        self.speedValues = []
        self.speedGauge = 0.0
        self.pingValues = []
        
        self.currentView.clearValues()
        self.currentView.currentTest = self.loopModeInfo?.current ?? 0
        self.currentView.totalTests = self.loopModeInfo?.total ?? 0
        
        self.isQOSState = false
        
        if let info = self.loopModeInfo {
            _ = self.locationTracker.startIfAuthorized()
            // Start monitoring location changes
            NotificationCenter.default.addObserver(self, selector: #selector(locationsDidChange(_:)), name: NSNotification.Name.RMBTLocationTracker, object: nil)
            super.startTest(with: info.params)
        } else {
            super.startTest(with: nil)
        }
    }
    
    // MARK: - Footer
    
    @objc (displayText:forLabel:) func display(text: String, for label: UILabel) {
        label.text = text
    }
    
    func displayAlert(with title: String,
                      message: String,
                      cancelButtonTitle: String? = nil,
                      otherButtonTitle: String? = nil,
                      cancelHandler: @escaping RMBTBlock,
                      otherHandler: @escaping RMBTBlock) {
        let block = { [weak self] in
            self?.alertView = UIAlertController.presentAlert(title: title, text: message, cancelTitle: cancelButtonTitle, otherTitle: otherButtonTitle, cancelAction: { _ in
                cancelHandler()
            }, otherAction: { _ in
                otherHandler()
            })
        }
        
        if (alertView != nil) {
            alertView?.dismiss(animated: true, completion: {
                block()
            })
        } else {
            block()
        }
    }
    
    func updateSpeedLabel(for phase: RMBTTestRunnerPhase, withSpeed kbps: UInt32, isFinal: Bool) {
        self.isShowSpeedSuffix = false
        if phase == .down {
            self.downColor = .byResultClass(RMBTHelpers.RMBTDownClassification(with: Double(kbps)))
            self.down = RMBTSpeedMbpsString(Double(kbps), withMbps: true)
        } else {
            self.upColor = .byResultClass(RMBTHelpers.RMBTUpClassification(with: Double(kbps)))
            self.up = RMBTSpeedMbpsString(Double(kbps), withMbps: true)
        }
        self.speed = kbps
    }
    
    func hideAlert() {
        if ((alertView) != nil) {
            alertView?.dismiss(animated: true, completion: nil)
            alertView = nil
        }
    }

    @IBAction func closeButtonClick(_ sender: Any) {
        self.tapped()
    }
    
    func tapped() {
        self.displayAlert(with: RMBTHelpers.RMBTAppTitle(),
                          message: NSLocalizedString("Do you really want to abort the running test?", comment: "Abort test alert title"),
                          cancelButtonTitle: NSLocalizedString("Abort Test", comment: "Abort test alert button"),
                          otherButtonTitle: NSLocalizedString("Continue", comment: "Abort test alert button")) { [weak self] in
            guard let self = self else { return }
            self.cancelTest()
            guard let _ = self.loopModeInfo else { return }
            self.performSegue(withIdentifier: self.actionsSegue, sender: self)
            
        } otherHandler: { }
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if (identifier == "embed_qos_progress" && !RMBTSettings.shared.qosEnabled) {
            return false
        }
        return true
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == actionsSegue,
           let vc = segue.destination as? RMBTLoopModeCompleteViewController {
            vc.onResultsHandler = { [weak self] in
                guard let self = self else { return }
                self.delegate?.testViewController(self, didFinishLoopWithTest: nil)
            }
            vc.onRunAgainHandler = { [weak self] in
                self?.dismiss(animated: true, completion: nil)
                self?.delegate?.runTestInLoopMode()
            }
        }
    }
    
    var movementReached: Bool = false
    var durationReached: Bool = false
    
    var lastTestFirstGoodLocation: CLLocation?
    var startDate: Date?
    
    var timer: Timer?
    
    private func cleanup () {
        movementReached = false
        durationReached = false
        if timer?.isValid == true {
            timer?.invalidate()
            timer = nil
        }
        locationTracker.stop()
        lastTestFirstGoodLocation = nil
        startDate = nil
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.RMBTLocationTracker, object: nil)
        loopModeWaitingViewController.minutesValue = ""
        loopModeWaitingViewController.minutesPercents = 0.0
        loopModeWaitingViewController.distanceValue = ""
        loopModeWaitingViewController.distancePercents = 0.0
    }
    
    private func startNextTestIfNeeded() {
        if (movementReached || durationReached) && self.state == .waiting {
            cleanup()
            startTest()
        }
    }
    
    @objc private func tick() {
        guard let startDate = startDate else { return }
        let time = Date().timeIntervalSince(startDate)
        let endDate = Date(timeInterval: Double((self.loopModeInfo?.waitMinutes ?? 0)) * 60, since: startDate)
        let totalTime = endDate.timeIntervalSince(startDate)
        let percents = time / totalTime
        let restTime = totalTime - time
        let minutes = Int(restTime / 60)
        let seconds = Int(restTime) % 60
        loopModeWaitingViewController.minutesValue = String(format: "%02d:%02d", minutes, seconds)
        loopModeWaitingViewController.minutesPercents = percents
        
        if time >= Double((self.loopModeInfo?.waitMinutes ?? 0)) * 60 {
            timer?.invalidate()
            durationReached = true
            startNextTestIfNeeded()
        }
    }
    
    private func startWaitingNextTest() {
        timer = Timer.scheduledTimer(timeInterval: 0.3, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }
    
    @objc private func locationsDidChange(_ notification: Notification) {
        guard let l = (notification.userInfo?["locations"] as? [CLLocation])?.last,
              CLLocationCoordinate2DIsValid(l.coordinate)
        else {
            return
        }

        if (lastTestFirstGoodLocation == nil) {
            lastTestFirstGoodLocation = l
        }

        updateLocation(l)
    }

    private func updateLocation(_ location: CLLocation) {
        var d: CLLocationDistance = 0
        if let l = lastTestFirstGoodLocation {
            d = location.distance(from: l)
        }
        
        // TODO: Update distance in waiting view
        let percents = d / Double(self.loopModeInfo?.waitMeters ?? 0)
        loopModeWaitingViewController.distanceValue = String(format: "%0.1f", Double(self.loopModeInfo?.waitMeters ?? 0) - d)
        loopModeWaitingViewController.distancePercents = percents
        movementReached = (d >= Double(self.loopModeInfo?.waitMeters ?? 0))
        if movementReached {
            startNextTestIfNeeded()
        }
    }

    private func goToWaitingState() {
        guard let loopModeInfo = loopModeInfo else { return }

        if !loopModeInfo.isFinished {
            self.state = .waiting
            self.currentView.showWaitingUI()
            self.status = .nextTest
            startWaitingNextTest()
        } else {
            self.finishTest()
            self.performSegue(withIdentifier: actionsSegue, sender: self)
        }
    }
    
    func clearDataAfterTest() {
        self.graphTickTimer = nil
        self.qosProgressViewController.tests = []
        self.qosProgressViewController.testGroups = []
    }
}

extension RMBTTestViewController: UIViewControllerTransitioningDelegate {
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let v = RMBTVerticalTransitionController()
        v.reverse = true
        return v
    }
    
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return RMBTVerticalTransitionController()
    }
}

extension RMBTTestViewController: RMBTBaseTestViewControllerSubclass {
    func onTestUpdatedConnectivity(_ connectivity: RMBTConnectivity) {
        self.networkName = connectivity.networkName
        self.networkType = RMBTValueOrString(connectivity.networkTypeDescription, "n/a") as? String ?? ""
        
        if (connectivity.networkType == .cellular) {
            self.networkTypeImage = UIImage(named: "mobile_icon_full")?.withRenderingMode(.alwaysTemplate)
        } else if (connectivity.networkType == .wifi) {
            self.networkTypeImage = UIImage(named: "wifi_icon")?.withRenderingMode(.alwaysTemplate)
        } else {
            self.networkTypeImage = nil
        }
        
        self.networkTypeEnum = connectivity.networkType
        self.networkTypeTechnology = connectivity.networkTypeTechnology

        self.technology = connectivity.networkTypeDescription
    }
    
    func onTestUpdatedLocation(_ location: CLLocation) { }
    
    func onTestUpdatedServerName(_ name: String) { }
    
    func onTestUpdatedStatus(_ status: String) {
        self.status = status
    }
    
    func onTestUpdatedTotalProgress(_ percentage: UInt, gaugeProgress gaugePercentage: UInt) {
        self.progress = percentage
        self.progressGauge = Double(gaugePercentage) / 100.0
    }
    
    @objc func updateGraph(_ timer: Timer) {
        let speedValues = self.speedValues
        self.speedValues = []
        self.speedValues = speedValues
    }
    
    @objc func updatePingGraph(_ timer: Timer) {
        let pingValues = self.pingValues
        self.pingValues = []
        self.pingValues = pingValues
    }
    
    func onTestStartedPhase(_ phase: RMBTTestRunnerPhase) {
        self.phase = phase
        self.speedValues = []
        self.pingValues = []
        self.graphTickTimer = nil
        
        if (phase == .qos) {
            self.isQOSState = true
            self.isInfoCollapsed = true
        }
    }
    
    func onTestFinishedPhase(_ phase: RMBTTestRunnerPhase) { }
    
    func onTestMeasuredLatency(_ nanos: UInt64) {
        self.pingColor = .byResultClass(RMBTHelpers.RMBTPingClassification(with: Int64(nanos)))
        self.currentView.ping = RMBTHelpers.RMBTMillisecondsString(with: Int64(nanos), withMS: true)
    }
    
    func onTestMeasuredPings(_ pings: [Ping], in phase: RMBTTestRunnerPhase) {
        if phase == .latency && self.pingValues.count == 0 {
            graphTickTimer = Timer.scheduledTimer(timeInterval: tickDelayForGraph, target: self, selector: #selector(updatePingGraph(_:)), userInfo: nil, repeats: true)
        }
        
        if let lastPing = self.pingValues.last {
            let filteredPings = pings.filter({ $0.relativeTimestampNanos > lastPing.timeElapsed })
            
            filteredPings.forEach { ping in
                let historyPing = RMBTHistoryPing(pingMs: Double(ping.clientNanos) * 1.0e-6, timeElapsed: Int(ping.relativeTimestampNanos))
                self.addPingValue(historyPing)
            }
        } else {
            self.pingValues = pings.map({ RMBTHistoryPing(pingMs: Double($0.clientNanos) * 1.0e-6, timeElapsed: Int($0.relativeTimestampNanos))})
        }
    }
    
    func onTestCompletedLantencPhase() {
        currentView.pingGraphView.isHidden = false
    }

    func onTestMeasuredTroughputs(_ throughputs: [RMBTThroughput], in phase: RMBTTestRunnerPhase) {
        var kbps = 0
        var l: Double = 0.0

        if (phase == .down || phase == .up) && self.speedValues.count == 0 {
            startSpeedPhaseDate = Date()
            graphTickTimer = Timer.scheduledTimer(timeInterval: tickDelayForGraph, target: self, selector: #selector(updateGraph(_:)), userInfo: nil, repeats: true)
        }
        
        self.speedValues += throughputs
        for t in throughputs {
            kbps = Int(t.kilobitsPerSecond())
            l = RMBTSpeedLogValue(Double(kbps))
        }

        if (throughputs.count > 0) {
            // Use last values for momentary display (gauge and label)
            self.speedGauge = l
            self.updateSpeedLabel(for: phase, withSpeed: UInt32(kbps), isFinal: false)
        }
    }
    
    func onTestMeasuredDownloadSpeed(_ kbps: UInt32) {
        self.speedGauge = 0
        // Speed gauge set to 0, but leave the chart until we have measurements for the upload
        // [self.speedGraphView clear];
        self.updateSpeedLabel(for: .down, withSpeed: kbps, isFinal: true)
    }
    
    func onTestMeasuredUploadSpeed(_ kbps: UInt32) {
        self.updateSpeedLabel(for: .up, withSpeed: kbps, isFinal: true)
    }
    
    func onTestStartedQoS(with groups: [RMBTQoSTestGroup], and tests: [RMBTQoSTest]) {
        self.qosProgressViewController.tests = tests
        self.qosProgressViewController.testGroups = groups
        self.qosCounterText = self.qosProgressViewController.progressString()
        self.state = .qos
        self.currentView.showQoSUI(true)
    }
    
    func onTestUpdatedProgress(_ progress: Float, in group: RMBTQoSTestGroup) {
        self.qosProgressViewController.update(progress, for: group)
        self.qosCounterText = self.qosProgressViewController.progressString()
    }
    
    func onTestUpdatedProgress(_ testProgress: Float, for test: RMBTQoSTest, in group: RMBTQoSTestGroup) {
        self.qosCounterText = self.qosProgressViewController.progressString()
    }
    
    func onTestCompleted(with result: RMBTHistoryResult!, qos qosPerformed: Bool) {
        self.qosCounterText = self.qosProgressViewController.progressString()
        self.hideAlert()
        self.clearDataAfterTest()
        if self.loopModeInfo != nil {
            self.goToWaitingState()
        } else {
            self.finishTest()
            self.delegate?.testViewController(self, didFinishWithTest: result)
        }
    }
    
    func onTestCancelled(with reason: RMBTTestRunnerCancelReason) {
        self.clearDataAfterTest()
        guard loopModeInfo == nil || reason == .userRequested else {
            self.goToWaitingState()
            return
        }
        self.finishTest()
        switch(reason) {
        case .userRequested:
            if loopModeInfo == nil {
                self.dismiss(animated: true, completion: nil)
            }
        case .mixedConnectivity:
            Log.logger.debug("Test cancelled because of mixed connectivity")
            self.startTest()
        case .noConnection, .errorFetchingTestingParams:
            var message: String = ""
            if (reason == .noConnection) {
                Log.logger.debug("Test cancelled because of connection error")
                message = NSLocalizedString("The connection to the test server was lost. Test aborted.", comment: "Alert view message");
            } else {
                Log.logger.debug("Test cancelled failing to fetch test params")
                message = NSLocalizedString("Couldn't connect to test server.", comment: "Alert view message");
            }
            
            self.displayAlert(with: NSLocalizedString("Connection Error", comment: "Alert view title"),
                              message: message,
                              cancelButtonTitle: NSLocalizedString("Cancel", comment: "Alert view button"),
                              otherButtonTitle: NSLocalizedString("Try Again", comment: "Alert view button")) { [weak self] in
                self?.dismiss(animated: true, completion: nil)
            } otherHandler: { [weak self] in
                self?.startTest()
            }

        case .errorSubmittingTestResult:
            Log.logger.debug("Test cancelled failing to submit test results")
            self.displayAlert(with: NSLocalizedString("Error", comment: "Alert view title"),
                              message: NSLocalizedString("Test was completed, but the results couldn't be submitted to the test server.", comment: "Alert view message"),
                              cancelButtonTitle: NSLocalizedString("Dismiss", comment: "Alert view button"),
                              otherButtonTitle: nil) { [weak self] in
                self?.dismiss(animated: true, completion: nil)
            } otherHandler: { }
        case .appBackgrounded:
            Log.logger.debug("Test cancelled because app backgrounded")
            self.displayAlert(with: NSLocalizedString("Test aborted", comment: "Alert view title"),
                              message: NSLocalizedString("Test was aborted because the app went into background. Tests can only be performed while the app is running in foreground.", comment: "Alert view message"),
                              cancelButtonTitle: NSLocalizedString("Close", comment: "Alert view button"),
                              otherButtonTitle: NSLocalizedString("Repeat Test", comment: "Alert view button")) { [weak self] in
                self?.dismiss(animated: true, completion: nil)
            } otherHandler: { [weak self] in
                self?.startTest()
            }
        }
    }
}

private extension String {
    static let nextTest = NSLocalizedString("loop_mode_next_test", comment: "")
}

