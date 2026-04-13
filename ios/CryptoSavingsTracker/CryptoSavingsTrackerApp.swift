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

    @StateObject private var persistenceController: PersistenceController
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegateRouter.self) private var appDelegateRouter
    #endif

    init() {
        if UITestFlags.isEnabled {
            UserDefaults.standard.set("ui-test-owner", forKey: "familyShare.ownerID")
            UserDefaults.standard.set("ui-test-household", forKey: "familyShare.shareID")
            UserDefaults.standard.set("UI Test Owner", forKey: "familyShare.ownerName")
        }
        // Clean up any cloud-backed store files left by a retired cutover attempt.
        // Must run before any cloud-backed ModelContainer is opened.
        PersistenceController.performDeferredCloudStoreCleanupIfNeeded()
        // Phase 1.5 hard cutover: retired local-primary store files are removed on launch.
        PersistenceController.performLegacyLocalStoreCleanupIfNeeded()
        _persistenceController = StateObject(wrappedValue: PersistenceController.shared)

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
            let environment = ProcessInfo.processInfo.environment
            let isXCTestRun = environment["XCTestConfigurationFilePath"] != nil
            let isUITestRun = args.contains(where: { $0.hasPrefix("UITEST") })
            let isPreviewRun = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            let isTestRun = isXCTestRun || isUITestRun || isPreviewRun

            if !isTestRun {
                await MainActor.run {
                    DIContainer.shared.cloudKitHealthMonitor.startMonitoring()
                }
            }
        }
    }

    // MARK: - UI Test Seeding

    private static var didRunUITestSeed = false

    /// Seed deterministic data for UI tests: two goals, shared asset, plans, start execution,
    /// and record a deposit + reallocation to surface shared-asset sync issues.
    @MainActor
    static func runUITestSeedIfNeeded(context: ModelContext) async {
        guard !didRunUITestSeed else { return }
        let shouldSeedGoalsOnly = UITestFlags.shouldSeedGoals
        let shouldSeedManyGoals = UITestFlags.shouldSeedManyGoals
        guard shouldSeedGoalsOnly || shouldSeedManyGoals else { return }
        didRunUITestSeed = true

        OnboardingManager.shared.completeOnboarding()

        if shouldSeedGoalsOnly {
            await seedUITestGoals(context: context, count: 1)
        }

        if shouldSeedManyGoals {
            await seedUITestGoals(context: context, count: 18)
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
            OnboardingManager.shared.completeOnboarding()
            UserDefaults.standard.set("ui-test-owner", forKey: "familyShare.ownerID")
            UserDefaults.standard.set("ui-test-household", forKey: "familyShare.shareID")
            UserDefaults.standard.set("UI Test Owner", forKey: "familyShare.ownerName")
            await DIContainer.shared.familyShareAcceptanceCoordinator.resetAllNamespaces()
            AppLog.info("UITEST_RESET_DATA cleared all entities", category: .ui)
        } catch {
            AppLog.error("UITEST_RESET_DATA failed: \(error)", category: .ui)
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
                } else if args.contains("UITEST_SEED_MANY_GOALS")
                    || args.contains("UITEST_SEED_GOALS")
                    || args.contains("UITEST_UI_FLOW")
                {
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

#if os(iOS)
final class AppDelegateRouter: NSObject, UIApplicationDelegate {}
#endif
