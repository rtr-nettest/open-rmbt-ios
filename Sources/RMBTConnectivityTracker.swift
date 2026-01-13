//
//  RMBTConnectivityTracker.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 21.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import CoreTelephony
import NetworkExtension

@objc protocol RMBTConnectivityTrackerDelegate: AnyObject {
    func connectivityTracker(_ tracker: RMBTConnectivityTracker, didDetect connectivity: RMBTConnectivity)
    
    func connectivityTrackerDidDetectNoConnectivity(_ tracker: RMBTConnectivityTracker)
    
    @objc optional func connectivityTracker(_ tracker: RMBTConnectivityTracker, didStopAndDetectIncompatibleConnectivity connectivity: RMBTConnectivity)
}

protocol WiFiInfoProviding {
    typealias WiFiInfo = (ssid: String, bssid: String?)

    func fetchCurrent(completion: @escaping (WiFiInfo?) -> Void)
}

struct SystemWiFiInfoProvider: WiFiInfoProviding {
    func fetchCurrent(completion: @escaping (WiFiInfo?) -> Void) {
        NEHotspotNetwork.fetchCurrent { network in
            guard let network else {
                completion(nil)
                return
            }
            completion((ssid: network.ssid, bssid: network.bssid))
        }
    }
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
    private var reachabilityChangeToken: UInt = 0

    var wifiInfoProvider: any WiFiInfoProviding = SystemWiFiInfoProvider()
    
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
            let summarizedPayload: String
            if let dict = notification.object as? [String: Any] {
                summarizedPayload = dict.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",")
            } else {
                summarizedPayload = String(describing: notification.object)
            }
            Log.logger.debug("radioDidChange payload \(summarizedPayload)")
            // Sometimes iOS delivers multiple notifications without a real radio change.
            if (notification.object as? NSObject) == (self.lastRadioAccessTechnology as? NSObject) {
                Log.logger.debug("radioDidChange duplicate payload ignored")
                return
            }
            self.lastRadioAccessTechnology = notification.object
            self.reachabilityDidChange(to: NetworkReachability.shared.status)
        }
    }
    
    func reachabilityDidChange(to status: NetworkReachability.NetworkReachabilityStatus) {
        queue.async { [weak self] in
            self?._reachabilityDidChange(to: status)
        }
    }

    private func _reachabilityDidChange(to status: NetworkReachability.NetworkReachabilityStatus) {
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

        reachabilityChangeToken &+= 1
        let token = reachabilityChangeToken

        if (networkType == .none) {
            Log.logger.debug("No connectivity detected.")
            self.lastConnectivity = nil
            delegate?.connectivityTrackerDidDetectNoConnectivity(self)
            return
        }

        if networkType == .wifi {
            wifiInfoProvider.fetchCurrent { [weak self] wifiInfo in
                guard let self else { return }
                self.queue.async { [weak self] in
                    guard let self else { return }
                    guard self.reachabilityChangeToken == token else {
                        Log.logger.debug("Wi-Fi info resolved for stale reachability update, ignoring.")
                        return
                    }

                    let connectivity = RMBTConnectivity(networkType: networkType)
                    if let wifiInfo {
                        let formattedBssid = wifiInfo.bssid.map(RMBTHelpers.RMBTReformatHexIdentifier)
                        connectivity.updateWiFiInfo(ssid: wifiInfo.ssid, bssid: formattedBssid)
                    } else {
                        Log.logger.debug("Wi-Fi info unavailable (SSID/BSSID nil).")
                    }

                    self.handleNewConnectivity(connectivity)
                }
            }
            return
        }

        let connectivity = RMBTConnectivity(networkType: networkType)
        handleNewConnectivity(connectivity)
    }

    private func handleNewConnectivity(_ connectivity: RMBTConnectivity) {
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
