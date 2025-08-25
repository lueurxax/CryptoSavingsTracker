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
#if os(iOS)
import UIKit
#endif

@main
struct CryptoSavingsTrackerApp: App {
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([Goal.self, Asset.self, Transaction.self, MonthlyPlan.self, AssetAllocation.self])
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
        // Suppress haptic feedback warnings in iOS Simulator
        #if targetEnvironment(simulator) && os(iOS)
        // Disable haptic feedback system in simulator to prevent CHHapticPattern warnings
        // These warnings are harmless but create console noise during development
        if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
            // Running in iOS Simulator - haptics don't work anyway
        }
        #endif

        // Mark startup complete after a delay to prevent API spam
        Task {
            await StartupThrottler.shared.waitForStartup()
            _ = await NotificationManager.shared.requestPermission()
            
            // Perform data migration if needed
            do {
                let migrationService = MigrationService(modelContext: CryptoSavingsTrackerApp.sharedModelContainer.mainContext)
                try await migrationService.performMigrationIfNeeded()
            } catch {
                print("Migration failed: \(error)")
                // In production, you might want to handle this more gracefully
                // For now, we'll continue with the app startup
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            OnboardingContentView()
        }
        .modelContainer(CryptoSavingsTrackerApp.sharedModelContainer)

        #if os(macOS)
        // Additional window for goal comparison
        WindowGroup("Goal Comparison", id: "goal-comparison") {
            GoalComparisonView()
        }
        .modelContainer(CryptoSavingsTrackerApp.sharedModelContainer)
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
