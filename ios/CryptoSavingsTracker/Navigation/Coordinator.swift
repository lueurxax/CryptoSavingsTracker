//
//  Coordinator.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 11/08/2025.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

/// Protocol defining the base coordinator interface
protocol Coordinator: AnyObject, ObservableObject {
    associatedtype Route
    
    var navigationPath: NavigationPath { get set }
    var presentedSheet: Route? { get set }
    var presentedFullScreen: Route? { get set }
    
    func navigate(to route: Route)
    func present(_ route: Route, style: PresentationStyle)
    func dismiss()
    func popToRoot()
}

/// Presentation styles for navigation
enum PresentationStyle {
    case sheet
    case fullScreen
    case push
}

/// Base implementation of Coordinator
class BaseCoordinator<Route: Hashable>: ObservableObject, Coordinator {
    @Published var navigationPath = NavigationPath()
    @Published var presentedSheet: Route?
    @Published var presentedFullScreen: Route?
    
    func navigate(to route: Route) {
        navigationPath.append(route)
    }
    
    func present(_ route: Route, style: PresentationStyle) {
        switch style {
        case .sheet:
            presentedSheet = route
        case .fullScreen:
            presentedFullScreen = route
        case .push:
            navigate(to: route)
        }
    }
    
    func dismiss() {
        if presentedSheet != nil {
            presentedSheet = nil
        } else if presentedFullScreen != nil {
            presentedFullScreen = nil
        } else if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }
    
    func popToRoot() {
        navigationPath = NavigationPath()
    }
    
    deinit {
        // Explicit deinit to avoid compiler crash
    }
}

// MARK: - Main App Coordinator
@MainActor
final class AppCoordinator: BaseCoordinator<AppRoute> {
    static let shared = AppCoordinator()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Child Coordinators
    lazy var goalCoordinator = GoalCoordinator()
    lazy var settingsCoordinator = SettingsCoordinator()
    lazy var dashboardCoordinator = DashboardCoordinator()
    
    // MARK: - Navigation Methods
    func showGoalDetail(_ goal: Goal) {
        navigate(to: .goalDetail(goal))
    }
    
    func showCreateGoal() {
        present(.createGoal, style: .sheet)
    }
    
    func showEditGoal(_ goal: Goal) {
        present(.editGoal(goal), style: .sheet)
    }
    
    func showSettings() {
        present(.settings, style: .sheet)
    }
    
    func showDashboard() {
        navigate(to: .dashboard)
    }
    
    func showAssetDetail(_ asset: Asset) {
        navigate(to: .assetDetail(asset))
    }
    
    func showTransactionHistory(for asset: Asset) {
        navigate(to: .transactionHistory(asset))
    }
    
    func showMonthlyPlanning() {
        navigate(to: .monthlyPlanning)
    }
}

// MARK: - App Routes
enum AppRoute: Hashable, Identifiable {
    case dashboard
    case goalsList
    case goalDetail(Goal)
    case createGoal
    case editGoal(Goal)
    case assetDetail(Asset)
    case transactionHistory(Asset)
    case settings
    case monthlyPlanning
    case monthlyPlanningSettings
    case flexAdjustment
    
    var id: String {
        switch self {
        case .dashboard: return "dashboard"
        case .goalsList: return "goalsList"
        case .goalDetail(let goal): return "goalDetail-\(goal.id)"
        case .createGoal: return "createGoal"
        case .editGoal(let goal): return "editGoal-\(goal.id)"
        case .assetDetail(let asset): return "assetDetail-\(asset.id)"
        case .transactionHistory(let asset): return "transactionHistory-\(asset.id)"
        case .settings: return "settings"
        case .monthlyPlanning: return "monthlyPlanning"
        case .monthlyPlanningSettings: return "monthlyPlanningSettings"
        case .flexAdjustment: return "flexAdjustment"
        }
    }
}

// MARK: - Goal Coordinator
@MainActor
final class GoalCoordinator: BaseCoordinator<GoalRoute> {
    
    func showGoalDetail(_ goal: Goal) {
        navigate(to: .detail(goal))
    }
    
    func showEditGoal(_ goal: Goal) {
        present(.edit(goal), style: .sheet)
    }
    
    func showCreateGoal() {
        present(.create, style: .sheet)
    }
    
    func showAssetManagement(for goal: Goal) {
        navigate(to: .assetManagement(goal))
    }
    
    func showAddAsset(to goal: Goal) {
        present(.addAsset(goal), style: .sheet)
    }
    
    func showEditAsset(_ asset: Asset) {
        present(.editAsset(asset), style: .sheet)
    }
    
    func showTransactionHistory(for asset: Asset) {
        navigate(to: .transactionHistory(asset))
    }
    
    func showAddTransaction(to asset: Asset) {
        present(.addTransaction(asset), style: .sheet)
    }
}

// MARK: - Goal Routes
enum GoalRoute: Hashable {
    case list
    case detail(Goal)
    case create
    case edit(Goal)
    case assetManagement(Goal)
    case addAsset(Goal)
    case editAsset(Asset)
    case transactionHistory(Asset)
    case addTransaction(Asset)
}

// MARK: - Settings Coordinator
@MainActor
final class SettingsCoordinator: BaseCoordinator<SettingsRoute> {
    
    func showGeneralSettings() {
        navigate(to: .general)
    }
    
    func showNotificationSettings() {
        navigate(to: .notifications)
    }
    
    func showMonthlyPlanningSettings() {
        navigate(to: .monthlyPlanning)
    }
    
    func showAPISettings() {
        navigate(to: .apiKeys)
    }
    
    func showAbout() {
        navigate(to: .about)
    }
    
    func showDebugInfo() {
        navigate(to: .debug)
    }
}

// MARK: - Settings Routes
enum SettingsRoute: Hashable {
    case main
    case general
    case notifications
    case monthlyPlanning
    case apiKeys
    case about
    case debug
    case exportData
    case importData
}

// MARK: - Dashboard Coordinator
@MainActor
final class DashboardCoordinator: BaseCoordinator<DashboardRoute> {
    
    func showMonthlyPlanning() {
        navigate(to: .monthlyPlanning)
    }
    
    func showFlexAdjustment() {
        present(.flexAdjustment, style: .sheet)
    }
    
    func showGoalQuickView(_ goal: Goal) {
        present(.goalQuickView(goal), style: .sheet)
    }
    
    func showPortfolioAnalysis() {
        navigate(to: .portfolioAnalysis)
    }
    
    func showPerformanceMetrics() {
        navigate(to: .performanceMetrics)
    }
}

// MARK: - Dashboard Routes
enum DashboardRoute: Hashable {
    case main
    case monthlyPlanning
    case flexAdjustment
    case goalQuickView(Goal)
    case portfolioAnalysis
    case performanceMetrics
    case alerts
}

// MARK: - Environment Key for Coordinator
struct CoordinatorKey: EnvironmentKey {
    static let defaultValue = AppCoordinator.shared
}

extension EnvironmentValues {
    var coordinator: AppCoordinator {
        get { self[CoordinatorKey.self] }
        set { self[CoordinatorKey.self] = newValue }
    }
}

// MARK: - Navigation View Modifier
struct NavigationCoordinatorModifier: ViewModifier {
    @ObservedObject var coordinator: AppCoordinator
    
    func body(content: Content) -> some View {
        NavigationStack(path: $coordinator.navigationPath) {
            content
                .navigationDestination(for: AppRoute.self) { route in
                    destinationView(for: route)
                }
        }
        .sheet(item: $coordinator.presentedSheet) { route in
            sheetView(for: route)
        }
        #if os(iOS)
        .fullScreenCover(item: $coordinator.presentedFullScreen) { route in
            fullScreenView(for: route)
        }
        #endif
    }
    
    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        switch route {
        case .dashboard:
            DashboardView()
        case .goalsList:
            GoalsListView()
        case .goalDetail(let goal):
            GoalDetailView(goal: goal)
        case .assetDetail(let asset):
            AssetDetailView(asset: asset)
        case .transactionHistory(let asset):
            TransactionHistoryView(asset: asset)
        case .monthlyPlanning:
            MonthlyPlanningContainer()
        default:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func sheetView(for route: AppRoute) -> some View {
        switch route {
        case .createGoal:
            CreateGoalWrapper()
        case .editGoal(let goal):
            EditGoalWrapper(goal: goal)
        case .settings:
            SettingsView()
        case .monthlyPlanningSettings:
            MonthlyPlanningSettingsView(goals: [])
        case .flexAdjustment:
            FlexAdjustmentView()
        default:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func fullScreenView(for route: AppRoute) -> some View {
        switch route {
        default:
            EmptyView()
        }
    }
}

// MARK: - View Extension for Easy Use
extension View {
    func withNavigationCoordinator() -> some View {
        self.modifier(NavigationCoordinatorModifier(coordinator: AppCoordinator.shared))
            .environmentObject(AppCoordinator.shared)
    }
}

// MARK: - Wrapper Views for EditGoalView
struct CreateGoalWrapper: View {
    @Environment(\.modelContext) private var modelContext
    @State private var newGoal: Goal
    
    init() {
        let goal = Goal(
            name: "",
            currency: "USD",
            targetAmount: 1000,
            deadline: Date().addingTimeInterval(86400 * 90), // 90 days from now
            startDate: Date()
        )
        self._newGoal = State(initialValue: goal)
    }
    
    var body: some View {
        EditGoalView(goal: newGoal, modelContext: modelContext)
            .onAppear {
                // Insert the new goal into context
                modelContext.insert(newGoal)
            }
    }
}

struct EditGoalWrapper: View {
    let goal: Goal
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        EditGoalView(goal: goal, modelContext: modelContext)
    }
}