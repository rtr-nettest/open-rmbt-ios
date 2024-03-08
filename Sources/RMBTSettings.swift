/*****************************************************************************************************
 * Copyright 2013 appscape gmbh
 * Copyright 2014-2016 SPECURE GmbH
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *****************************************************************************************************/

import Foundation

///
@objc final class RMBTSettings: NSObject {
    
    public enum NerdModeQosMode: Int {
        case manually
        case newNetwork
        case always
    }
    
    @objc(sharedSettings) public static let shared = RMBTSettings()

// MARK: Temporary app state (global variables)

    ///
    @objc public dynamic var mapOptionsSelection: RMBTMapOptionsSelection

// MARK: Persisted app state
    @objc public dynamic var testCounter: UInt = 0
    @objc public dynamic var previousTestStatus: String?

// MARK: User configurable properties

    ///
    @objc public dynamic var publishPublicData = false // only for akos
    
    @objc public dynamic var submitZeroTesting = true

    /// anonymous mode
    @objc public dynamic var anonymousModeEnabled = false

// MARK: Nerd mode

    ///
    @objc public dynamic var nerdModeEnabled = false
    @objc public dynamic var forceIPv4 = false

    ///
    @objc public dynamic var debugForceIPv6 = false
    
    @objc public dynamic var isDarkMode = false

    ///
    @objc public dynamic var nerdModeQosEnabled = NerdModeQosMode.newNetwork.rawValue // Enable QoS

// MARK: Debug properties

    ///
    
    @objc public dynamic var debugUnlocked = false
    @objc public dynamic var expertMode = false

    // loop mode

    ///
    @objc public dynamic var loopMode = false
    @objc public dynamic var loopModeLastCount: UInt = 0

    ///
    @objc public dynamic var debugLoopModeMaxTests: UInt = 0
    @objc public dynamic var loopModeEveryMeters: UInt = 0
    @objc public dynamic var loopModeEveryMinutes: UInt = 0
    
    ///
    @objc public dynamic var debugLoopModeMinDelay: UInt = 0
    
    @objc public dynamic var qosEnabled: Bool = false
    @objc public dynamic var only2Hours: Bool = false
    @objc public dynamic var previousLaunchQoSDate: Date?
    
    
    @objc public dynamic var debugLoopModeDistance: UInt = 0
    
    @objc public dynamic var debugLoopModeIsStartImmedatelly: Bool = true

    // control server

    ///
    @objc public dynamic var debugControlServerCustomizationEnabled = false

    ///
    @objc public dynamic var debugControlServerHostname: String?

    ///
    @objc public dynamic var debugControlServerPort: UInt = 0

    ///
    @objc public dynamic var debugControlServerUseSSL = false

    // map server

    ///
    @objc public dynamic var debugMapServerCustomizationEnabled = false

    ///
    @objc public dynamic var debugMapServerHostname: String?

    ///
    @objc public dynamic var debugMapServerPort: UInt = 0

    ///
    @objc public dynamic var debugMapServerUseSSL = false

    // logging

    ///
    @objc public dynamic var debugLoggingEnabled = false
    @objc public dynamic var debugLoggingHostname: String?
    @objc public dynamic var debugLoggingPort: UInt = 0
    
    @objc public dynamic var previousNetworkName: String?
    @objc public dynamic var isAdsRemoved: Bool = false
    
    @objc public dynamic var lastSurveyTimestamp: Double = 0.0
    
    @objc public dynamic var isClientPersistent: Bool = true
    @objc public dynamic var isAnalyticsEnabled: Bool = true
    
    @objc public dynamic var countMeasurements: Int = 0
    @objc public dynamic var isDevModeEnabled: Bool = false
    @objc public dynamic var serverIdentifier: String?
    @objc public dynamic var isOverrideServer: Bool = false
    @objc public dynamic var activeMeasurementId: String?

    ///
    private override init() {
        mapOptionsSelection = RMBTMapOptionsSelection()

        super.init()

        UserDefaults.appDefaults.register(defaults:
        [
            "loopModeEveryMeters": RMBTConfig.RMBT_TEST_LOOPMODE_DEFAULT_MOVEMENT_M,
            "loopModeEveryMinutes": RMBTConfig.RMBT_TEST_LOOPMODE_DEFAULT_DELAY_MINS,
            "loopModeLastCount": RMBTConfig.RMBT_TEST_LOOPMODE_DEFAULT_COUNT
        ])
        
        bindKeyPaths([
            "testCounter",
            "previousTestStatus",

            "debugUnlocked",
            "developerModeEnabled", // TODO: this should replace debug unlocked

            ///////////
            // USER SETTINGS

            // general
            "publishPublicData",
            "submitZeroTesting",

            // anonymous mode
            "anonymousModeEnabled",

            ///////////
            // NERD MODE

            // nerd mode
            "nerdModeEnabled",

            "forceIPv4",
            "debugForceIPv6",

            // nerd mode, advanced settings, qos
            "nerdModeQosEnabled",

            ///////////
            // DEVELOPER MODE

            // developer mode, advanced settings, loop mode
            "loopMode",
            "developerModeLoopModeMaxTests",
            "developerModeLoopModeMinDelay",

            // control server

            "debugControlServerCustomizationEnabled",
            "debugControlServerHostname",
            "debugControlServerPort",
            "debugControlServerUseSSL",

            "debugLoggingHostname",
            "debugLoggingPort",
            // map server

            "debugMapServerCustomizationEnabled",
            "debugMapServerHostname",
            "debugMapServerPort",
            "debugMapServerUseSSL",

            // logging

            "debugLoggingEnabled",
            "previousNetworkName",
            "isAdsRemoved",
            
            "lastSurveyTimestamp",
            
            //Loop mode
            "debugLoopMode",
            "loopModeLastCount",
            "loopModeEveryMeters",
            "loopModeEveryMinutes",
            "debugLoopModeMinDelay",
            "qosEnabled",
            "only2Hours",
            "previousLaunchQoSDate",
            "debugLoopModeDistance",
            "debugLoopModeIsStartImmedatelly",
            "isDarkMode",
            "isClientPersistent",
            "isAnalyticsEnabled",
            "countMeasurements",
            "isDevModeEnabled",
            "serverIdentifier",
            "isOverrideServer",
            "expertMode"
        ])
    }

    ///
    private func bindKeyPaths(_ keyPaths: [String]) {
        for keyPath in keyPaths {
            if let value = UserDefaults.getDataFor(key: keyPath) {
                setValue(value, forKey: keyPath)
            }

            // Start observing
//            addObserver(self, forKeyPath: keyPath, options: .new, context: nil)
            self.addObserver(self, forKeyPath: keyPath, options: [.new], context: nil)
        }
    }

    ///
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let newValue = change?[NSKeyValueChangeKey.newKey], let kp = keyPath {
            Log.logger.debugExec() {
                let oldValue = UserDefaults.getDataFor(key: kp)
                Log.logger.debug("Settings changed for keyPath '\(String(describing: keyPath))' from '\(String(describing: oldValue))' to '\(newValue)'")
            }

            UserDefaults.storeDataFor(key: kp, obj: newValue)
        }
    }
}
