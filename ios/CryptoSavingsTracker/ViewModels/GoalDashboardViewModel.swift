//
//  GoalDashboardViewModel.swift
//  CryptoSavingsTracker
//

import Foundation
import SwiftData
import Combine

@MainActor
final class GoalDashboardViewModel: ObservableObject {
    @Published private(set) var sceneModel: GoalDashboardSceneModel?
    @Published private(set) var isRefreshing = false

    private let dashboardViewModel: DashboardViewModel
    private let assembler: GoalDashboardSceneAssembler

    private var goal: Goal?
    private var modelContext: ModelContext?
    private var lastSuccessfulRefreshAt: Date?
    private var legacyWidgetMigration = GoalDashboardLegacyWidgetMigrationResult(
        utilityActionOrder: GoalDashboardContract.defaultUtilityActionOrder,
        applied: false,
        resetToDefaultPreset: false
    )
    private var cancellables = Set<AnyCancellable>()

    init(
        dashboardViewModel: DashboardViewModel? = nil,
        assembler: GoalDashboardSceneAssembler? = nil
    ) {
        self.dashboardViewModel = dashboardViewModel ?? DIContainer.shared.makeDashboardViewModel()
        self.assembler = assembler ?? GoalDashboardSceneAssembler()
        observeDashboardState()
    }

    func configure(goal: Goal, modelContext: ModelContext, legacyWidgetsJSON: String) {
        self.goal = goal
        self.modelContext = modelContext
        legacyWidgetMigration = GoalDashboardLegacyWidgetMigration.migrate(widgetsJSON: legacyWidgetsJSON)
        rebuildScene()
    }

    func load() async {
        guard let goal, let modelContext else { return }
        isRefreshing = true
        await dashboardViewModel.loadData(for: goal, modelContext: modelContext)
        if !hasHardError {
            lastSuccessfulRefreshAt = Date()
        }
        rebuildScene()
        isRefreshing = false
    }

    func reloadLegacyWidgets(widgetsJSON: String) {
        legacyWidgetMigration = GoalDashboardLegacyWidgetMigration.migrate(widgetsJSON: widgetsJSON)
        rebuildScene()
    }

    private var hasHardError: Bool {
        let states: [ChartLoadingState] = [
            dashboardViewModel.balanceHistoryState,
            dashboardViewModel.assetCompositionState,
            dashboardViewModel.forecastState,
            dashboardViewModel.heatmapState
        ]
        return states.contains { state in
            if case .error = state { return true }
            return false
        }
    }

    private func observeDashboardState() {
        dashboardViewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.rebuildScene()
                }
            }
            .store(in: &cancellables)
    }

    private func rebuildScene() {
        guard let goal else { return }
        sceneModel = assembler.assemble(
            goal: goal,
            dashboardViewModel: dashboardViewModel,
            generatedAt: Date(),
            lastSuccessfulRefreshAt: lastSuccessfulRefreshAt,
            legacyWidgetMigration: legacyWidgetMigration
        )
    }
}
