//
//  AppDelegate.swift
//  Reachability
//
//  Created by Dmytro Shapovalov on 25.09.2020.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {



  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Override point for customization after application launch.
    
    NotificationCenter.default.addObserver(self, selector: #selector(updateValue(_ :)), name: .reachabilityChanged, object: nil)
    let _ = Reachability.live.startNotifier()
    
    return true
  }

  // MARK: UISceneSession Lifecycle

  func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
  }

  func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
  }

  @objc func updateValue(_ notification: Notification) {
    guard let networkStatus = (notification.object as? Bool) else { return }
    print("Network status is reachable: \(networkStatus)")
  }
}

