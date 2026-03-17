//
//  GoalDashboardSceneAssembler.swift
//  CryptoSavingsTracker
//
//  Builds GoalDashboardSceneModel from goal and dashboard data.
//

import Foundation

@MainActor
struct GoalDashboardSceneAssembler {
    func assemble(
        goal: Goal,
        dashboardViewModel: DashboardViewModel,
        generatedAt: Date = Date(),
        lastSuccessfulRefreshAt: Date?,
        legacyWidgetMigration: GoalDashboardLegacyWidgetMigrationResult? = nil
    ) -> GoalDashboardSceneModel {
        let migration = legacyWidgetMigration ?? GoalDashboardLegacyWidgetMigrationResult(
            utilityActionOrder: GoalDashboardContract.defaultUtilityActionOrder,
            applied: false,
            resetToDefaultPreset: false
        )
        let lifecycle = GoalDashboardLifecycleState(goalLifecycleStatus: goal.lifecycleStatus)
        let freshness = resolveFreshness(for: dashboardViewModel, generatedAt: generatedAt)

        let forecastSlice = buildForecastRiskSlice(
            goal: goal,
            dashboardViewModel: dashboardViewModel,
            freshness: freshness,
            generatedAt: generatedAt
        )
        let activitySlice = buildContributionActivitySlice(
            goal: goal,
            dashboardViewModel: dashboardViewModel,
            freshness: freshness.state
        )
        let allocationSlice = buildAllocationHealthSlice(goal: goal, freshness: freshness.state)
        let snapshotSlice = buildSnapshotSlice(
            goal: goal,
            forecast: forecastSlice,
            freshness: freshness
        )

        let resolver = GoalDashboardNextActionResolver()
        let nextAction = resolver.resolve(
            lifecycle: lifecycle,
            freshness: freshness.state,
            hasAssets: !goal.allocatedAssets.isEmpty,
            hasContributionsThisMonth: activitySlice.monthContributionSum > 0,
            forecastStatus: forecastSlice.status,
            forecastConfidence: forecastSlice.confidence,
            overAllocated: allocationSlice.overAllocated,
            lastSuccessfulRefreshAt: lastSuccessfulRefreshAt,
            reasonCode: freshness.reasonCode
        )

        let allActions = [
            DashboardAction(
                id: "add_asset",
                title: "Add Asset",
                copyKey: "dashboard.utilities.addAsset",
                systemImage: "plus.circle.fill"
            ),
            DashboardAction(
                id: "add_contribution",
                title: "Add Contribution",
                copyKey: "dashboard.utilities.addContribution",
                systemImage: "arrow.down.circle.fill"
            ),
            DashboardAction(
                id: "edit_goal",
                title: "Edit Goal",
                copyKey: "dashboard.utilities.editGoal",
                systemImage: "pencil.circle.fill"
            ),
            DashboardAction(
                id: "view_history",
                title: "View History",
                copyKey: "dashboard.utilities.viewHistory",
                systemImage: "clock.arrow.circlepath"
            )
        ]
        let actionsByID = Dictionary(uniqueKeysWithValues: allActions.map { ($0.id, $0) })
        let orderedActions = migration.utilityActionOrder.compactMap { actionsByID[$0] }
        let utilitiesState: GoalDashboardModuleState
        switch freshness.state {
        case .hardError:
            utilitiesState = .error
        case .stale:
            utilitiesState = .stale
        case .fresh:
            utilitiesState = .ready
        }

        let utilities = UtilitiesSlice(
            moduleState: utilitiesState,
            actions: orderedActions,
            legacyWidgetPrefsApplied: migration.applied || migration.resetToDefaultPreset
        )

        return GoalDashboardSceneModel(
            goalId: goal.id,
            goalLifecycle: lifecycle,
            currency: goal.currency,
            generatedAt: generatedAt,
            freshness: freshness.state,
            freshnessUpdatedAt: freshness.updatedAt,
            freshnessReason: freshness.reasonCode,
            snapshot: snapshotSlice,
            nextAction: nextAction,
            forecastRisk: forecastSlice,
            contributionActivity: activitySlice,
            allocationHealth: allocationSlice,
            utilities: utilities,
            telemetryContext: DashboardTelemetryContext(
                source: "goal_dashboard_screen",
                generatedAt: generatedAt
            )
        )
    }

    private func resolveFreshness(for viewModel: DashboardViewModel, generatedAt: Date) -> FreshnessResult {
        let chartErrorState = firstChartErrorState(from: viewModel)
        if let chartErrorState {
            return FreshnessResult(
                state: .hardError,
                updatedAt: chartErrorState.timestamp,
                reasonCode: sanitizeReason(chartErrorState.error.localizedDescription)
            )
        }

        guard let lastBalanceDate = viewModel.balanceHistory.last?.date else {
            return FreshnessResult(
                state: .stale,
                updatedAt: generatedAt,
                reasonCode: "no_balance_history"
            )
        }

        let ageSeconds = generatedAt.timeIntervalSince(lastBalanceDate)
        if ageSeconds > 60 * 60 * 24 * 3 {
            return FreshnessResult(
                state: .stale,
                updatedAt: generatedAt,
                reasonCode: "stale_balance_history"
            )
        }

        return FreshnessResult(state: .fresh, updatedAt: generatedAt, reasonCode: nil)
    }

    private func firstChartErrorState(from viewModel: DashboardViewModel) -> ChartErrorState? {
        let states: [ChartLoadingState] = [
            viewModel.balanceHistoryState,
            viewModel.assetCompositionState,
            viewModel.forecastState,
            viewModel.heatmapState
        ]
        for state in states {
            if case .error(let errorState) = state {
                return errorState
            }
        }
        return nil
    }

    private func buildSnapshotSlice(
        goal: Goal,
        forecast: ForecastRiskSlice,
        freshness: FreshnessResult
    ) -> SnapshotSlice {
        let currentAmount = Decimal(goal.currentTotal)
        let targetAmount = Decimal(goal.targetAmount)
        let remaining = max(targetAmount - currentAmount, 0)
        let ratio = goal.targetAmount > 0 ? goal.currentTotal / goal.targetAmount : 0

        let moduleState: GoalDashboardModuleState
        switch freshness.state {
        case .hardError:
            moduleState = .error
        case .stale:
            moduleState = .stale
        case .fresh:
            moduleState = .ready
        }

        return SnapshotSlice(
            moduleState: moduleState,
            currentAmount: currentAmount,
            targetAmount: targetAmount,
            remainingAmount: remaining,
            progressRatio: ratio,
            daysRemaining: daysRemaining(for: goal),
            status: forecast.status,
            lastUpdatedAt: freshness.updatedAt
        )
    }

    private func daysRemaining(for goal: Goal) -> Int? {
        switch goal.lifecycleStatus {
        case .finished, .deleted:
            return nil
        case .active, .cancelled:
            return goal.daysRemaining
        }
    }

    private func buildForecastRiskSlice(
        goal: Goal,
        dashboardViewModel: DashboardViewModel,
        freshness: FreshnessResult,
        generatedAt: Date
    ) -> ForecastRiskSlice {
        if dashboardViewModel.isLoadingForecast {
            return ForecastRiskSlice(
                moduleState: .loading,
                status: nil,
                assumptionWindowDays: nil,
                confidence: nil,
                updatedAt: nil,
                targetDate: goal.deadline,
                projectedAmount: nil,
                whyStatusCopyKey: nil,
                errorReasonCode: nil
            )
        }

        if case .error(let chartErrorState) = dashboardViewModel.forecastState {
            return ForecastRiskSlice(
                moduleState: .error,
                status: nil,
                assumptionWindowDays: nil,
                confidence: nil,
                updatedAt: chartErrorState.timestamp,
                targetDate: goal.deadline,
                projectedAmount: nil,
                whyStatusCopyKey: nil,
                errorReasonCode: sanitizeReason(chartErrorState.error.localizedDescription)
            )
        }

        guard let lastForecast = dashboardViewModel.forecastData.last else {
            return ForecastRiskSlice(
                moduleState: .empty,
                status: nil,
                assumptionWindowDays: nil,
                confidence: nil,
                updatedAt: freshness.updatedAt,
                targetDate: goal.deadline,
                projectedAmount: nil,
                whyStatusCopyKey: "dashboard.forecast.empty",
                errorReasonCode: nil
            )
        }

        let status: GoalDashboardRiskStatus
        if lastForecast.realistic >= goal.targetAmount {
            status = .onTrack
        } else if lastForecast.realistic >= goal.targetAmount * 0.9 {
            status = .atRisk
        } else {
            status = .offTrack
        }

        let assumptionWindowDays = estimateAssumptionWindow(from: dashboardViewModel.balanceHistory)
        let confidence = confidenceLevel(
            historyCount: dashboardViewModel.balanceHistory.count,
            forecastCount: dashboardViewModel.forecastData.count,
            assumptionWindowDays: assumptionWindowDays
        )
        let moduleState: GoalDashboardModuleState = freshness.state == .stale ? .stale : .ready

        return ForecastRiskSlice(
            moduleState: moduleState,
            status: status,
            assumptionWindowDays: assumptionWindowDays,
            confidence: confidence,
            updatedAt: freshness.updatedAt ?? generatedAt,
            targetDate: goal.deadline,
            projectedAmount: Decimal(lastForecast.realistic),
            whyStatusCopyKey: "dashboard.forecast.why.\(status.rawValue)",
            errorReasonCode: nil
        )
    }

    private func estimateAssumptionWindow(from history: [BalanceHistoryPoint]) -> Int {
        guard let first = history.first?.date, let last = history.last?.date else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
        return max(0, days)
    }

    private func confidenceLevel(historyCount: Int, forecastCount: Int, assumptionWindowDays: Int) -> GoalDashboardForecastConfidence {
        if historyCount < 4 || assumptionWindowDays < 21 {
            return .low
        }
        if historyCount < 8 || forecastCount < 4 || assumptionWindowDays < 45 {
            return .medium
        }
        return .high
    }

    private func buildContributionActivitySlice(
        goal: Goal,
        dashboardViewModel: DashboardViewModel,
        freshness: DataFreshnessState
    ) -> ContributionActivitySlice {
        if dashboardViewModel.isLoadingHeatmap {
            return ContributionActivitySlice(
                moduleState: .loading,
                monthContributionSum: 0,
                recentRows: [],
                lastContributionAt: nil
            )
        }

        let rows = dashboardViewModel.recentTransactions.map { transaction in
            ActivityRow(
                id: transaction.id,
                assetCurrency: transaction.asset?.currency ?? "Unknown",
                amount: Decimal(transaction.amount),
                date: transaction.date,
                note: transaction.comment
            )
        }

        let monthSum = monthContributionSum(for: goal)
        let state: GoalDashboardModuleState
        if freshness == .hardError {
            state = .error
        } else if freshness == .stale {
            state = .stale
        } else {
            state = rows.isEmpty ? .empty : .ready
        }

        return ContributionActivitySlice(
            moduleState: state,
            monthContributionSum: monthSum,
            recentRows: rows,
            lastContributionAt: rows.first?.date
        )
    }

    private func monthContributionSum(for goal: Goal) -> Decimal {
        let calendar = Calendar.current
        let monthRange = calendar.dateInterval(of: .month, for: Date())
        guard let start = monthRange?.start, let end = monthRange?.end else { return 0 }

        let transactions = goal.allocatedAssets.flatMap { $0.transactions ?? [] }
        let sum = transactions
            .filter { $0.date >= start && $0.date < end && $0.amount > 0 }
            .reduce(Decimal(0)) { partial, tx in
                let amount = Decimal(tx.amount)
                if tx.asset?.currency.uppercased() == goal.currency.uppercased() {
                    return partial + amount
                }
                return partial
            }
        return sum
    }

    private func buildAllocationHealthSlice(goal: Goal, freshness: DataFreshnessState) -> AllocationHealthSlice {
        let positiveAllocations = (goal.allocations ?? [])
            .compactMap { allocation -> (Asset, Decimal)? in
                guard let asset = allocation.asset, allocation.amountValue > 0 else {
                    return nil
                }
                return (asset, Decimal(allocation.amountValue))
            }

        let total = positiveAllocations.reduce(Decimal(0)) { $0 + $1.1 }
        let overAllocated = goal.allocatedAssets.contains(where: { $0.isOverAllocated })

        let weights: [AssetWeight] = positiveAllocations.map { (asset, amount) in
            let ratio: Double
            if total > 0 {
                let value = NSDecimalNumber(decimal: amount / total).doubleValue
                ratio = value
            } else {
                ratio = 0
            }
            return AssetWeight(
                assetId: asset.id,
                assetCurrency: asset.currency,
                amount: amount,
                weightRatio: ratio
            )
        }
            .sorted(by: { $0.weightRatio > $1.weightRatio })

        let concentration = weights.first?.weightRatio
        let warning: String?
        if overAllocated {
            warning = "dashboard.allocation.overAllocated"
        } else if let concentration, concentration >= 0.7 {
            warning = "dashboard.allocation.highConcentration"
        } else {
            warning = nil
        }

        let moduleState: GoalDashboardModuleState
        switch freshness {
        case .hardError:
            moduleState = .error
        case .stale:
            moduleState = .stale
        case .fresh:
            moduleState = weights.isEmpty ? .empty : .ready
        }

        return AllocationHealthSlice(
            moduleState: moduleState,
            overAllocated: overAllocated,
            concentrationRatio: concentration,
            topAssets: Array(weights.prefix(3)),
            warningCopyKey: warning
        )
    }

    private func sanitizeReason(_ message: String) -> String {
        message
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }
}

@MainActor
struct GoalDashboardNextActionResolver {
    func resolve(
        lifecycle: GoalDashboardLifecycleState,
        freshness: DataFreshnessState,
        hasAssets: Bool,
        hasContributionsThisMonth: Bool,
        forecastStatus: GoalDashboardRiskStatus?,
        forecastConfidence: GoalDashboardForecastConfidence?,
        overAllocated: Bool,
        lastSuccessfulRefreshAt: Date?,
        reasonCode: String?
    ) -> NextActionSlice {
        let state = resolveState(
            lifecycle: lifecycle,
            freshness: freshness,
            hasAssets: hasAssets,
            hasContributionsThisMonth: hasContributionsThisMonth,
            forecastStatus: forecastStatus,
            forecastConfidence: forecastConfidence,
            overAllocated: overAllocated
        )

        let payload = payload(for: state, lastSuccessfulRefreshAt: lastSuccessfulRefreshAt, reasonCode: reasonCode)
        let moduleState: GoalDashboardModuleState = {
            switch freshness {
            case .hardError: return .error
            case .stale: return .stale
            case .fresh: return .ready
            }
        }()
        return NextActionSlice(
            resolverState: state,
            moduleState: moduleState,
            primaryCta: payload.primary,
            secondaryCta: payload.secondary,
            reasonCopyKey: payload.reasonCopyKey,
            isBlocking: payload.isBlocking,
            diagnostics: payload.diagnostics
        )
    }

    private func resolveState(
        lifecycle: GoalDashboardLifecycleState,
        freshness: DataFreshnessState,
        hasAssets: Bool,
        hasContributionsThisMonth: Bool,
        forecastStatus: GoalDashboardRiskStatus?,
        forecastConfidence: GoalDashboardForecastConfidence?,
        overAllocated: Bool
    ) -> GoalDashboardNextActionResolverState {
        if freshness == .hardError {
            return .hardError
        }
        if lifecycle == .finished || lifecycle == .archived {
            return .goalFinishedOrArchived
        }
        if lifecycle == .paused {
            return .goalPaused
        }
        if overAllocated {
            return .overAllocated
        }
        if !hasAssets {
            return .noAssets
        }
        if !hasContributionsThisMonth {
            return .noContributions
        }
        if freshness == .stale {
            return .staleData
        }
        if forecastStatus == .offTrack {
            return .behindSchedule
        }
        // Low-confidence optimistic forecast must not produce "on track" recommendation copy.
        if forecastStatus == .onTrack, forecastConfidence == .low {
            return .staleData
        }
        return .onTrack
    }

    private func payload(
        for state: GoalDashboardNextActionResolverState,
        lastSuccessfulRefreshAt: Date?,
        reasonCode: String?
    ) -> (primary: DashboardCTA, secondary: DashboardCTA?, reasonCopyKey: String, isBlocking: Bool, diagnostics: DiagnosticsPayload?) {
        switch state {
        case .hardError:
            return (
                DashboardCTA(
                    id: "retry_data_sync",
                    title: "Retry Data Sync",
                    copyKey: "dashboard.nextAction.hardError.primary",
                    systemImage: "arrow.clockwise"
                ),
                DashboardCTA(
                    id: "view_diagnostics",
                    title: "View Diagnostics",
                    copyKey: "dashboard.nextAction.hardError.secondary",
                    systemImage: "doc.text.magnifyingglass"
                ),
                "dashboard.nextAction.hardError.reason",
                true,
                DiagnosticsPayload(
                    reasonCode: reasonCode ?? "unknown_hard_error",
                    lastSuccessfulRefreshAt: lastSuccessfulRefreshAt,
                    nextStepCopyKey: "dashboard.nextAction.hardError.nextStep",
                    userMessage: GoalDashboardCopyCatalog.hardErrorUserMessage
                )
            )
        case .goalFinishedOrArchived:
            return (
                DashboardCTA(
                    id: "view_goal_history",
                    title: "View Goal History",
                    copyKey: "dashboard.nextAction.finished.primary",
                    systemImage: "clock.arrow.circlepath"
                ),
                DashboardCTA(
                    id: "create_new_goal",
                    title: "Create New Goal",
                    copyKey: "dashboard.nextAction.finished.secondary",
                    systemImage: "plus.circle"
                ),
                "dashboard.nextAction.finished.reason",
                false,
                nil
            )
        case .goalPaused:
            return (
                DashboardCTA(
                    id: "resume_goal",
                    title: "Resume Goal",
                    copyKey: "dashboard.nextAction.paused.primary",
                    systemImage: "play.circle"
                ),
                DashboardCTA(
                    id: "edit_goal",
                    title: "Edit Goal",
                    copyKey: "dashboard.nextAction.paused.secondary",
                    systemImage: "pencil.circle"
                ),
                "dashboard.nextAction.paused.reason",
                false,
                nil
            )
        case .overAllocated:
            return (
                DashboardCTA(
                    id: "rebalance_allocations",
                    title: "Rebalance Allocations",
                    copyKey: "dashboard.nextAction.overAllocated.primary",
                    systemImage: "arrow.left.arrow.right.circle"
                ),
                DashboardCTA(
                    id: "open_allocation_health",
                    title: "Open Allocation Health",
                    copyKey: "dashboard.nextAction.overAllocated.secondary",
                    systemImage: "gauge.with.dots.needle.33percent"
                ),
                "dashboard.nextAction.overAllocated.reason",
                true,
                nil
            )
        case .noAssets:
            return (
                DashboardCTA(
                    id: "add_first_asset",
                    title: "Add First Asset",
                    copyKey: "dashboard.nextAction.noAssets.primary",
                    systemImage: "plus.circle.fill"
                ),
                DashboardCTA(
                    id: "edit_goal",
                    title: "Edit Goal",
                    copyKey: "dashboard.nextAction.noAssets.secondary",
                    systemImage: "pencil.circle"
                ),
                "dashboard.nextAction.noAssets.reason",
                false,
                nil
            )
        case .noContributions:
            return (
                DashboardCTA(
                    id: "add_first_contribution",
                    title: "Add First Contribution",
                    copyKey: "dashboard.nextAction.noContributions.primary",
                    systemImage: "arrow.down.circle.fill"
                ),
                DashboardCTA(
                    id: "open_activity",
                    title: "Open Activity",
                    copyKey: "dashboard.nextAction.noContributions.secondary",
                    systemImage: "list.bullet.rectangle"
                ),
                "dashboard.nextAction.noContributions.reason",
                false,
                nil
            )
        case .staleData:
            return (
                DashboardCTA(
                    id: "refresh_data",
                    title: "Refresh Data",
                    copyKey: "dashboard.nextAction.stale.primary",
                    systemImage: "arrow.clockwise"
                ),
                DashboardCTA(
                    id: "continue_last_data",
                    title: "Continue With Last Data",
                    copyKey: "dashboard.nextAction.stale.secondary",
                    systemImage: "clock.badge.exclamationmark"
                ),
                "dashboard.nextAction.stale.reason",
                false,
                nil
            )
        case .behindSchedule:
            return (
                DashboardCTA(
                    id: "plan_this_month",
                    title: "Plan This Month",
                    copyKey: "dashboard.nextAction.behind.primary",
                    systemImage: "calendar.badge.exclamationmark"
                ),
                DashboardCTA(
                    id: "add_contribution",
                    title: "Add Contribution",
                    copyKey: "dashboard.nextAction.behind.secondary",
                    systemImage: "arrow.down.circle"
                ),
                "dashboard.nextAction.behind.reason",
                false,
                nil
            )
        case .onTrack:
            return (
                DashboardCTA(
                    id: "log_contribution",
                    title: "Log Contribution",
                    copyKey: "dashboard.nextAction.onTrack.primary",
                    systemImage: "plus.circle"
                ),
                DashboardCTA(
                    id: "open_forecast",
                    title: "Open Forecast",
                    copyKey: "dashboard.nextAction.onTrack.secondary",
                    systemImage: "chart.line.uptrend.xyaxis"
                ),
                "dashboard.nextAction.onTrack.reason",
                false,
                nil
            )
        }
    }
}

private struct FreshnessResult {
    let state: DataFreshnessState
    let updatedAt: Date?
    let reasonCode: String?
}
