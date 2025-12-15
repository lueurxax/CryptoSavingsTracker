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
            AllocationHistory.self,
            Contribution.self,
            MonthlyExecutionRecord.self,
            CompletedExecution.self,
            ExecutionSnapshot.self
        ])
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let appSupport {
            // Ensure the Application Support directory exists before SwiftData tries to create the SQLite store.
            // This avoids sporadic CoreData errors about failing to stat/create `default.store`.
            try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }

        let modelConfiguration = ModelConfiguration(
            "default",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none  // CloudKit requires model changes (optional attrs, inverse relationships)
        )

        func resetStoreFilesIfPresent() {
            guard let appSupport else { return }
            let storeURL = appSupport.appendingPathComponent("default.store")
            let candidatePaths = [
                storeURL.path,
                storeURL.path + "-shm",
                storeURL.path + "-wal",
                storeURL.path + "-journal"
            ]

            for path in candidatePaths {
                try? fileManager.removeItem(atPath: path)
            }
        }

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Initial-schema-only strategy: if the store can't be opened due to schema mismatch,
            // wipe and recreate. This is acceptable while we have 0 clients.
            resetStoreFilesIfPresent()
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
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
            let isUITestRun = ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("UITEST") })
            if !isUITestRun {
                _ = await NotificationManager.shared.requestPermission()
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
        // UI tests should not trigger automation or notification scheduling (causes permission prompts and flakiness).
        let isUITestRun = ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("UITEST") })
        if isUITestRun { return }

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

    // MARK: - UI Test Seeding

    private static var didRunUITestSeed = false

    /// Seed deterministic data for UI tests: two goals, shared asset, plans, start execution,
    /// and record a deposit + reallocation to surface shared-asset sync issues.
    @MainActor
    static func runUITestSeedIfNeeded(context: ModelContext) async {
        guard !didRunUITestSeed else { return }
        let args = ProcessInfo.processInfo.arguments
        let shouldSeed = args.contains("UITEST_SEED_SHARED_ASSET")
        let shouldReshare = args.contains("UITEST_RESHARE_ASSET")
        guard shouldSeed || shouldReshare else { return }
        didRunUITestSeed = true

        OnboardingManager.shared.completeOnboarding()

        if shouldSeed {
            await seedUITestData(context: context)
        }

        if shouldReshare {
            await applyUITestReshare(context: context)
        }
    }

    @MainActor
    private static func seedUITestData(context: ModelContext) async {
        do {
            // Clear existing data to avoid cross-test contamination
            for completed in try context.fetch(FetchDescriptor<CompletedExecution>()) { context.delete(completed) }
            for contrib in try context.fetch(FetchDescriptor<Contribution>()) { context.delete(contrib) }
            for plan in try context.fetch(FetchDescriptor<MonthlyPlan>()) { context.delete(plan) }
            for record in try context.fetch(FetchDescriptor<MonthlyExecutionRecord>()) { context.delete(record) }
            for history in try context.fetch(FetchDescriptor<AllocationHistory>()) { context.delete(history) }
            for allocation in try context.fetch(FetchDescriptor<AssetAllocation>()) { context.delete(allocation) }
            for tx in try context.fetch(FetchDescriptor<Transaction>()) { context.delete(tx) }
            for goal in try context.fetch(FetchDescriptor<Goal>()) { context.delete(goal) }
            for asset in try context.fetch(FetchDescriptor<Asset>()) { context.delete(asset) }
            try context.save()

            // Goals
            let goalA = Goal(
                name: "UI Goal A",
                currency: "USD",
                targetAmount: 4000,
                deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
            )
            let goalB = Goal(
                name: "UI Goal B",
                currency: "USD",
                targetAmount: 3000,
                deadline: Calendar.current.date(byAdding: .month, value: 6, to: Date())!
            )
            context.insert(goalA)
            context.insert(goalB)

            // Shared asset with a balance
            let sharedAsset = Asset(currency: "USD")
            let seedTx = Transaction(amount: 200, asset: sharedAsset)
            sharedAsset.transactions.append(seedTx)
            context.insert(sharedAsset)
            try context.save()

            // Services
            let planService = DIContainer.shared.makeMonthlyPlanService(modelContext: context)
            let executionService = DIContainer.shared.executionTrackingService(modelContext: context)
            let contributionService = ContributionService(modelContext: context)

            // Create plans and start execution
            let plans = try await planService.getOrCreatePlansForCurrentMonth(goals: [goalA, goalB])
            let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
            let record = try executionService.startTracking(for: monthLabel, from: plans, goals: [goalA, goalB])

            // Deposit to Goal A
            let deposit = try contributionService.recordDeposit(
                amount: 120,
                assetAmount: 120,
                to: goalA,
                from: sharedAsset,
                exchangeRate: 1.0
            )
            try executionService.linkContribution(deposit, to: record)

            // Reallocate 40 from A to B
            let reallocation = try contributionService.recordReallocation(
                fiatAmount: 40,
                assetAmount: 40,
                from: goalA,
                to: goalB,
                asset: sharedAsset,
                exchangeRate: 1.0
            )
            try executionService.linkContribution(reallocation.withdrawal, to: record)
            try executionService.linkContribution(reallocation.deposit, to: record)

            try context.save()
            AppLog.info("UITest seed complete", category: .executionTracking)
        } catch {
            AppLog.error("UITest seed failed: \(error)", category: .executionTracking)
        }
    }

    /// Apply an additional reallocation to simulate resharing an asset between goals.
    @MainActor
    private static func applyUITestReshare(context: ModelContext) async {
        do {
            // Fetch existing seeded goals
            let goals = try context.fetch(FetchDescriptor<Goal>())
            guard let goalA = goals.first(where: { $0.name == "UI Goal A" }),
                  let goalB = goals.first(where: { $0.name == "UI Goal B" }) else {
                AppLog.warning("UITest reshare skipped: goals not found", category: .executionTracking)
                return
            }

            let executionService = DIContainer.shared.executionTrackingService(modelContext: context)
            guard let record = try executionService.getCurrentMonthRecord() else {
                AppLog.warning("UITest reshare skipped: execution record not found", category: .executionTracking)
                return
            }

            // Reuse shared asset or create if missing
            let asset: Asset
            if let existing = try context.fetch(FetchDescriptor<Asset>()).first(where: { $0.currency == "USD" }) {
                asset = existing
            } else {
                asset = Asset(currency: "USD")
                context.insert(asset)
            }

            let contributionService = ContributionService(modelContext: context)
            // Reallocate an extra 20 from A to B to change totals (net A 60, B 60)
            let reallocation = try contributionService.recordReallocation(
                fiatAmount: 20,
                assetAmount: 20,
                from: goalA,
                to: goalB,
                asset: asset,
                exchangeRate: 1.0
            )
            try executionService.linkContribution(reallocation.withdrawal, to: record)
            try executionService.linkContribution(reallocation.deposit, to: record)

            try context.save()
            AppLog.info("UITest reshare applied", category: .executionTracking)
        } catch {
            AppLog.error("UITest reshare failed: \(error)", category: .executionTracking)
        }
    }

    // MARK: - UITest reset

    private static var didRunUITestReset = false
    static func runUITestResetIfNeeded(context: ModelContext) async {
        guard !didRunUITestReset else { return }
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("UITEST_RESET_DATA") else { return }
        didRunUITestReset = true

        await MainActor.run {
            do {
                let completedExecutions = try context.fetch(FetchDescriptor<CompletedExecution>())
                let contributions = try context.fetch(FetchDescriptor<Contribution>())
                let execRecords = try context.fetch(FetchDescriptor<MonthlyExecutionRecord>())
                let snapshots = try context.fetch(FetchDescriptor<ExecutionSnapshot>())
                let plans = try context.fetch(FetchDescriptor<MonthlyPlan>())
                let allocationHistories = try context.fetch(FetchDescriptor<AllocationHistory>())
                let allocations = try context.fetch(FetchDescriptor<AssetAllocation>())
                let transactions = try context.fetch(FetchDescriptor<Transaction>())
                let assets = try context.fetch(FetchDescriptor<Asset>())
                let goals = try context.fetch(FetchDescriptor<Goal>())

                (completedExecutions as [any PersistentModel]).forEach { context.delete($0) }
                (contributions as [any PersistentModel]).forEach { context.delete($0) }
                (execRecords as [any PersistentModel]).forEach { context.delete($0) }
                (snapshots as [any PersistentModel]).forEach { context.delete($0) }
                (plans as [any PersistentModel]).forEach { context.delete($0) }
                (allocationHistories as [any PersistentModel]).forEach { context.delete($0) }
                (allocations as [any PersistentModel]).forEach { context.delete($0) }
                (transactions as [any PersistentModel]).forEach { context.delete($0) }
                (assets as [any PersistentModel]).forEach { context.delete($0) }
                (goals as [any PersistentModel]).forEach { context.delete($0) }

                try context.save()
                OnboardingManager.shared.completeOnboarding()
                AppLog.info("UITEST_RESET_DATA cleared all entities", category: .ui)
            } catch {
                AppLog.error("UITEST_RESET_DATA failed: \(error)", category: .ui)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            let args = ProcessInfo.processInfo.arguments
            UITestBootstrapView {
                if args.contains("UITEST_SEED_SHARED_ASSET") {
                    MonthlyPlanningContainer()
                } else if args.contains("UITEST_UI_FLOW") {
                    ContentView()
                } else {
                    OnboardingContentView()
                }
            }
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
