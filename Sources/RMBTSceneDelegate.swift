//
//  RMBTSceneDelegate.swift
//  RMBT
//

import UIKit

final class RMBTSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private var hasEnteredBackground = false

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        window?.overrideUserInterfaceStyle = .light
        localizeTabBarTitles()
        onStart(true)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        hasEnteredBackground = true
        RMBTLocationTracker.shared.stop()
        NetworkReachability.shared.stopMonitoring()
        // Log writes are queued off the calling thread, so drain them while we still have a chance to run.
        LogConfig.flushLog()
    }

    // Also fires on cold launch, which onStart(true) has already covered.
    func sceneWillEnterForeground(_ scene: UIScene) {
        guard hasEnteredBackground else { return }
        hasEnteredBackground = false
        onStart(false)
    }

    private func localizeTabBarTitles() {
        let tabBar = (window?.rootViewController as? UITabBarController)?.tabBar
        tabBar?.items?[0].title = NSLocalizedString("Home", comment: "")
        tabBar?.items?[1].title = NSLocalizedString("History", comment: "")
        tabBar?.items?[2].title = NSLocalizedString("Statistics", comment: "")
        tabBar?.items?[3].title = NSLocalizedString("Map", comment: "")
    }

    private func onStart(_ isLaunched: Bool) {
        Log.logger.debug("App started")
        NetworkReachability.shared.startMonitoring()
        RMBTControlServer.shared.updateWithCurrentSettings { [weak self] in
            let tos = RMBTTOS.shared

            if tos.isCurrentVersionAccepted(with: RMBTControlServer.shared.termsAndConditions) {
                self?.checkNews(isLaunched: isLaunched)
            } else {
                // TODO: Remake it
                tos.bk_addObserver(forKeyPath: "lastAcceptedVersion") { [weak self] sender in
                    Log.logger.debug("TOS accepted, checking news...")
                    self?.checkNews(isLaunched: isLaunched)
                }
            }
        } error: {  _ in
        }

        // If user has authorized location services, we should start tracking location now, so that when test starts,
        // we already have a more accurate location
        _ = RMBTLocationTracker.shared.startIfAuthorized()
    }

    private func checkNews(isLaunched: Bool) {
        RMBTControlServer.shared.getSettings {
            Task {
                try? await NetworkCoverageFactory().persistedFencesSender.resendPersistentAreas(isLaunched: isLaunched)
            }
        } error: { _ in }

        RMBTControlServer.shared.getNews { [weak self] response in
            self?.showNews(response.news)
        } error: { _ in }
    }

    private func showNews(_ news: [RMBTNews]) {
        guard news.count > 0 else { return }

        var currentNews = news
        let n = currentNews.removeLast()

        UIAlertController.presentAlert(
            title: n.title,
            text: n.text,
            cancelTitle: NSLocalizedString("Dismiss", comment: "News alert view button"),
            otherTitle: nil
        ) { [weak self] _ in
            self?.showNews(currentNews)
        } otherAction: { _ in }
    }
}
