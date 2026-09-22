//
//  RMBTSceneDelegate.swift
//  RMBT
//

import UIKit

/// The app adopts the UIScene life cycle (required by the iOS 26+ SDK). This delegate owns the window and
/// forwards the app-level foreground/background work to `RMBTAppDelegate`, which remains the single owner of
/// that logic. The window is created explicitly here from `MainStoryboard` (rather than relying on the
/// storyboard-manifest auto-setup, which does not reliably make the window key & visible once a scene
/// delegate implements `willConnectTo` — the symptom being a black screen at launch).
final class RMBTSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    /// `sceneWillEnterForeground(_:)` also fires on cold launch (which the app delegate's launch `onStart`
    /// already covers), so the foreground work is only re-run after a real background → foreground return.
    private var hasEnteredBackground = false

    private var appDelegate: RMBTAppDelegate? { UIApplication.shared.delegate as? RMBTAppDelegate }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = UIStoryboard(name: "MainStoryboard", bundle: nil).instantiateInitialViewController()
        self.window = window
        window.makeKeyAndVisible()

        appDelegate?.localizeTabBarTitles(in: window)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        hasEnteredBackground = true
        appDelegate?.didEnterBackground()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        guard hasEnteredBackground else { return }
        hasEnteredBackground = false
        appDelegate?.willEnterForeground()
    }
}
