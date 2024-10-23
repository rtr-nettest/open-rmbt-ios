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
            UIAlertController.presentAlert(title: "Debug Mode \(stateString)",
                                           text: "The app will now quit to apply the new settings.",
                                           cancelTitle: "OK", otherTitle: nil) { _ in
                exit(0)
            } otherAction: { _ in }
            return true
        } else {
            return false
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        RMBTLocationTracker.shared.stop()
        NetworkReachability.shared.stopMonitoring()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        onStart(false)
    }
    
    // This method is called from both applicationWillEnterForeground and application:didFinishLaunchingWithOptions:
    private func onStart(_ isLaunched: Bool) {
        Log.logger.debug("App started")
        NetworkReachability.shared.startMonitoring()
        RMBTControlServer.shared.updateWithCurrentSettings { [weak self] in
            let tos = RMBTTOS.shared
            
            if tos.isCurrentVersionAccepted(with: RMBTControlServer.shared.termsAndConditions) {
                self?.checkNews()
            } else {
                // TODO: Remake it
                tos.bk_addObserver(forKeyPath: "lastAcceptedVersion") { [weak self] sender in
                    Log.logger.debug("TOS accepted, checking news...")
                    self?.checkNews()
                }
            }
        } error: {  _ in
            
        }

        // If user has authorized location services, we should start tracking location now, so that when test starts,
        // we already have a more accurate location
        _ = RMBTLocationTracker.shared.startIfAuthorized()
    }
    
    private func checkNews() {
        RMBTControlServer.shared.getSettings { } error: { _ in }
        RMBTControlServer.shared.getNews { [weak self] response in
            self?.showNews(response.news)
        } error: { _ in }
    }
    
    private func showNews(_ news: [RMBTNews]) {
        guard news.count > 0 else { return }
        
        var currentNews = news
        let n = currentNews.removeLast()
        UIAlertController.presentAlert(title: n.title,
                                                   text: n.text, cancelTitle: NSLocalizedString("Dismiss", comment: "News alert view button"), otherTitle: nil) { [weak self] _ in
            self?.showNews(currentNews)
        } otherAction: { _ in }
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

        let tabBar = (window?.rootViewController as? UITabBarController)?.tabBar

        tabBar?.items?[0].title = NSLocalizedString("Home", comment: "")
        tabBar?.items?[1].title = NSLocalizedString("History", comment: "")
        tabBar?.items?[2].title = NSLocalizedString("Statistics", comment: "")
        tabBar?.items?[3].title = NSLocalizedString("Map", comment: "")
    }
}

extension RMBTAppDelegate: UIAlertViewDelegate {
    
}
