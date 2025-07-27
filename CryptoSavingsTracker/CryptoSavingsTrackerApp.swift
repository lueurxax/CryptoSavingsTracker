//
//  CryptoSavingsTrackerApp.swift
//  CryptoSavingsTracker
//
//  Created by user on 25/07/2025.
//

import SwiftUI
import SwiftData

@main
struct CryptoSavingsTrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Goal.self, Asset.self, Transaction.self)
        } catch {
            print("Failed to create ModelContainer: \(error)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    init() {
        NotificationManager.shared.initialize()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
