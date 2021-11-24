//
//  RMBTAppDelegate.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 17.08.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

@UIApplicationMain
final class RMBTAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        applyAppearance()
        onStart(true)
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if url.host == "debug" || url.host == "undebug" {
            let unlock = url.host == "debug"
            RMBTSettings.shared.debugUnlocked = unlock
            let stateString = unlock ? "Unlocked" : "Locked"
            UIAlertView.bk_show(withTitle: "Debug Mode \(stateString)",
                                message: "The app will now quit to apply the new settings.",
                                cancelButtonTitle: "OK",
                                otherButtonTitles: nil) { _, _ in
                exit(0)
            }
            return true
        } else {
            return false
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        RMBTLocationTracker.shared().stop()
        NetworkReachability.shared.stopMonitoring()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        onStart(false)
    }
    
    // This method is called from both applicationWillEnterForeground and application:didFinishLaunchingWithOptions:
    private func onStart(_ isLaunched: Bool) {
        Log.logger.debug("App started")
        NetworkReachability.shared.startMonitoring()
        RMBTControlServer.shared.updateWithCurrentSettings {} error: { _ in }

        // If user has authorized location services, we should start tracking location now, so that when test starts,
        // we already have a more accurate location
        RMBTLocationTracker.shared().startIfAuthorized()
        
        let tos = RMBTTOS.shared
        
        if tos.isCurrentVersionAccepted {
            checkNews()
        } else {
            // TODO: Remake it
            tos.bk_addObserver(forKeyPath: "lastAcceptedVersion") { [weak self] sender in
                Log.logger.debug("TOS accepted, checking news...")
                self?.checkNews()
            }
        }
    }
    
    private func checkNews() {
        RMBTControlServer.shared.getSettings { } error: { _ in }
        RMBTControlServer.shared.getNews { news in
            guard let news = news as? [RMBTNews] else { return }
            
            news.forEach { n in
                UIAlertView.bk_show(withTitle: n.title,
                                    message: n.text,
                                    cancelButtonTitle: NSLocalizedString("Dismiss", comment: "News alert view button"),
                                    otherButtonTitles: nil) { _, _ in }
            }
        }
    }

    private func applyAppearance() {
        //Disable dark mode
        if #available(iOS 13.0, *) {
            window?.overrideUserInterfaceStyle = .light
        }
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
        UITabBar.appearance().tintColor = UIColor(named: "tintTabbarColor")
        UITabBar.appearance().unselectedItemTintColor = UIColor(named: "tintUnselectedTabbarColor")
        
        // Text color
        RMBTNavigationBar.appearance().titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor(red: 66.0/255.0, green: 66.0/255.0, blue: 66.0/255.0, alpha: 1.0)]
    }
}

extension RMBTAppDelegate: UIAlertViewDelegate {
    
}
