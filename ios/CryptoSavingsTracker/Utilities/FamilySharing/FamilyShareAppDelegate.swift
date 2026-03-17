//
//  FamilyShareAppDelegate.swift
//  CryptoSavingsTracker
//

#if os(iOS)
import UIKit

final class FamilyShareAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: connectingSceneSession.configuration.name,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = FamilyShareSceneDelegateBridge.self
        return configuration
    }
}
#endif
