//
//  RMBTIntro2ViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 26.07.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import BlocksKit
import CoreLocation

class RMBTIntroViewController: UIViewController {
    private let showTosSegue = "show_tos"
    private let showSettingsSegue = "show_settings_segue"
    private let showLoopModeSettingsSegue = "show_loop_mode_settings_segue"
    
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
    
    private weak var currentPopupViewController: RMBTPopupViewController?
    
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
        if connectivity.networkType == .cellular || connectivity.networkType == .wifi {
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
        
        currentView.updateLoopModeUI()
        self.updateOrientation(to: UIApplication.shared.windowSize)
        
        NotificationCenter.default.addObserver(self, selector: #selector(forceUpdateNetwork(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        RMBTControlServer.shared.updateWithCurrentSettings { [weak self] in
            guard let self = self else { return }
            
            let tos = RMBTTOS.shared
            // If user hasn't agreed to new TOS version, show TOS modally
            if (!tos.isCurrentVersionAccepted(with: RMBTControlServer.shared.termsAndConditions)) {
                Log.logger.debug("Current TOS version \(RMBTControlServer.shared.termsAndConditions.version) > last accepted version \(tos.lastAcceptedVersion), showing dialog")
                self.performSegue(withIdentifier: self.showTosSegue, sender: self)
            }
        } error: {_ in }
    }
    
    @objc func forceUpdateNetwork(_ sender: Any) {
        RMBTLocationTracker.shared.startAfterDeterminingAuthorizationStatus({
            self.connectivityTracker.forceUpdate()
        })
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.updateStates()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        currentView.updateLoopModeUI()
        self.connectivityTracker.start()
        RMBTLocationTracker.shared.startAfterDeterminingAuthorizationStatus({
            self.connectivityTracker.forceUpdate()
        })
        RMBTSettings.shared.activeMeasurementId = nil
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
    
    private func ipV4PopupInfo(with connectivityInfo: ConnectivityInfo, tintColor: UIColor) -> RMBTPopupInfo {
        if connectivityInfo.ipv4.externalIp == nil {
            let popupInfo = RMBTPopupInfo(with: .ipv4Icon, tintColor: tintColor, style: .list, values: [ ])
            return popupInfo
        }
        let popupInfo = RMBTPopupInfo(with: .ipv4Icon, tintColor: tintColor, style: .line, values: [
            RMBTPopupInfo.Value(title: .localIP, value: connectivityInfo.ipv4.internalIp ?? ""),
            RMBTPopupInfo.Value(title: .externalIP, value: connectivityInfo.ipv4.externalIp ?? ""),
        ])
        return popupInfo
    }
    
    private func ipv4TapHandler(_ tintColor: UIColor) {
        guard let connectivityInfo = self.connectivityInfo else { return }
        let popupInfo = self.ipV4PopupInfo(with: connectivityInfo, tintColor: tintColor)
        currentPopupViewController = RMBTPopupViewController.present(with: popupInfo, in: self)
        currentPopupViewController?.popupType = .ipv4
    }
    
    private func ipV6PopupInfo(with connectivityInfo: ConnectivityInfo, tintColor: UIColor) -> RMBTPopupInfo {
        if connectivityInfo.ipv6.externalIp == nil {
            let popupInfo = RMBTPopupInfo(with: .ipv6Icon, tintColor: tintColor, style: .list, values: [ ])
            return popupInfo
        }
        let popupInfo = RMBTPopupInfo(with: .ipv6Icon, tintColor: tintColor, style: .list, values: [
            RMBTPopupInfo.Value(title: .localIP, value: connectivityInfo.ipv6.internalIp ?? ""),
            RMBTPopupInfo.Value(title: .externalIP, value: connectivityInfo.ipv6.externalIp ?? ""),
        ])
        return popupInfo
    }
    
    private func ipv6TapHandler(_ tintColor: UIColor) {
        guard let connectivityInfo = self.connectivityInfo else { return }
        let popupInfo = self.ipV6PopupInfo(with: connectivityInfo, tintColor: tintColor)
        currentPopupViewController = RMBTPopupViewController.present(with: popupInfo, in: self)
        currentPopupViewController?.popupType = .ipv6
    }
    
    private func locationPopupInfo(with location: CLLocation, tintColor: UIColor) -> RMBTPopupInfo {
        let altitude = "\(Int(location.altitude)) m"
        let timestamp = abs(Date().timeIntervalSince(location.timestamp))
        let age: String
        if timestamp < 1 {
            age = "< 1 s"
        } else {
            age = "\(Int(timestamp)) s"
        }
        
        var speedKilometers: Int = 0
        if location.speed >= 0 {
            speedKilometers = Int(location.speed * 3.6)
        }
            
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
        guard let location = RMBTLocationTracker.shared.location else { return }
        
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
            self.performSegue(withIdentifier: showLoopModeSettingsSegue, sender: self)
        } else {
            self.startTest(with: nil)
        }
    }
    
    private func startTest(with loopModeInfo: RMBTLoopInfo?) {
        // Before transitioning to test view controller, we want to wait for user to allow/deny location services first
        RMBTLocationTracker.shared.startAfterDeterminingAuthorizationStatus({
            guard
                let navController = UIStoryboard(name: "TestStoryboard", bundle: nil).instantiateViewController(withIdentifier: "RMBTTestNavigationControllerID") as? UINavigationController,
                let testVC = navController.topViewController as? RMBTTestViewController else {
                fatalError()
            }
            let activeMeasurementId = RMBTSettings.shared.activeMeasurementId
            guard activeMeasurementId == nil || (loopModeInfo?.loopUuid != nil && activeMeasurementId == loopModeInfo?.loopUuid) else {
                return
            }
            testVC.loopModeInfo = loopModeInfo
            navController.modalPresentationStyle = .fullScreen
            navController.transitioningDelegate = self
            testVC.delegate = self
            testVC.roaming = self.isRoaming
            
            self.present(navController, animated: true, completion: nil)
        })
    }
    
    private func updateRoamingStatus() {
        guard let connectivity = connectivity,
              connectivity.networkType == .cellular
        else { return }
        
        guard let location = RMBTLocationTracker.shared.location else { return }
        
        var params = connectivity.testResultDictionary()
        let locationParams = location.paramsDictionary()
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
        
        
        if (connectivity.ipv4.internalIp == nil) || (connectivity.ipv4.externalIp == nil) {
            currentView.ipV4TintColor = .ipNotAvailable
        } else {
            if (connectivity.ipv4.externalIp != nil) && (connectivity.ipv4.externalIp == connectivity.ipv4.internalIp) {
                currentView.ipV4TintColor = .ipAvailable
            } else {
                currentView.ipV4TintColor = .ipSemiAvailable
            }
        }
        
        if (connectivity.ipv6.internalIp == nil) || (connectivity.ipv6.externalIp == nil) {
            currentView.ipV6TintColor = .ipNotAvailable
        } else {
            if (connectivity.ipv6.externalIp != nil) && (connectivity.ipv6.externalIp == connectivity.ipv6.internalIp) {
                currentView.ipV6TintColor = .ipAvailable
            } else {
                currentView.ipV6TintColor = .ipSemiAvailable
            }
        }
        
        currentView.locationTintColor = !RMBTLocationTracker.shared.isLocationDenied ? .ipAvailable : .ipNotAvailable

        if let type = self.connectivity?.networkTypeDescription,
           let technology = RMBTNetworkTypeConstants.cellularCodeDescriptionDictionary[type] {
            currentView.networkMobileClassImage = technology.technologyIcon
        } else {
            currentView.networkMobileClassImage = nil
        }
        
        if let popup = self.currentPopupViewController {
            switch popup.popupType {
            case .ipv4:
                let tintColor = currentView.ipV4TintColor ?? UIColor.ipAvailable
                let popupInfo = self.ipV4PopupInfo(with: connectivity, tintColor: tintColor)
                popup.info = popupInfo
            case .ipv6:
                let tintColor = currentView.ipV6TintColor ?? UIColor.ipAvailable
                let popupInfo = self.ipV6PopupInfo(with: connectivity, tintColor: tintColor)
                popup.info = popupInfo
            case .location: break
            }
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

        if (connectivity.networkType == .wifi) || (connectivity.networkType == .cellular) {
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

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == showLoopModeSettingsSegue,
           let navigationController = segue.destination as? UINavigationController,
           let vc = navigationController.topViewController as? RMBTLoopModeSettingsViewController {
            vc.loopModeHandler = { [weak self] loopModeInfo in
                self?.startTest(with: loopModeInfo)
            }
        } else if segue.identifier == showSettingsSegue,
          let navigationController = segue.destination as? UINavigationController,
          let vc = navigationController.topViewController as? RMBTSettingsViewController {
            vc.delegate = self
        }
    }
}

extension RMBTIntroViewController: RMBTSettingsViewControllerDelegate {
    func settingsDidChanged(in viewController: RMBTSettingsViewController) {
        currentView.updateLoopModeUI()
    }
}

extension RMBTIntroViewController: RMBTConnectivityTrackerDelegate {
    func connectivityTracker(_ tracker: RMBTConnectivityTracker, didDetect connectivity: RMBTConnectivity) {
        DispatchQueue.main.async {
            self.connectivity = connectivity
        }
    }
    
    func connectivityTrackerDidDetectNoConnectivity(_ tracker: RMBTConnectivityTracker) {
        DispatchQueue.main.async {
            self.connectivity = nil
            self.noConnectionState()
        }
    }
}

extension RMBTIntroViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return RMBTVerticalTransitionController()
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let v = RMBTVerticalTransitionController()
        v.reverse = true
        return v
    }
}

extension RMBTIntroViewController: RMBTTestViewControllerDelegate {
    func runTestInLoopMode() {
        self.performSegue(withIdentifier: showLoopModeSettingsSegue, sender: self)
    }
    
    func testViewController(_ controller: RMBTTestViewController, didFinishLoopWithTest result: RMBTHistoryResult?) {
        defer {
            controller.dismiss(animated: true, completion: nil)
        }
        
        self.tabBarController?.selectedIndex = 1
    }
    
    func testViewController(_ controller: RMBTTestViewController, didFinishWithTest result: RMBTHistoryResult?) {
        defer {
            controller.dismiss(animated: true, completion: nil)
        }
        
        guard let result = result else { return }
        
        self.tabBarController?.selectedIndex = 1 // TODO: avoid hardcoding tab index
        
        guard let navController = self.tabBarController?.selectedViewController as? UINavigationController,
              let historyVC = navController.viewControllers.first as? RMBTHistoryIndexViewController else { return }
              
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
