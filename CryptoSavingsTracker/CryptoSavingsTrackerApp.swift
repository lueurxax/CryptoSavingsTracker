//
//  CryptoSavingsTrackerApp.swift
//  CryptoSavingsTracker
//
//  Created by user on 25/07/2025.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

@main
struct CryptoSavingsTrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Goal.self, Asset.self, Transaction.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema, 
            isStoredInMemoryOnly: false,
            // Enable automatic migration for optional property additions like firstReminderDate
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    init() {
        Task {
            _ = await NotificationManager.shared.requestPermission()
        }
    }

    var body: some Scene {
        WindowGroup {
            OnboardingContentView()
        }
        .modelContainer(sharedModelContainer)
        
        #if os(macOS)
        // Additional window for goal comparison
        WindowGroup("Goal Comparison", id: "goal-comparison") {
            GoalComparisonView()
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1200, height: 800)
        
        // Settings window
        WindowGroup("Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 400)
        #endif
    }
}
