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
    static let previewModelContainer: ModelContainer = PersistenceStackFactory.makePreviewContainer()

    @StateObject private var persistenceController = PersistenceController.shared

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
            let args = ProcessInfo.processInfo.arguments
            let isXCTestRun = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            let isUITestRun = args.contains(where: { $0.hasPrefix("UITEST") })
            let isPreviewRun = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            let isTestRun = isXCTestRun || isUITestRun || isPreviewRun

            if !isTestRun {
                _ = await NotificationManager.shared.requestPermission()
            }

            // Check for automated monthly execution transitions
            Task { @MainActor in
                do {
                    let service = DIContainer.shared.executionTrackingService(
                        modelContext: PersistenceController.shared.activeMainContext
                    )
                    _ = try service.backfillCompletionEventsIfNeeded()
                } catch {
                    AppLog.warning("CompletionEvent backfill skipped: \(error)", category: .executionTracking)
                }
                await CryptoSavingsTrackerApp.checkAutomation()
            }
        }
    }

    /// Check and execute any pending automation based on settings
    @MainActor
    private static func checkAutomation() async {
        // Tests should not trigger automation or notification scheduling (causes permission prompts and flakiness).
        let args = ProcessInfo.processInfo.arguments
        let isXCTestRun = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let isUITestRun = args.contains(where: { $0.hasPrefix("UITEST") })
        let isPreviewRun = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if isXCTestRun || isUITestRun || isPreviewRun { return }

        let scheduler = AutomationScheduler(modelContext: PersistenceController.shared.activeMainContext)

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
        let shouldSeedGoalsOnly = UITestFlags.shouldSeedGoals
        let shouldSeedManyGoals = UITestFlags.shouldSeedManyGoals
        let shouldSeed = UITestFlags.shouldSeedSharedAsset
        let shouldSeedPresentationFlow = args.contains("UITEST_PRESENTATION_FLOW")
        let shouldReshare = args.contains("UITEST_RESHARE_ASSET")
        let shouldSeedBudgetShortfall = UITestFlags.shouldSeedBudgetShortfall
        let shouldSeedStaleDrafts = UITestFlags.shouldSeedStaleDrafts
        guard shouldSeedGoalsOnly || shouldSeedManyGoals || shouldSeed || shouldSeedPresentationFlow || shouldReshare || shouldSeedBudgetShortfall || shouldSeedStaleDrafts else { return }
        didRunUITestSeed = true

        OnboardingManager.shared.completeOnboarding()

        var didSeedGoals = false

        if shouldSeedGoalsOnly {
            await seedUITestGoals(context: context, count: 1)
            didSeedGoals = true
        }

        if shouldSeedManyGoals {
            await seedUITestGoals(context: context, count: 18)
            didSeedGoals = true
        }

        if shouldSeed {
            await seedUITestData(context: context)
        }

        if shouldSeedPresentationFlow {
            await seedUITestData(context: context)
        }

        if shouldReshare {
            await applyUITestReshare(context: context)
        }

        if shouldSeedBudgetShortfall {
            if !didSeedGoals {
                await seedUITestGoals(context: context, count: 1)
            }
            await seedUITestBudgetShortfall()
        }

        if shouldSeedStaleDrafts {
            if !didSeedGoals {
                await seedUITestGoals(context: context, count: 1)
            }
            await seedUITestStaleDrafts(context: context)
        }
    }

    @MainActor
    private static func seedUITestGoals(context: ModelContext, count: Int) async {
        do {
            // If tests didn't request a reset, keep existing data and avoid duplicate deterministic goals.
            let existingGoals = try context.fetch(FetchDescriptor<Goal>())
            let expectedNames: [String]
            if count <= 1 {
                expectedNames = ["UI Goal Seed"]
            } else {
                expectedNames = (1...count).map { "UI Goal \($0)" }
            }

            let existingNames = Set(existingGoals.map(\.name))
            if Set(expectedNames).isSubset(of: existingNames) {
                return
            }

            if count <= 1 {
                let goal = Goal(
                    name: "UI Goal Seed",
                    currency: "USD",
                    targetAmount: 1000,
                    deadline: Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date().addingTimeInterval(86400 * 90)
                )
                context.insert(goal)
            } else {
                for index in 1...count {
                    let goal = Goal(
                        name: "UI Goal \(index)",
                        currency: "USD",
                        targetAmount: Double(900 + index * 150),
                        deadline: Calendar.current.date(byAdding: .month, value: 1 + (index % 10), to: Date())
                            ?? Date().addingTimeInterval(86400 * 30 * Double(1 + (index % 10)))
                    )
                    context.insert(goal)
                }
            }

            try context.save()
            AppLog.info("UITest goals seed complete (\(count) goals)", category: .ui)
        } catch {
            AppLog.error("UITest goals seed failed: \(error)", category: .ui)
        }
    }

    @MainActor
    private static func seedUITestBudgetShortfall() async {
        let settings = MonthlyPlanningSettings.shared
        settings.budgetCurrency = "USD"
        settings.monthlyBudget = 1
        settings.budgetAppliedMonthLabel = nil
        settings.budgetAppliedSignature = nil
        AppLog.info("UITest shortfall budget seeded", category: .ui)
    }

    @MainActor
    private static func seedUITestStaleDrafts(context: ModelContext) async {
        do {
            let goals = try context.fetch(FetchDescriptor<Goal>())
            let goal: Goal
            if let existingGoal = goals.first(where: { $0.name == "UI Goal Seed" }) ?? goals.first {
                goal = existingGoal
            } else {
                let newGoal = Goal(
                    name: "UI Goal Seed",
                    currency: "USD",
                    targetAmount: 1800,
                    deadline: Calendar.current.date(byAdding: .month, value: 4, to: Date())
                        ?? Date().addingTimeInterval(86400 * 120)
                )
                context.insert(newGoal)
                goal = newGoal
            }

            let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            let monthLabel = MonthlyExecutionRecord.monthLabel(from: previousMonth)
            let existingPlans = try context.fetch(FetchDescriptor<MonthlyPlan>())
            let alreadySeeded = existingPlans.contains { plan in
                plan.goalId == goal.id && plan.monthLabel == monthLabel && plan.state == .draft
            }

            if !alreadySeeded {
                let stalePlan = MonthlyPlan(
                    goalId: goal.id,
                    monthLabel: monthLabel,
                    requiredMonthly: 275,
                    remainingAmount: 1_650,
                    monthsRemaining: 6,
                    currency: goal.currency,
                    status: .attention,
                    state: .draft
                )
                context.insert(stalePlan)
            }

            try context.save()
            AppLog.info("UITest stale draft seed complete", category: .ui)
        } catch {
            AppLog.error("UITest stale draft seed failed: \(error)", category: .ui)
        }
    }

    @MainActor
    private static func seedUITestData(context: ModelContext) async {
        do {
            // Clear existing data to avoid cross-test contamination
            for completed in try context.fetch(FetchDescriptor<CompletedExecution>()) { context.delete(completed) }
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

            // Create plans and start execution
            let plans = try await planService.getOrCreatePlansForCurrentMonth(goals: [goalA, goalB])
            let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
            let record = try executionService.startTracking(for: monthLabel, from: plans, goals: [goalA, goalB])

            // Allocate shared asset fully to Goal A, then expand targets on deposit to keep it dedicated.
            let allocationA = AssetAllocation(asset: sharedAsset, goal: goalA, amount: sharedAsset.currentAmount)
            context.insert(allocationA)
            context.insert(AllocationHistory(asset: sharedAsset, goal: goalA, amount: allocationA.amountValue, timestamp: record.startedAt ?? Date()))

            // Deposit to the shared asset after tracking start (counts for Goal A because it's dedicated+fully allocated).
            let depositDate = (record.startedAt ?? Date()).addingTimeInterval(60)
            let depositTx = Transaction(amount: 120, asset: sharedAsset, date: depositDate)
            sharedAsset.transactions.append(depositTx)
            context.insert(depositTx)
            let newTargetA = allocationA.amountValue + 120
            allocationA.updateAmount(newTargetA)
            context.insert(AllocationHistory(asset: sharedAsset, goal: goalA, amount: newTargetA, timestamp: depositDate))

            // Reallocate 40 from A to B after deposit (counts as asset reallocation).
            let reallocDate = depositDate.addingTimeInterval(60)
            allocationA.updateAmount(max(0, newTargetA - 40))
            let allocationB = AssetAllocation(asset: sharedAsset, goal: goalB, amount: 40)
            context.insert(allocationB)
            context.insert(AllocationHistory(asset: sharedAsset, goal: goalA, amount: allocationA.amountValue, timestamp: reallocDate))
            context.insert(AllocationHistory(asset: sharedAsset, goal: goalB, amount: allocationB.amountValue, timestamp: reallocDate))

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
            guard (try executionService.getCurrentMonthRecord()) != nil else {
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

            // Reallocate an extra 20 from A to B by adjusting allocation targets.
            let allocations = asset.allocations
            guard let allocA = allocations.first(where: { $0.goal?.id == goalA.id }) else { return }
            let allocB = allocations.first(where: { $0.goal?.id == goalB.id }) ?? AssetAllocation(asset: asset, goal: goalB, amount: 0)
            if allocB.goal == nil { context.insert(allocB) }
            allocA.updateAmount(max(0, allocA.amountValue - 20))
            allocB.updateAmount(allocB.amountValue + 20)
            let ts = Date()
            context.insert(AllocationHistory(asset: asset, goal: goalA, amount: allocA.amountValue, timestamp: ts))
            context.insert(AllocationHistory(asset: asset, goal: goalB, amount: allocB.amountValue, timestamp: ts))

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
                let execRecords = try context.fetch(FetchDescriptor<MonthlyExecutionRecord>())
                let snapshots = try context.fetch(FetchDescriptor<ExecutionSnapshot>())
                let plans = try context.fetch(FetchDescriptor<MonthlyPlan>())
                let allocationHistories = try context.fetch(FetchDescriptor<AllocationHistory>())
                let allocations = try context.fetch(FetchDescriptor<AssetAllocation>())
                let transactions = try context.fetch(FetchDescriptor<Transaction>())
                let assets = try context.fetch(FetchDescriptor<Asset>())
                let goals = try context.fetch(FetchDescriptor<Goal>())

                (completedExecutions as [any PersistentModel]).forEach { context.delete($0) }
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
            let environment = ProcessInfo.processInfo.environment
            let isXCTestRun = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            let captureMode = environment["VISUAL_CAPTURE_MODE"]?.lowercased()
            let productionFlow = environment["VISUAL_PRODUCTION_FLOW"]
            let productionState = environment["VISUAL_PRODUCTION_STATE"]
            let captureComponent = environment["VISUAL_CAPTURE_COMPONENT"]
            let captureState = environment["VISUAL_CAPTURE_STATE"]
            UITestBootstrapView {
                // Keep the app headless only for unit/integration tests.
                // UI tests rely on UITEST_* launch arguments and need real UI rendered.
                if isXCTestRun && !UITestFlags.isEnabled {
                    Color.clear
                } else if captureMode == "production", let productionFlow {
                    VisualProductionCaptureView(flow: productionFlow, state: productionState ?? "default")
                } else if let captureComponent, let captureState {
                    VisualStateCaptureView(component: captureComponent, state: captureState)
                } else if args.contains("UITEST_PRESENTATION_FLOW") {
                    ContentView()
                } else if args.contains("UITEST_SEED_SHARED_ASSET")
                    || args.contains("UITEST_SEED_BUDGET_SHORTFALL")
                    || args.contains("UITEST_SEED_MANY_GOALS")
                {
                    MonthlyPlanningContainer()
                } else if args.contains("UITEST_UI_FLOW") {
                    ContentView()
                } else {
                    OnboardingContentView()
                }
            }
        }
        .modelContainer(persistenceController.activeContainer)
        #if os(macOS)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 700)
        #endif

        #if os(macOS)
        // Additional window for goal comparison
        WindowGroup("Goal Comparison", id: "goal-comparison") {
            GoalComparisonView()
        }
        .modelContainer(persistenceController.activeContainer)
        .defaultSize(width: 1200, height: 800)

        // Settings window
        WindowGroup("Settings", id: "settings") {
            SettingsView()
        }
        .modelContainer(persistenceController.activeContainer)
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 400)
        #endif
    }
    
}

private enum VisualCaptureState: String {
    case `default`
    case pressed
    case disabled
    case error
    case loading
    case empty
    case stale
    case recovery
}

private struct VisualStateCaptureView: View {
    let component: String
    let state: VisualCaptureState

    init(component: String, state: String) {
        self.component = component
        self.state = VisualCaptureState(rawValue: state) ?? .default
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Visual State Capture")
                .font(.title2)
                .fontWeight(.bold)
            Text("\(component) • \(state.rawValue)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("CAPTURE:\(component):\(state.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)

            componentCard
                .opacity(state == .disabled ? 0.45 : 1)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(canvasBackground)
    }

    @ViewBuilder
    private var componentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch component {
            case "planning.header_card":
                Text("Monthly Planning")
                    .font(.headline)
                Text("Required: 1,250 USD")
                    .font(.subheadline)
            case "planning.goal_row":
                Text("Emergency Fund")
                    .font(.headline)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                        RoundedRectangle(cornerRadius: 6)
                            .fill(stateTint)
                            .frame(width: geo.size.width * 0.62)
                    }
                }
                .frame(height: 8)
            case "dashboard.summary_card":
                Text("Projected Progress")
                    .font(.headline)
                HStack(spacing: 16) {
                    metric("63%", "This month")
                    metric("1", "At risk goals")
                }
            case "settings.section_row":
                HStack {
                    Circle()
                        .fill(stateTint)
                        .frame(width: 10, height: 10)
                    Text("Budget Notifications")
                        .font(.body)
                    Spacer()
                    Text("Enabled")
                        .foregroundStyle(.secondary)
                }
            default:
                Text(component)
                    .font(.headline)
            }

            stateFooter
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var stateFooter: some View {
        switch state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading latest values")
                    .font(.caption)
            }
        case .empty:
            Text("No items available")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .stale:
            Text("Data may be stale")
                .font(.caption)
                .foregroundStyle(AccessibleColors.warning)
                .fontWeight(.semibold)
        case .error:
            Text("Action required")
                .font(.caption)
                .foregroundStyle(AccessibleColors.error)
                .fontWeight(.semibold)
        case .recovery:
            Text("Recovered successfully")
                .font(.caption)
                .foregroundStyle(AccessibleColors.success)
                .fontWeight(.semibold)
        default:
            Text("State: \(state.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stateTint: Color {
        switch state {
        case .error:
            return AccessibleColors.error
        case .stale:
            return AccessibleColors.warning
        case .recovery:
            return AccessibleColors.success
        case .pressed, .loading, .default:
            return AccessibleColors.primaryInteractive
        case .disabled:
            return AccessibleColors.disabled
        case .empty:
            return AccessibleColors.tertiaryText
        }
    }

    private var canvasBackground: Color {
        #if os(macOS)
        Color(NSColor.windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    private var cardBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }
}

private enum VisualProductionFlow: String {
    case planning
    case dashboard
    case settings
}

private enum VisualProductionState: String {
    case `default`
    case error
    case recovery
}

private struct VisualProductionCaptureView: View {
    let flow: VisualProductionFlow
    let state: VisualProductionState

    init(flow: String, state: String) {
        self.flow = VisualProductionFlow(rawValue: flow) ?? .planning
        self.state = VisualProductionState(rawValue: state) ?? .default
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            flowContent
            Text("PRODUCTION_CAPTURE:\(flow.rawValue):\(state.rawValue)")
                .font(.caption2.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(12)
        }
        .task {
            OnboardingManager.shared.completeOnboarding()
        }
    }

    @ViewBuilder
    private var flowContent: some View {
        switch flow {
        case .planning:
            MonthlyPlanningContainer()
        case .dashboard:
            DashboardView()
        case .settings:
            SettingsView()
        }
    }
}
