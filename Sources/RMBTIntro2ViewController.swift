//
//  RMBTIntro2ViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 26.07.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import BlocksKit

class RMBTIntro2ViewController: UIViewController {
    
    private let showTosSegue = "show_tos"
    private let showSettingsSegue = "show_settings_segue"
    
    
    private var isRoaming: Bool = false
    private var isLoopMode: Bool {
        return RMBTSettings.shared.loopMode
    }
    
    private lazy var landscapeView: RMBTIntroPortraitView = {
        let view = RMBTIntroLandscapeView.view()
        self.initView(view)
        return view
    }()
    
    private lazy var portraitView: RMBTIntroPortraitView = {
        let view = RMBTIntroPortraitView.view()
        self.initView(view)
        return view
    }()
    
    private var currentView: RMBTIntroPortraitView {
        let size = UIApplication.shared.windowSize
        if size.width > size.height {
            return self.landscapeView
        } else {
            return self.portraitView
        }
    }
    
    func initView(_ view: RMBTIntroPortraitView) {
        view.ipV4Tapped = { [weak self] color in
            guard let self = self else { return }
            self.ipv4TapHandler(color)
        }
        view.ipV6Tapped = { [weak self] color in
            guard let self = self else { return }
            self.ipv6TapHandler(color)
        }
        view.locationTapped = { [weak self] color in
            guard let self = self else { return }
            self.locationTapHandler(color)
        }
        view.loopModeHandler = { [weak self] isOn in
            guard let self = self else { return }
            self.loopModeSwitched(isOn)
        }
        view.startButtonHandler = {
            self.startTest()
        }
        view.settingsButtonHandler = {
            self.performSegue(withIdentifier: self.showSettingsSegue, sender: self)
        }
    }
    
    private let connectivityService = ConnectivityService()
    
    private lazy var connectivityTracker: RMBTConnectivityTracker = {
        return RMBTConnectivityTracker(delegate: self, stopOnMixed: false)
    }()
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        guard let connectivity = connectivity else { return .default }
        if connectivity.networkType == .cellular || connectivity.networkType == .wiFi {
            return .lightContent
        } else {
            if #available(iOS 13.0, *) {
                return .darkContent
            } else {
                return .default
            }
        }
    }
    
    private var connectivityInfo: ConnectivityInfo? {
        didSet {
            updateConnectivityInfo()
        }
    }
    private var connectivity: RMBTConnectivity? {
        didSet {
            updateRoamingStatus()
            updateStates()
        }
    }
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.navigationController?.tabBarItem.title = " "
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.navigationController?.tabBarItem.title = " "
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        self.updateOrientation(to: size)
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
            self.currentView.updateLoopModeUI()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.view.backgroundColor = UIColor.networkAvailable

        self.modalPresentationCapturesStatusBarAppearance = true
        
        self.tabBarController?.tabBar.isTranslucent = false
        self.navigationController?.setNavigationBarHidden(true, animated: false)
        
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        let tos = RMBTTOS.shared
        // If user hasn't agreed to new TOS version, show TOS modally
        if (!tos.isCurrentVersionAccepted) {
            Log.logger.debug("Current TOS version \(tos.currentVersion) > last accepted version \(tos.lastAcceptedVersion), showing dialog")
            self.performSegue(withIdentifier: showTosSegue, sender: self)
        }
        
        currentView.updateLoopModeUI()
        self.updateOrientation(to: UIApplication.shared.windowSize)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.updateStates()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        currentView.updateLoopModeUI()
        self.connectivityTracker.start()
        RMBTLocationTracker.shared().start {
            self.connectivityTracker.forceUpdate()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        connectivityTracker.stop()
    }
    
    @objc private func didBecomeActive(_ sender: Any) {
        if self.connectivity != nil {
            currentView.startAnimation()
        } else {
            currentView.stopAnimation()
        }
    }
    
    private func ipv4TapHandler(_ tintColor: UIColor) {
        guard let connectivityInfo = self.connectivityInfo else { return }
        let popupInfo = RMBTPopupInfo(with: .ipv4Icon, tintColor: tintColor, style: .line, values: [
            RMBTPopupInfo.Value(title: .localIP, value: connectivityInfo.ipv4.internalIp ?? ""),
            RMBTPopupInfo.Value(title: .externalIP, value: connectivityInfo.ipv4.externalIp ?? ""),
        ])
        RMBTPopupViewController.present(with: popupInfo, in: self)
    }
    
    private func ipv6TapHandler(_ tintColor: UIColor) {
        guard let connectivityInfo = self.connectivityInfo else { return }
        let popupInfo = RMBTPopupInfo(with: .ipv6Icon, tintColor: tintColor, style: .list, values: [
            RMBTPopupInfo.Value(title: .localIP, value: connectivityInfo.ipv6.internalIp ?? ""),
            RMBTPopupInfo.Value(title: .externalIP, value: connectivityInfo.ipv6.externalIp ?? ""),
        ])
        RMBTPopupViewController.present(with: popupInfo, in: self)
    }
    
    private func locationPopupInfo(with location: CLLocation, tintColor: UIColor) -> RMBTPopupInfo {
        let altitude = "\(Int(location.altitude)) m"
        let ageSeconds = Int(Date().timeIntervalSince1970 - location.timestamp.timeIntervalSince1970)
        let age = "< \(ageSeconds) s"
        let speedKilometers = abs(Int(location.speed * 3.6))
        let speed = "\(speedKilometers) km/h"
        let horizontalAccuracy = "+/-\(Int(location.horizontalAccuracy)) m"
        
        let locationString = location.dms
        let popupInfo = RMBTPopupInfo(with: .locationIcon, tintColor: tintColor, style: .list, values: [
            RMBTPopupInfo.Value(title: .locationPosition, value: locationString),
            RMBTPopupInfo.Value(title: .locationAccuracy, value: horizontalAccuracy),
            RMBTPopupInfo.Value(title: .locationAge, value: age),
            RMBTPopupInfo.Value(title: .locationAltitude, value: altitude),
            RMBTPopupInfo.Value(title: .locationSpeed, value: speed),
        ])
        return popupInfo
    }
    
    private func locationTapHandler(_ tintColor: UIColor) {
        guard let location = RMBTLocationTracker.shared().location else { return }
        
        let popupInfo = self.locationPopupInfo(with: location, tintColor: tintColor)
        RMBTLocationPopupViewController.presentLocation(with: popupInfo, in: self) { [weak self] vc in
            vc.info = self?.locationPopupInfo(with: location, tintColor: tintColor)
        }
    }
    
    private func loopModeSwitched(_ isOn: Bool) {
        if isOn {
            self.performSegue(withIdentifier: "show_loop_mode_confirmation", sender: self)
        } else {
            RMBTSettings.shared.loopMode = isOn
            RMBTSettings.shared.expertMode = RMBTSettings.shared.loopMode
        }
        currentView.updateLoopModeUI()
    }
    
    @IBAction func acceptLoopModeConfirmation(_ segue: UIStoryboardSegue) {
        RMBTSettings.shared.loopMode = true
        RMBTSettings.shared.expertMode = RMBTSettings.shared.loopMode
        currentView.updateLoopModeUI()
        segue.source.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func declineLoopModeConfirmation(_ segue: UIStoryboardSegue) {
        RMBTSettings.shared.loopMode = false
        RMBTSettings.shared.expertMode = RMBTSettings.shared.loopMode
        currentView.updateLoopModeUI()
        segue.source.dismiss(animated: true, completion: nil)
    }
    
    private func startTest() {
        if isLoopMode {
            let settings = RMBTSettings.shared

            // Ask user how many tests to run
            let title = NSLocalizedString("Number of tests", comment: "Loop mode alert title")
            let message = String(format: NSLocalizedString("You are about to start tests in loop mode. The distance is set to %@ meters. The waiting time between tests is %@ minutes.", comment: "Loop mode alert message"), NSNumber(value: settings.loopModeEveryMeters), NSNumber(value: settings.loopModeEveryMinutes))
            
            let av = UIAlertView.bk_alertView(withTitle: title, message: message)
            av?.alertViewStyle = .plainTextInput
            let tf = av?.textField(at: 0)
            tf?.text = String(format: "%@", NSNumber(value: settings.loopModeLastCount))
            tf?.keyboardType = .numberPad
          
            av?.bk_addButton(withTitle: NSLocalizedString("Start tests", comment: "Loop mode alert button"), handler: {
                guard let text = tf?.text,
                      let i = UInt(text)
                else { return }
                
                let max = settings.debugUnlocked ? Int32.max : RMBT_TEST_LOOPMODE_MAX_COUNT
                
                if (i < RMBT_TEST_LOOPMODE_MIN_COUNT || i > max) {
                    UIAlertView.bk_show(withTitle: "Invalid number of tests",
                                        message: String(format: "Please enter a value between %@ and %@", NSNumber(value: RMBT_TEST_LOOPMODE_MIN_COUNT), NSNumber(value: max)),
                                        cancelButtonTitle: "OK",
                                        otherButtonTitles: []) { [weak self] _, _ in
                        guard let self = self else { return }
                        self.startTest()
                    }
                } else {
                    settings.loopModeLastCount = i

                    let info = RMBTLoopInfo(with: settings.loopModeEveryMeters,
                                            minutes: settings.loopModeEveryMinutes,
                                            total: i)
                    self.startTest(with: info)
                }
            })
            av?.bk_setCancelButton(withTitle: NSLocalizedString("Cancel", comment: "Button title"), handler: {})
            av?.show()
        } else {
            self.startTest(with: nil)
        }
    }
    
    private func startTest(with loopModeInfo: RMBTLoopInfo?) {
        // Before transitioning to test view controller, we want to wait for user to allow/deny location services first
        RMBTLocationTracker.shared().start {
            if let info = loopModeInfo {
                guard let loopVC = UIStoryboard(name: "TestStoryboard", bundle: nil).instantiateViewController(withIdentifier: "loop_test_vc") as? RMBTLoopModeTestViewController else {
                    fatalError()
                }
                loopVC.info = info
                loopVC.modalPresentationStyle = .fullScreen
                loopVC.transitioningDelegate = self
                let navController = UINavigationController(rootViewController: loopVC)
                navController.modalPresentationStyle = .fullScreen
                navController.transitioningDelegate = self
                
                self.present(navController, animated: true, completion: nil)
            } else {
                guard let testVC = UIStoryboard(name: "TestStoryboard", bundle: nil).instantiateViewController(withIdentifier: "test_vc") as? RMBTTestViewController else {
                    fatalError()
                }
                testVC.modalPresentationStyle = .fullScreen
                testVC.transitioningDelegate = self
                testVC.delegate = self
                testVC.roaming = self.isRoaming
                
                self.present(testVC, animated: true, completion: nil)
            }
        }
    }
    
    private func updateRoamingStatus() {
        guard let connectivity = connectivity,
              connectivity.networkType == .cellular
        else { return }
        
        guard let location = RMBTLocationTracker.shared()?.location else { return }
        
        var params = connectivity.testResultDictionary() ?? [:]
        let locationParams = location.paramsDictionary() ?? [:]
        for param in locationParams {
            params[param.key] = param.value
        }
        
        RMBTControlServer.shared.getRoamingStatus(with: params) { [] response in
            guard let response = response as? Bool else { return }
            self.isRoaming = response
            self.currentView.isHiddenNetworkName = response
        }
    }
    
    private func updateConnectivityInfo() {
        guard let connectivity = self.connectivityInfo else {
            currentView.ipV4TintColor = .ipNotAvailable
            currentView.ipV6TintColor = .ipNotAvailable
            currentView.locationTintColor = .ipNotAvailable
            return
        }
        
        if (connectivity.ipv4.internalIp != nil) {
            if (connectivity.ipv4.externalIp != nil) && (connectivity.ipv4.externalIp == connectivity.ipv4.internalIp) {
                currentView.ipV4TintColor = .ipAvailable
            } else {
                currentView.ipV4TintColor = .ipSemiAvailable
            }
        } else {
            currentView.ipV4TintColor = .ipNotAvailable
        }
        
        if (connectivity.ipv6.internalIp != nil) {
            if (connectivity.ipv6.externalIp != nil) && (connectivity.ipv6.externalIp == connectivity.ipv6.internalIp) {
                currentView.ipV6TintColor = .ipAvailable
            } else {
                currentView.ipV6TintColor = .ipSemiAvailable
            }
        } else {
            currentView.ipV6TintColor = .ipNotAvailable
        }
        
        currentView.locationTintColor = CLLocationManager.authorizationStatus() != .denied ? .ipAvailable : .ipNotAvailable
        
        if let type = self.connectivity?.networkTypeDescription,
           let technology = RMBTNetworkTypeConstants.cellularCodeDescriptionDictionary[type] {
            currentView.networkMobileClassImage = technology.technologyIcon
        } else {
            currentView.networkMobileClassImage = nil
        }
    }
    
    private var networkName: String? {
        if connectivity?.networkType == .cellular {
            return connectivity?.networkName
        }
        return connectivity?.networkName ?? .unknown
    }
    
    private func updateStates() {
        guard let connectivity = self.connectivity else {
            self.connectivityInfo = nil
            self.noConnectionState()
            return
        }
        
        
        self.connectivityService.checkConnectivity { [weak self] connectivityInfo in
            DispatchQueue.main.async {
                self?.connectivityInfo = connectivityInfo
            }
        }
        
        currentView.networkAvailable(connectivity.networkType, networkName: self.networkName, networkDescription: connectivity.networkTypeDescription)

        if (connectivity.networkType == .wiFi) || (connectivity.networkType == .cellular) {
            self.setNeedsStatusBarAppearanceUpdate()
            self.navigationController?.setNeedsStatusBarAppearanceUpdate()
        }
    }
    
    private func noConnectionState() {
        self.connectivityInfo = nil
        currentView.networkNotAvailable()
        self.setNeedsStatusBarAppearanceUpdate()
        self.navigationController?.setNeedsStatusBarAppearanceUpdate()
    }

}

extension RMBTIntro2ViewController: RMBTConnectivityTrackerDelegate {
    func connectivityTracker(_ tracker: RMBTConnectivityTracker!, didDetect connectivity: RMBTConnectivity!) {
        DispatchQueue.main.async {
            self.connectivity = connectivity
        }
    }
    
    func connectivityTrackerDidDetectNoConnectivity(_ tracker: RMBTConnectivityTracker!) {
        DispatchQueue.main.async {
            self.connectivity = nil
            self.noConnectionState()
        }
    }
}

extension RMBTIntro2ViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return RMBTVerticalTransitionController()
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let v = RMBTVerticalTransitionController()
        v.reverse = true
        return v
    }
}

extension RMBTIntro2ViewController: RMBTTestViewControllerDelegate {
    func testViewController(_ controller: RMBTTestViewController, didFinishWithTest result: RMBTHistoryResult?) {
        defer {
            controller.dismiss(animated: true, completion: nil)
        }
        
        guard let result = result else { return }
        
        self.tabBarController?.selectedIndex = 1 // TODO: avoid hardcoding tab index
        
        guard let navController = self.tabBarController?.selectedViewController as? UINavigationController,
              let historyVC = navController.viewControllers.first as? RMBTHistoryIndex2ViewController else { return }
              
        historyVC.displayTestResult(result)
    }
}

private extension String {
    static let noNetworkAvailable = NSLocalizedString("No network connection available", comment: "");
    static let unknown = NSLocalizedString("Unknown", comment: "");
    
    static let localIP = NSLocalizedString("private_ip_address", comment: "");
    static let externalIP = NSLocalizedString("public_ip_address", comment: "");
    
    static let locationTitle = NSLocalizedString("location_dialog_label_title", comment: "");
    static let locationPosition = NSLocalizedString("location_dialog_label_position", comment: "");
    static let locationAccuracy = NSLocalizedString("location_dialog_label_accuracy", comment: "");
    static let locationAge = NSLocalizedString("location_dialog_label_age", comment: "");
    static let locationAltitude = NSLocalizedString("location_dialog_label_altitude", comment: "");
    static let locationSpeed = NSLocalizedString("location_dialog_label_speed", comment: "");
    static let loopModeLabel = NSLocalizedString("title_loop_mode", comment: "")
}

private extension UIImage {
    static let noNetworkAvailable = UIImage(named: "no_internet_icon")
    static let wifiAvailable = UIImage(named: "wifi_icon")
    
    static let ipv4Icon = UIImage(named: "ip_v4")
    static let ipv6Icon = UIImage(named: "ip_v6")
    static let locationIcon = UIImage(named: "location_icon")
}

private extension UIColor {
    static let noNetworkAvailable = UIColor(red: 242.0 / 255, green: 243.0 / 255, blue: 245.0 / 255, alpha: 1.0)
    static let networkAvailable = UIColor(red: 0.0 / 255, green: 113.0 / 255, blue: 215.0 / 255, alpha: 1.0)
    
    static let noNetworkTypeAvailable = UIColor(red: 66.0 / 255, green: 66.0 / 255, blue: 66.0 / 255, alpha: 0.4)
    static let networkTypeAvailable = UIColor(red: 1, green: 1, blue: 1, alpha: 0.4)
    
    static let noNetworkLogoAvailable = UIColor(red: 66.0 / 255, green: 66.0 / 255, blue: 66.0 / 255, alpha: 1.0)
    static let networkLogoAvailable = UIColor(red: 1, green: 1, blue: 1, alpha: 1.0)
    
    static let ipNotAvailable = UIColor(red: 245.0 / 255.0, green: 0.0 / 255.0, blue: 28.0/255.0, alpha: 1.0)
    static let ipSemiAvailable = UIColor(red: 255.0 / 255.0, green: 186.0 / 255.0, blue: 0, alpha: 1.0)
    static let ipAvailable = UIColor(red: 89.0 / 255.0, green: 178.0 / 255.0, blue: 0, alpha: 1.0)
}