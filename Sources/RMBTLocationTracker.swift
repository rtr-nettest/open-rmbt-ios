//
//  RMBTLocationTracker.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 09.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import Foundation
import CoreLocation

@objc extension NSNotification {
    public static let RMBTLocationTrackerNotification = Notification.Name.RMBTLocationTracker
}

public extension Notification.Name {
    static let RMBTLocationTracker = Notification.Name("RMBTLocationTrackerNotification")
}

@objc class RMBTLocationTracker: NSObject {

    @objc(sharedTracker) public static let shared = RMBTLocationTracker()
    
    public let locationManager: CLLocationManager
    
    open var authorizationCallback: EmptyCallback?
    
    @objc open var location: CLLocation? {
        if let result = locationManager.location, CLLocationCoordinate2DIsValid(result.coordinate) {
            return result
        }

        return nil
    }
    
    override init() {
        locationManager = CLLocationManager()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3.0

        super.init()

        locationManager.delegate = self
    }
    
    open func stop() {
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopUpdatingLocation()
    }
    
    open func startIfAuthorized() -> Bool {
        let authorizationStatus = locationManager.authorizationStatus

        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
            return true
        }
        return false
    }
    
    open func startAfterDeterminingAuthorizationStatus(_ callback: @escaping EmptyCallback) {
        if startIfAuthorized() {
            callback()
        } else if locationManager.authorizationStatus == .notDetermined {
            // Not determined yet
            authorizationCallback = callback

            locationManager.requestWhenInUseAuthorization()
        } else {
            Log.logger.warning("User hasn't enabled or authorized location services")
            callback()
        }
    }
    
    @objc open func forceUpdate() {
        stop()
        _ = startIfAuthorized()
    }
    
    var isAuthorized: Bool {
        locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse
    }

    var isLocationDenied: Bool {
        locationManager.authorizationStatus == .denied
    }
}

extension RMBTLocationTracker: CLLocationManagerDelegate {
    open func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        NotificationCenter.default.post(name: .RMBTLocationTracker,
                                        object: self,
                                        userInfo:["locations": locations])
    }
    
    
    open func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        #if os(iOS) // TODO: replacement for this method?
        if locationManager.responds(to: #selector(CLLocationManager.startUpdatingLocation)) {
            locationManager.startUpdatingLocation()
        }
        #endif

        if let authorizationCallback = self.authorizationCallback {
            authorizationCallback()
        }
    }

    open func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.logger.error("Failed to obtain location \(error)")
    }
}
