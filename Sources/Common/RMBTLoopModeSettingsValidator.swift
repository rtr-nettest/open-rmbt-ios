//
//  RMBTLoopModeSettingsValidator.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 22.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

@objc class RMBTLoopModeSettingsValidator: NSObject {
    @objc static func validateCountTest(for loopModeInfo: RMBTLoopInfo) -> Bool {
        if RMBTSettings.shared.debugUnlocked,
           loopModeInfo.total > 0 {
            return true
        } else if loopModeInfo.total > RMBTConfig.shared.RMBT_TEST_LOOPMODE_MAX_COUNT ||
            loopModeInfo.total < RMBTConfig.shared.RMBT_TEST_LOOPMODE_MIN_COUNT {
            return false
        }
        
        return true
    }
    
    @objc static func validateDuration(for loopModeInfo: RMBTLoopInfo) -> Bool {
        if RMBTSettings.shared.debugUnlocked,
           loopModeInfo.waitMinutes > 0 {
            return true
        } else if loopModeInfo.waitMinutes < RMBTConfig.shared.RMBT_TEST_LOOPMODE_MIN_DELAY_MINS ||
            loopModeInfo.waitMinutes >
                    RMBTConfig.shared.RMBT_TEST_LOOPMODE_MAX_DELAY_MINS {
            return false
        }
        
        return true
    }
    
    @objc static func validateDistance(for loopModeInfo: RMBTLoopInfo) -> Bool {
        if RMBTSettings.shared.debugUnlocked,
           loopModeInfo.waitMeters > 0 {
            return true
        } else if loopModeInfo.waitMeters < RMBTConfig.shared.RMBT_TEST_LOOPMODE_MIN_MOVEMENT_M ||
            loopModeInfo.waitMeters > RMBTConfig.shared.RMBT_TEST_LOOPMODE_MAX_MOVEMENT_M {
            return false
        }
        
        return true
    }
}
