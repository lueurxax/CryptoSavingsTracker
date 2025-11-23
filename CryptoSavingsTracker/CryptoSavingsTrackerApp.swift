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
        let schema = Schema([
            Goal.self,
            Asset.self,
            Transaction.self,
            MonthlyPlan.self,
            AssetAllocation.self,
            Contribution.self,
            MonthlyExecutionRecord.self,
            ExecutionSnapshot.self,
            MigrationMetadata.self
        ])
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

                // Perform MonthlyPlan Schema V2 migration
                let planMigrationService = MonthlyPlanMigrationService(modelContext: CryptoSavingsTrackerApp.sharedModelContainer.mainContext)
                try await planMigrationService.migrateToSchemaV2()

                // Verify migration
                let verification = try await planMigrationService.verifyMigration()
                AppLog.info(verification.description, category: .monthlyPlanning)

                if !verification.isSuccessful {
                    AppLog.error("MonthlyPlan migration verification failed!", category: .monthlyPlanning)
                }
            } catch {
                AppLog.error("Migration failed: \(error)", category: .monthlyPlanning)
                // In production, you might want to handle this more gracefully
                // For now, we'll continue with the app startup
            }

            // Check for automated monthly execution transitions
            Task { @MainActor in
                await CryptoSavingsTrackerApp.checkAutomation()
            }
        }
    }

    /// Check and execute any pending automation based on settings
    @MainActor
    private static func checkAutomation() async {
        let scheduler = AutomationScheduler(modelContext: CryptoSavingsTrackerApp.sharedModelContainer.mainContext)

        do {
            // Check if automation should trigger
            try await scheduler.checkAndExecuteAutomation()

            // Schedule future automation notifications
            try await scheduler.scheduleAutomationNotifications()
        } catch {
            print("Automation check failed: \(error)")
            // Continue app startup even if automation fails
        }
    }

    var body: some Scene {
        WindowGroup {
            OnboardingContentView()
        }
        .modelContainer(CryptoSavingsTrackerApp.sharedModelContainer)
        #if os(macOS)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 700)
        #endif

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
