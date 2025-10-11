//
//  RMBTConnectivityTracker.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 21.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import CoreTelephony

@objc protocol RMBTConnectivityTrackerDelegate: AnyObject {
    func connectivityTracker(_ tracker: RMBTConnectivityTracker, didDetect connectivity: RMBTConnectivity)
    
    func connectivityTrackerDidDetectNoConnectivity(_ tracker: RMBTConnectivityTracker)
    
    @objc optional func connectivityTracker(_ tracker: RMBTConnectivityTracker, didStopAndDetectIncompatibleConnectivity connectivity: RMBTConnectivity)
}



@objc class RMBTConnectivityTracker: NSObject {
    // According to http://www.objc.io/issue-5/iOS7-hidden-gems-and-workarounds.html one should
    // keep a reference to CTTelephonyNetworkInfo live if we want to receive radio changed notifications (?)
    static let sharedNetworkInfo = CTTelephonyNetworkInfo()
    
    private weak var delegate: RMBTConnectivityTrackerDelegate?
    private var queue = DispatchQueue(label: "at.rtr.rmbt.connectivitytracker")
    private var lastRadioAccessTechnology: Any?
    private var lastConnectivity: RMBTConnectivity?
    private var stopOnMixed: Bool = false
    private var started: Bool = false
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc init(delegate: RMBTConnectivityTrackerDelegate, stopOnMixed: Bool) {
        self.stopOnMixed = stopOnMixed
        self.delegate = delegate
    }
    
    @objc func start() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.started = true
            self.lastRadioAccessTechnology = nil

            // Re-Register for notifications
            NotificationCenter.default.removeObserver(self)
            
            NotificationCenter.default.addObserver(self, selector: #selector(self.appWillEnterForeground(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
            
            NetworkReachability.shared.addReachabilityCallback { [weak self] status in
                self?.reachabilityDidChange(to: status)
            }
            
            NotificationCenter.default.addObserver(self, selector: #selector(self.radioDidChange(_:)), name: NSNotification.Name.CTServiceRadioAccessTechnologyDidChange, object: nil)
            
            self.reachabilityDidChange(to: NetworkReachability.shared.status)
        }
    }
    
    @objc func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.removeObserver(self)
            self.started = false
        }
    }
    
    @objc func forceUpdate() {
        //    if (_lastConnectivity == nil) { return; }
        queue.async {
    //        NSAssert(_lastConnectivity, @"Connectivity should be known by now");
            self.reachabilityDidChange(to: NetworkReachability.shared.status)
            guard let connectivity = self.lastConnectivity else { return }
            self.delegate?.connectivityTracker(self, didDetect: connectivity)
        }
    }
    
    @objc func appWillEnterForeground(_ notification: Notification) {
        queue.async {
            // Restart various observartions and force update (if already started)
            if self.started { self.start() }
        }
    }
    
    @objc func radioDidChange(_ notification: Notification) {
        queue.async { [weak self] in
            guard let self = self else { return }
            // Note:Sometimes iOS delivers multiple notification w/o radio technology actually changing
            if (notification.object as? NSObject) == (self.lastRadioAccessTechnology as? NSObject) { return }
            self.lastRadioAccessTechnology = notification.object
            self.reachabilityDidChange(to: NetworkReachability.shared.status)
        }
    }
    
    func reachabilityDidChange(to status: NetworkReachability.NetworkReachabilityStatus) {
        let networkType: RMBTNetworkType
        switch status {
        case .notReachability, .unknown:
            networkType = .none
        case .wifi:
            networkType = .wifi
        case .mobile:
            networkType = .cellular
        default:
            // No assert here because simulator often returns unknown connectivity status
            Log.logger.debug("Unknown reachability status \(status)")
            return
        }

        if (networkType == .none) {
            Log.logger.debug("No connectivity detected.")
            self.lastConnectivity = nil
            delegate?.connectivityTrackerDidDetectNoConnectivity(self)
            return
        }

        let connectivity = RMBTConnectivity(networkType: networkType)

        if let last = lastConnectivity, last.isEqual(to: connectivity) { return }

        Log.logger.debug("New connectivity = \(String(describing: connectivity.testResultDictionary()))")
        
        if (stopOnMixed) {
            // Detect compatilibity
            var compatible = true

            if ((lastConnectivity) != nil) {
                if (connectivity.networkType != lastConnectivity?.networkType) {
                    Log.logger.debug("Connectivity network mismatched \(String(describing: lastConnectivity?.networkTypeDescription)) -> \(String(describing: connectivity.networkTypeDescription))")
                    compatible = false
                } else if ((connectivity.networkName != lastConnectivity?.networkName) && ((connectivity.networkName != nil) || (lastConnectivity?.networkName != nil))) {
                    Log.logger.debug("Connectivity network mismatched \(String(describing: lastConnectivity?.networkName)) -> \(String(describing: connectivity.networkName))")
                    compatible = false
                }
            }

            lastConnectivity = connectivity

            if (compatible) {
                delegate?.connectivityTracker(self, didDetect: connectivity)
            } else {
                // stop
                self.stop()
                delegate?.connectivityTracker?(self, didStopAndDetectIncompatibleConnectivity: connectivity)
            }
        } else {
            lastConnectivity = connectivity
            delegate?.connectivityTracker(self, didDetect: connectivity)
        }
    }

}
