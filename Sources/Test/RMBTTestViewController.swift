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
}

final class RMBTTestViewController: RMBTBaseTestViewController {
    private let actionsSegue = "actions_segue"
    private var locationTracker: RMBTLocationTracker?
    
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
    
    var ping: String? {
        didSet {
            self.currentView.ping = ping
        }
    }
    
    var down: String? {
        didSet {
            self.currentView.down = down
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
    
    var speedValues: [RMBTThroughput] = [] {
        didSet {
            self.currentView.clearSpeedGraph()
            for t in speedValues {
                let kbps = Int(t.kilobitsPerSecond())
                let l = RMBTSpeedLogValue(Double(kbps))
                self.currentView.addSpeed(CGFloat(l), at: TimeInterval(t.endNanos / NSEC_PER_SEC))
            }
        }
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
    
    var alertView: UIAlertView?

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
        self.currentView.networkTypeImage = self.networkTypeImage
        self.currentView.technology = self.technology
        self.currentView.status = self.status
        self.currentView.progress = self.progress
        self.currentView.speed = self.speed
        self.currentView.ping = self.ping
        self.currentView.down = self.down
        self.currentView.up = self.up
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        updateLoopModeInfo()
        
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        self.isQOSState = false

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
        UIApplication.shared.isIdleTimerDisabled = true
        self.loopModeInfo?.increment()
        
        self.state = .test
        self.speedValues = []
        self.speedGauge = 0.0
        
        self.currentView.clearValues()
        self.currentView.currentTest = self.loopModeInfo?.current ?? 0
        self.currentView.totalTests = self.loopModeInfo?.total ?? 0
        
        if let info = self.loopModeInfo {
            super.startTest(withExtraParams: info.params)
        } else {
            super.startTest(withExtraParams: nil)
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
        if ((alertView) != nil) { alertView?.dismiss(withClickedButtonIndex: -1, animated: false) }
        
        alertView = UIAlertView.bk_alertView(withTitle: title, message: message)
        
        if ((cancelButtonTitle) != nil) { alertView?.bk_setCancelButton(withTitle: cancelButtonTitle, handler: cancelHandler) }
        if ((otherButtonTitle) != nil) { alertView?.bk_addButton(withTitle: otherButtonTitle, handler: otherHandler) }
        alertView?.show()
    }
    
    func updateSpeedLabel(for phase: RMBTTestRunnerPhase, withSpeed kbps: UInt32, isFinal: Bool) {
        self.isShowSpeedSuffix = false
        if phase == .down {
            self.down = RMBTSpeedMbpsStringWithSuffix(kbps, false)
        } else {
            self.up = RMBTSpeedMbpsStringWithSuffix(kbps, false)
        }
        self.speed = kbps
    }
    
    func hideAlert() {
        if ((alertView) != nil) {
            alertView?.dismiss(withClickedButtonIndex: -1, animated: true)
            alertView = nil
        }
    }

    @IBAction func closeButtonClick(_ sender: Any) {
        self.tapped()
    }
    
    func tapped() {
        self.displayAlert(with: RMBTAppTitle() ?? "",
                          message: NSLocalizedString("Do you really want to abort the running test?", comment: "Abort test alert title"),
                          cancelButtonTitle: NSLocalizedString("Abort Test", comment: "Abort test alert button"),
                          otherButtonTitle: NSLocalizedString("Continue", comment: "Abort test alert button")) { [weak self] in
            self?.cancelTest()
        } otherHandler: { }
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if (identifier == "embed_qos_progress" && RMBTSettings.shared.skipQoS) {
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
        locationTracker?.stop()
        locationTracker = nil
        lastTestFirstGoodLocation = nil
        startDate = nil
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.RMBTLocationTracker, object: nil)
        loopModeWaitingViewController.minutesValue = ""
        loopModeWaitingViewController.minutesPercents = 0.0
        loopModeWaitingViewController.distanceValue = ""
        loopModeWaitingViewController.distancePercents = 0.0
    }
    
    private func startNextTestIfNeeded() {
        if movementReached || durationReached {
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
        // Start monitoring location changes
        NotificationCenter.default.addObserver(self, selector: #selector(locationsDidChange(_:)), name: NSNotification.Name.RMBTLocationTracker, object: nil)
        locationTracker = RMBTLocationTracker()
        locationTracker?.startIfAuthorized()
        
        self.startDate = Date()
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
            UIApplication.shared.isIdleTimerDisabled = false
            self.performSegue(withIdentifier: actionsSegue, sender: self)
        }
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
        self.networkName = RMBTValueOrString(connectivity.networkName, "Unknown") as? String
        self.networkType = RMBTValueOrString(connectivity.networkTypeDescription, "n/a") as? String ?? ""
        
        if (connectivity.networkType == .cellular) {
            self.networkTypeImage = UIImage(named: "mobile_icon_full")?.withRenderingMode(.alwaysTemplate)
        } else if (connectivity.networkType == .wiFi) {
            self.networkTypeImage = UIImage(named: "wifi_icon")?.withRenderingMode(.alwaysTemplate)
        } else {
            self.networkTypeImage = nil
        }

        self.technology = connectivity.networkTypeDescription
    }
    
    func onTestUpdatedLocation(_ location: CLLocation!) { }
    
    func onTestUpdatedServerName(_ name: String!) { }
    
    func onTestUpdatedStatus(_ status: String!) {
        self.status = status
    }
    
    func onTestUpdatedTotalProgress(_ percentage: UInt, gaugeProgress gaugePercentage: UInt) {
        self.progress = percentage
        self.progressGauge = Double(gaugePercentage) / 100.0
    }
    
    func onTestStartedPhase(_ phase: RMBTTestRunnerPhase) {
        self.phase = phase
        self.speedValues = []
        if (phase == .qoS) {
            self.isQOSState = true
            self.isInfoCollapsed = true
        }
    }
    
    func onTestFinishedPhase(_ phase: RMBTTestRunnerPhase) { }
    
    func onTestMeasuredLatency(_ nanos: UInt64) {
        self.currentView.ping = RMBTMillisecondsStringWithNanos(nanos, false)
    }
    
    func onTestMeasuredTroughputs(_ throughputs: [Any]!, in phase: RMBTTestRunnerPhase) {
        var kbps = 0
        var l: Double = 0.0

        self.speedValues += throughputs as? [RMBTThroughput] ?? []
        for t in throughputs as? [RMBTThroughput] ?? [] {
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
    
    func onTestStartedQoS(withGroups groups: [Any]!) {
        self.qosProgressViewController.testGroups = groups as? [RMBTQoSTestGroup]
        self.qosCounterText = self.qosProgressViewController.progressString()
        self.state = .qos
        self.currentView.showQoSUI(true)
    }
    
    func onTestUpdatedProgress(_ progress: Float, inQoSGroup group: RMBTQoSTestGroup!) {
        self.qosProgressViewController.updateProgress(progress, for: group)
        self.qosCounterText = self.qosProgressViewController.progressString()
    }
    
    func onTestCompleted(with result: RMBTHistoryResult!, qos qosPerformed: Bool) {
        self.qosCounterText = self.qosProgressViewController.progressString()
        self.hideAlert()
        if self.loopModeInfo != nil {
            self.goToWaitingState()
        } else {
            UIApplication.shared.isIdleTimerDisabled = false
            self.delegate?.testViewController(self, didFinishWithTest: result)
        }
    }
    
    func onTestCancelled(with reason: RMBTTestRunnerCancelReason) {
        guard loopModeInfo == nil || reason == .userRequested else {
            self.goToWaitingState()
            return
        }
        switch(reason) {
        case .userRequested:
            self.dismiss(animated: true, completion: nil)
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
        @unknown default: break
        }
    }
}

private extension String {
    static let nextTest = NSLocalizedString("loop_mode_next_test", comment: "")
}

