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

#if DEBUG
enum UITestFinishedSettlementFixtureTimeline {
    static let transactionDate = Date(timeIntervalSince1970: 1_750_000_000)
    static let completedAt = Date(timeIntervalSince1970: 1_780_000_000)
}
#endif

@main
struct CryptoSavingsTrackerApp: App {
    static let previewModelContainer: ModelContainer = PersistenceStackFactory.makePreviewContainer()

    private let bootstrapPlan: AppBootstrapPlan
    @StateObject private var persistenceController: PersistenceController

    init() {
        let bootstrapPlan = BootstrapPolicyResolver.resolve()
        self.bootstrapPlan = bootstrapPlan
        bootstrapPlan.testHarnessPlan.applyLaunchDefaults()
        bootstrapPlan.persistenceBootstrap.run()
        assert(
            !bootstrapPlan.platformBridgePlan.shouldEnableAppDelegateBridge,
            "BootstrapPolicyResolver must stay aligned with the removed app-root delegate bridge seam."
        )
        _persistenceController = StateObject(wrappedValue: PersistenceController.shared)

        // Suppress haptic feedback warnings in iOS Simulator
        #if targetEnvironment(simulator) && os(iOS)
        // Disable haptic feedback system in simulator to prevent CHHapticPattern warnings
        // These warnings are harmless but create console noise during development
        if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
            // Running in iOS Simulator - haptics don't work anyway
        }
        #endif

        Task {
            await bootstrapPlan.monitoringPlan.startIfNeeded(throttler: StartupThrottler.shared) {
                DIContainer.shared.cloudKitHealthMonitor.startMonitoring()
            }
        }
    }

    // MARK: - UI Test Seeding

#if DEBUG
    private static var didRunUITestSeed = false

    /// Seed deterministic data for UI tests: two goals, shared asset, plans, start execution,
    /// and record a deposit + reallocation to surface shared-asset sync issues.
    @MainActor
    static func runUITestSeedIfNeeded(context: ModelContext) async {
        guard !didRunUITestSeed else { return }
        let shouldSeedGoalsOnly = UITestFlags.shouldSeedGoals
        let shouldSeedManyGoals = UITestFlags.shouldSeedManyGoals
        let shouldSeedFinishedSettlements = UITestFlags.shouldSeedFinishedSettlements
        guard shouldSeedGoalsOnly || shouldSeedManyGoals || shouldSeedFinishedSettlements else { return }
        didRunUITestSeed = true

        OnboardingManager.shared.completeOnboarding()

        if shouldSeedGoalsOnly {
            await seedUITestGoals(context: context, count: 1)
        }

        if shouldSeedManyGoals {
            await seedUITestGoals(context: context, count: 18)
        }

        if shouldSeedFinishedSettlements {
            await seedUITestFinishedSettlements(context: context)
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
    private static func seedUITestFinishedSettlements(context: ModelContext) async {
        do {
            let expectedNames: Set<String> = [
                "Manual Finish Goal",
                "On-chain Finish Goal",
                "Mixed Finish Goal",
                "Legacy Finished Goal",
                "Legacy Review Host"
            ]
            let existingNames = Set(try context.fetch(FetchDescriptor<Goal>()).map(\.name))
            guard expectedNames.isSubset(of: existingNames) == false else { return }

            let deadline = Date(timeIntervalSince1970: 2_000_000_000)
            let completedAt = UITestFinishedSettlementFixtureTimeline.completedAt
            let transactionDate = UITestFinishedSettlementFixtureTimeline.transactionDate

            let manualGoal = Goal(
                name: "Manual Finish Goal",
                currency: "USD",
                targetAmount: 400,
                deadline: deadline
            )
            let onChainGoal = Goal(
                name: "On-chain Finish Goal",
                currency: "USD",
                targetAmount: 250,
                deadline: deadline
            )
            let mixedGoal = Goal(
                name: "Mixed Finish Goal",
                currency: "USD",
                targetAmount: 175,
                deadline: deadline
            )
            let legacyGoal = Goal(
                name: "Legacy Finished Goal",
                currency: "USD",
                targetAmount: 500,
                deadline: deadline
            )
            legacyGoal.markFinished(at: completedAt)
            let legacyReviewHost = Goal(
                name: "Legacy Review Host",
                currency: "USD",
                targetAmount: 1_000,
                deadline: deadline
            )

            let manualAsset = Asset(currency: "USD")
            let manualTransaction = Transaction(
                amount: 1_000,
                asset: manualAsset,
                date: transactionDate,
                source: .manual
            )
            manualAsset.transactions = [manualTransaction]
            let manualAllocation = AssetAllocation(asset: manualAsset, goal: manualGoal, amount: 400)
            manualAsset.allocations = [manualAllocation]
            manualGoal.allocations = [manualAllocation]

            let onChainAsset = Asset(
                currency: "USDT",
                address: "0x0000000000000000000000000000000000000001",
                chainId: "ethereum"
            )
            let onChainAllocation = AssetAllocation(asset: onChainAsset, goal: onChainGoal, amount: 250)
            onChainAsset.allocations = [onChainAllocation]
            onChainGoal.allocations = [onChainAllocation]

            let mixedAsset = Asset(
                currency: "USDT",
                address: "0x0000000000000000000000000000000000000002",
                chainId: "ethereum"
            )
            let mixedTransaction = Transaction(
                amount: 25,
                asset: mixedAsset,
                date: transactionDate,
                source: .manual
            )
            mixedAsset.transactions = [mixedTransaction]
            let mixedAllocation = AssetAllocation(asset: mixedAsset, goal: mixedGoal, amount: 175)
            mixedAsset.allocations = [mixedAllocation]
            mixedGoal.allocations = [mixedAllocation]

            let legacyUSDT = Asset(
                currency: "USDT",
                address: "0x0000000000000000000000000000000000000003",
                chainId: "ethereum"
            )
            let legacyBTC = Asset(
                currency: "BTC",
                address: "bc1qfinishedsettlementfixture",
                chainId: "bitcoin"
            )
            let legacyUSDTAllocation = AssetAllocation(asset: legacyUSDT, goal: legacyGoal, amount: 200)
            let legacyBTCAllocation = AssetAllocation(asset: legacyBTC, goal: legacyGoal, amount: 0.01)
            let hostUSDTAllocation = AssetAllocation(asset: legacyUSDT, goal: legacyReviewHost, amount: 50)
            legacyUSDT.allocations = [legacyUSDTAllocation, hostUSDTAllocation]
            legacyBTC.allocations = [legacyBTCAllocation]
            legacyGoal.allocations = [legacyUSDTAllocation, legacyBTCAllocation]
            legacyReviewHost.allocations = [hostUSDTAllocation]

            [manualGoal, onChainGoal, mixedGoal, legacyGoal, legacyReviewHost].forEach(context.insert)
            [manualAsset, onChainAsset, mixedAsset, legacyUSDT, legacyBTC].forEach(context.insert)
            [manualTransaction, mixedTransaction].forEach(context.insert)
            [
                manualAllocation,
                onChainAllocation,
                mixedAllocation,
                legacyUSDTAllocation,
                legacyBTCAllocation,
                hostUSDTAllocation
            ].forEach(context.insert)

            try context.save()
            AppLog.info("UITest finished settlement seed complete", category: .ui)
        } catch {
            AppLog.error("UITest finished settlement seed failed: \(error)", category: .ui)
        }
    }

    // MARK: - UITest reset

    private static var didRunUITestReset = false
    @MainActor
    static func runUITestResetIfNeeded(context: ModelContext) async {
        guard !didRunUITestReset else { return }
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("UITEST_RESET_DATA") else { return }
        didRunUITestReset = true

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
            if UITestFlags.shouldForceOnboarding {
                OnboardingManager.shared.startOnboarding()
            } else {
                OnboardingManager.shared.completeOnboarding()
            }
            UserDefaults.standard.set("ui-test-owner", forKey: "familyShare.ownerID")
            UserDefaults.standard.set("ui-test-household", forKey: "familyShare.shareID")
            UserDefaults.standard.set("UI Test Owner", forKey: "familyShare.ownerName")
            await DIContainer.shared.familyShareAcceptanceCoordinator.resetAllNamespaces()

            if UITestFlags.shouldSeedFinishedSettlements {
                await runUITestSeedIfNeeded(context: context)
            }
            AppLog.info("UITEST_RESET_DATA cleared all entities", category: .ui)
        } catch {
            AppLog.error("UITEST_RESET_DATA failed: \(error)", category: .ui)
        }
    }
#endif

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            AppAppearanceHost {
                UITestBootstrapView(plan: bootstrapPlan.testHarnessPlan) {
                    rootContent
                }
            }
            #else
            AppAppearanceHost {
                rootContent
            }
            #endif
        }
        .modelContainer(persistenceController.activeContainer)
        #if os(macOS)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 700)
        #endif

        #if os(macOS)
        // Settings window
        WindowGroup("Settings", id: "settings") {
            SettingsView()
        }
        .modelContainer(persistenceController.activeContainer)
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 400)
        #endif
    }

    @ViewBuilder
    private var rootContent: some View {
        if case .headless = bootstrapPlan.rootShellPlan.destination {
            Color.clear
        } else {
            switch bootstrapPlan.visualCapturePlan.destination {
            case .none:
                switch bootstrapPlan.rootShellPlan.destination {
                case .headless:
                    Color.clear
                case .content:
                    ContentView()
                case .onboarding:
                    OnboardingContentView()
                }
            case .production(let flow, let state):
                VisualProductionCaptureView(flow: flow, state: state)
            case .component(let component, let state):
                VisualStateCaptureView(component: component, state: state)
            }
        }
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
        self.flow = VisualProductionFlow(rawValue: flow) ?? .dashboard
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
        case .dashboard:
            DashboardView()
        case .settings:
            SettingsView()
        }
    }
}
