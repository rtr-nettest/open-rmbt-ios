//
//  RMBTAppDelegate.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 17.08.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import SwiftUI

@UIApplicationMain
final class RMBTAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        applyAppearance()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        LogConfig.flushLog()
    }

    private func applyAppearance() {
        // Background color
        if #available(iOS 13.0, *) {
            let navigationBarAppearance = UINavigationBarAppearance()
            navigationBarAppearance.configureWithTransparentBackground()
            navigationBarAppearance.backgroundColor = .white
            navigationBarAppearance.titleTextAttributes = [
                .foregroundColor: UIColor(red: 66.0/255.0, green: 66.0/255.0, blue: 66.0/255.0, alpha: 1.0),
                .font: UIFont.roboto(size: 20, weight: .medium)
            ]
            RMBTNavigationBar.appearance().standardAppearance = navigationBarAppearance
            RMBTNavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance

            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithDefaultBackground()
            tabBarAppearance.backgroundColor = .white
            UITabBar.appearance().standardAppearance = tabBarAppearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
            } else {
                // Fallback on earlier versions
            }
        } else {
            RMBTNavigationBar.appearance().barTintColor = UIColor.white
            RMBTNavigationBar.appearance().barTintColor = UIColor.white
            RMBTNavigationBar.appearance().titleTextAttributes = [
                .foregroundColor: UIColor.black,
                .font: UIFont.roboto(size: 20, weight: .medium)
            ]
        }

        // Tint color
        RMBTNavigationBar.appearance().tintColor = UIColor(red: 66.0/255.0, green: 66.0/255.0, blue: 66.0/255.0, alpha: 1.0)
        RMBTNavigationBar.appearance().isTranslucent = false

        UITabBar.appearance().barTintColor = .white
        UITabBar.appearance().tintColor = .brand
        UITabBar.appearance().unselectedItemTintColor = UIColor(named: "tintUnselectedTabbarColor")

        // Text color
        RMBTNavigationBar.appearance().titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor(red: 66.0/255.0, green: 66.0/255.0, blue: 66.0/255.0, alpha: 1.0)]
    }
}

extension RMBTAppDelegate: UIAlertViewDelegate {

}
