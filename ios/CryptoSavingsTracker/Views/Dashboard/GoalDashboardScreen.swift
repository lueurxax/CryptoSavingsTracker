//
//  GoalDashboardScreen.swift
//  CryptoSavingsTracker
//

import SwiftUI
import SwiftData

private enum GoalDashboardAssetIntent {
    case addContribution
    case reviewActivity
    case rebalanceAllocations
}

struct GoalDashboardScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage("dashboard_widgets") private var legacyWidgetsJSON: String = ""
    @AppStorage(PreviewFeaturesRuntime.userDefaultsKey) private var previewFeaturesEnabled = false

    let goal: Goal

    @StateObject private var viewModel = GoalDashboardViewModel()

    @State private var showingAddAsset = false
    @State private var showingAddTransaction = false
    @State private var showingTransactionHistory = false
    @State private var showingAllocationWorkspace = false
    @State private var showingAssetPicker = false
    @State private var showingEditGoal = false
    @State private var showingDiagnostics = false
    @State private var selectedAsset: Asset?
    @State private var pendingAssetIntent: GoalDashboardAssetIntent = .addContribution
    @State private var actionInfoMessage: String?
    @State private var dashboardOpenedTracked = false
    @State private var lastPrimaryCTAFingerprint: String?

    private var sceneModel: GoalDashboardSceneModel? { viewModel.sceneModel }
    private var goalAssets: [Asset] { goal.allocatedAssets }
    private var isRegularLayout: Bool { horizontalSizeClass == .regular }
    private var telemetryTracker: NavigationTelemetryTracker { DIContainer.shared.navigationTelemetryTracker }
    private var primaryCtaTrackingFingerprint: String? {
        guard let next = sceneModel?.nextAction else { return nil }
        return "\(next.resolverState.rawValue)|\(next.primaryCta.id)"
    }
    private var sceneTransitionAnimation: Animation {
        accessibilityReduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22)
    }

    private var shouldShowForecastModules: Bool {
        HiddenRuntimeMode.current.showsForecastModules
    }

    var body: some View {
        let observed = dashboardContent
            .task(id: goal.id) {
                viewModel.configure(goal: goal, modelContext: modelContext, legacyWidgetsJSON: legacyWidgetsJSON)
                await viewModel.load()
            }
            .onChange(of: legacyWidgetsJSON) { _, newValue in
                viewModel.reloadLegacyWidgets(widgetsJSON: newValue)
            }
            .onChange(of: (goal.allocations ?? []).count) { _, _ in reloadScene() }
            .onChange(of: goal.lifecycleStatus) { _, _ in reloadScene() }
            .onChange(of: goal.targetAmount) { _, _ in reloadScene() }
            .onChange(of: goal.deadline) { _, _ in reloadScene() }
            .onChange(of: previewFeaturesEnabled) { _, _ in reloadScene() }
            .onChange(of: sceneModel?.goalId) { _, newGoalID in
                guard !dashboardOpenedTracked, newGoalID != nil else { return }
                telemetryTracker.goalDashboardOpened(goalID: goal.id.uuidString.lowercased(), entryPoint: "goal_detail")
                dashboardOpenedTracked = true
            }
            .onChange(of: primaryCtaTrackingFingerprint) { _, newFingerprint in
                guard let newFingerprint, newFingerprint != lastPrimaryCTAFingerprint else { return }
                guard let next = sceneModel?.nextAction else { return }
                telemetryTracker.goalDashboardPrimaryCtaShown(
                    goalID: goal.id.uuidString.lowercased(),
                    resolverState: next.resolverState.rawValue,
                    ctaID: next.primaryCta.id
                )
                lastPrimaryCTAFingerprint = newFingerprint
            }

        let presented = observed
            .sheet(isPresented: $showingAddAsset) {
                AddAssetView(goal: goal)
            }
            .sheet(isPresented: $showingAddTransaction) {
                assetIntentSheet(for: .addContribution)
            }
            .sheet(isPresented: $showingTransactionHistory) {
                assetIntentSheet(for: .reviewActivity)
            }
            .sheet(isPresented: $showingAllocationWorkspace) {
                assetIntentSheet(for: .rebalanceAllocations)
            }
            .sheet(isPresented: $showingAssetPicker) {
                assetPickerSheet
            }
            .sheet(isPresented: $showingEditGoal) {
                EditGoalView(goal: goal, modelContext: modelContext)
            }
            .sheet(isPresented: $showingDiagnostics) {
                diagnosticsSheet
            }

        return presented
            .alert("Action Info", isPresented: Binding(
                get: { actionInfoMessage != nil },
                set: { if !$0 { actionInfoMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionInfoMessage ?? "")
            }
            .animation(sceneTransitionAnimation, value: sceneModel?.generatedAt)
    }

    private var dashboardContent: some View {
        ScrollView {
            if isRegularLayout {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    snapshotCard
                    nextActionCard
                    if shouldShowForecastModules {
                        forecastRiskCard
                    }
                    contributionActivityCard
                    allocationHealthCard
                    utilitiesCard
                }
                .padding(16)
            } else {
                VStack(spacing: 16) {
                    snapshotCard
                    nextActionCard
                    if shouldShowForecastModules {
                        forecastRiskCard
                    }
                    contributionActivityCard
                    allocationHealthCard
                    utilitiesCard
                }
                .padding(16)
            }
        }
    }

    private var assetPickerSheet: some View {
        NavigationStack {
            List(goalAssets, id: \.id) { asset in
                Button {
                    selectedAsset = asset
                    showingAssetPicker = false
                    switch pendingAssetIntent {
                    case .addContribution:
                        showingAddTransaction = true
                    case .reviewActivity:
                        showingTransactionHistory = true
                    case .rebalanceAllocations:
                        showingAllocationWorkspace = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "bitcoinsign.circle")
                        Text(asset.currency)
                        Spacer()
                        if let address = asset.address {
                            Text(address)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityLabel(
                        DashboardAccessibilityCopy.assetSelectionLabel(
                            currency: asset.currency,
                            address: asset.address
                        )
                    )
                    .accessibilityHint(
                        DashboardAccessibilityCopy.assetSelectionHint(currency: asset.currency)
                    )
                }
            }
            .navigationTitle("Select Asset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingAssetPicker = false }
                        .accessibilityIdentifier("dashboard.asset_picker.dismiss")
                        .accessibilityHint(DashboardAccessibilityCopy.assetPickerDismissHint)
                }
            }
        }
    }

    @ViewBuilder
    private func assetIntentSheet(for intent: GoalDashboardAssetIntent) -> some View {
        if let selectedAsset {
            switch intent {
            case .addContribution:
                AddTransactionView(asset: selectedAsset)
            case .reviewActivity:
                NavigationStack {
                    TransactionHistoryView(asset: selectedAsset)
                }
            case .rebalanceAllocations:
                AssetSharingView(asset: selectedAsset, currentGoalId: goal.id)
            }
        } else {
            DashboardTransactionRecoverySheet(
                goalName: goal.name,
                hasAssets: !goalAssets.isEmpty,
                primaryActionTitle: goalAssets.isEmpty ? "Add Asset" : "Choose Asset"
            ) {
                if goalAssets.isEmpty {
                    showingAddAsset = true
                } else {
                    showingAssetPicker = true
                }
            } onDismiss: {
                switch intent {
                case .addContribution:
                    showingAddTransaction = false
                case .reviewActivity:
                    showingTransactionHistory = false
                case .rebalanceAllocations:
                    showingAllocationWorkspace = false
                }
            }
        }
    }

    private func reloadScene() {
        Task { await viewModel.load() }
    }

    private var snapshotCard: some View {
        dashboardCard(
            moduleID: .goalSnapshot,
            title: "Goal Snapshot",
            systemImage: "target",
            surface: .primary
        ) {
            if let scene = sceneModel {
                switch scene.snapshot.moduleState {
                case .loading:
                    ProgressView()
                case .error, .stale:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Snapshot is not up to date.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        moduleRecoveryButton(
                            title: scene.snapshot.moduleState == .error ? "Retry Data Sync" : "Refresh Snapshot",
                            actionID: "refresh_data"
                        )
                    }
                case .ready, .empty:
                    VStack(alignment: .leading, spacing: 10) {
                        let currentText = CurrencyFormatter.format(
                            amount: scene.snapshot.currentAmount,
                            currency: scene.currency,
                            fractionDigits: 2
                        )
                        let targetText = CurrencyFormatter.format(
                            amount: scene.snapshot.targetAmount,
                            currency: scene.currency,
                            fractionDigits: 2
                        )
                        Text("\(currentText) of \(targetText)")
                            .font(.headline)

                        ProgressView(value: min(max(scene.snapshot.progressRatio, 0), 1.0))
                            .tint(VisualComponentTokens.statusInfo)

                        HStack {
                            Text("Remaining \(CurrencyFormatter.format(amount: scene.snapshot.remainingAmount, currency: scene.currency, fractionDigits: 2))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            if let days = scene.snapshot.daysRemaining {
                                Text("\(days) days left")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
    }

    private var nextActionCard: some View {
        dashboardCard(
            moduleID: .nextAction,
            title: "Next Action",
            systemImage: "bolt.fill",
            surface: .emphasis
        ) {
            if let next = sceneModel?.nextAction {
                if next.moduleState == .error, let diagnostics = next.diagnostics {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(diagnostics.userMessage)
                            .font(.subheadline)
                        Button("View Diagnostics") {
                            showingDiagnostics = true
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(copy(for: next.reasonCopyKey))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Button {
                            telemetryTracker.goalDashboardPrimaryCtaTapped(
                                goalID: goal.id.uuidString.lowercased(),
                                resolverState: next.resolverState.rawValue,
                                ctaID: next.primaryCta.id
                            )
                            handleAction(id: next.primaryCta.id)
                        } label: {
                            Label(next.primaryCta.title, systemImage: next.primaryCta.systemImage)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        if let secondary = next.secondaryCta {
                            Button {
                                handleAction(id: secondary.id)
                            } label: {
                                Label(secondary.title, systemImage: secondary.systemImage)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
    }

    private var forecastRiskCard: some View {
        dashboardCard(
            moduleID: .forecastRisk,
            title: "Forecast and Deadline Risk",
            systemImage: "chart.line.uptrend.xyaxis",
            surface: .primary
        ) {
            if let forecast = sceneModel?.forecastRisk {
                switch forecast.moduleState {
                case .loading:
                    ProgressView()
                case .empty:
                    Text("Add more contributions to generate forecast insights.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                case .error:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Forecast data is unavailable right now.")
                            .font(.subheadline)
                        forecastExplainabilityRows(
                            assumptionText: "Based on available contribution history before the error.",
                            updatedAt: forecast.updatedAt,
                            confidence: nil
                        )
                        Button("Why this status?") {
                            actionInfoMessage = "Forecast error reason: \(forecast.errorReasonCode ?? "unavailable")."
                        }
                        .buttonStyle(.bordered)
                        moduleRecoveryButton(title: "Retry Forecast", actionID: "refresh_data")
                    }
                case .stale, .ready:
                    VStack(alignment: .leading, spacing: 8) {
                        if let status = forecast.status {
                            statusChip(status)
                        }
                        if let amount = forecast.projectedAmount {
                            Text("Projected by deadline: \(CurrencyFormatter.format(amount: amount, currency: sceneModel?.currency ?? goal.currency, fractionDigits: 2))")
                                .font(.headline)
                        }
                        forecastExplainabilityRows(
                            assumptionText: "Based on last \(forecast.assumptionWindowDays ?? 0) days of contributions.",
                            updatedAt: forecast.updatedAt,
                            confidence: forecast.confidence
                        )
                        Button("Why this status?") {
                            actionInfoMessage = statusExplanation(for: forecast.status)
                        }
                        .buttonStyle(.bordered)
                        if forecast.moduleState == .stale {
                            moduleRecoveryButton(title: "Refresh Forecast", actionID: "refresh_data")
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
    }

    private var contributionActivityCard: some View {
        dashboardCard(
            moduleID: .contributionActivity,
            title: "Contributions and Activity",
            systemImage: "list.bullet.rectangle",
            surface: .primary
        ) {
            if let activity = sceneModel?.contributionActivity {
                switch activity.moduleState {
                case .loading:
                    ProgressView()
                case .error, .stale:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Activity data is out of date.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        moduleRecoveryButton(
                            title: activity.moduleState == .error ? "Reload Activity" : "Refresh Activity",
                            actionID: "refresh_data"
                        )
                    }
                case .empty, .ready:
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            "This month: \(CurrencyFormatter.format(amount: activity.monthContributionSum, currency: sceneModel?.currency ?? goal.currency, fractionDigits: 2))"
                        )
                        .font(.headline)

                        if activity.recentRows.isEmpty {
                            Text("No recent contributions.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(activity.recentRows.prefix(5), id: \.id) { row in
                                HStack {
                                    Text(row.assetCurrency)
                                    Spacer()
                                    Text(
                                        "\(NSDecimalNumber(decimal: row.amount).doubleValue >= 0 ? "+" : "")" +
                                            CurrencyFormatter.format(amount: row.amount, currency: row.assetCurrency, fractionDigits: 2)
                                    )
                                    .foregroundColor(NSDecimalNumber(decimal: row.amount).doubleValue >= 0 ? VisualComponentTokens.statusSuccess : VisualComponentTokens.statusError)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
    }

    private var allocationHealthCard: some View {
        dashboardCard(
            moduleID: .allocationHealth,
            title: "Allocation Health",
            systemImage: "gauge.with.dots.needle.33percent",
            surface: .primary
        ) {
            if let allocation = sceneModel?.allocationHealth {
                switch allocation.moduleState {
                case .loading:
                    ProgressView()
                case .error, .stale:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Allocation health needs refresh.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        moduleRecoveryButton(
                            title: allocation.moduleState == .error ? "Recompute Allocation Health" : "Refresh Allocations",
                            actionID: "refresh_data"
                        )
                    }
                case .empty:
                    Text("No allocations yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                case .ready:
                    VStack(alignment: .leading, spacing: 8) {
                        if allocation.overAllocated {
                            Text("Some assets are over-allocated.")
                                .font(.subheadline)
                                .foregroundColor(VisualComponentTokens.statusWarning)
                        } else if let ratio = allocation.concentrationRatio, ratio > 0.7 {
                            Text("Allocation is concentrated in a single asset.")
                                .font(.subheadline)
                                .foregroundColor(VisualComponentTokens.statusWarning)
                        } else {
                            Text("Allocation looks balanced.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        ForEach(allocation.topAssets, id: \.assetId) { asset in
                            HStack {
                                Text(asset.assetCurrency)
                                Spacer()
                                Text("\(Int(asset.weightRatio * 100))%")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
    }

    private var utilitiesCard: some View {
        dashboardCard(
            moduleID: .utilities,
            title: "Utilities",
            systemImage: "wrench.and.screwdriver",
            surface: .secondary
        ) {
            if let utilities = sceneModel?.utilities {
                switch utilities.moduleState {
                case .error:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Utility actions are temporarily unavailable.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        moduleRecoveryButton(title: "Open Goal Details", actionID: "edit_goal")
                    }
                case .stale:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Showing previous utility actions.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        moduleRecoveryButton(title: "Continue", actionID: "continue_last_data")
                    }
                case .loading:
                    ProgressView()
                case .empty:
                    Text("No utility actions available.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                case .ready:
                    VStack(spacing: 8) {
                        ForEach(utilities.actions, id: \.id) { action in
                            Button {
                                handleAction(id: action.id)
                            } label: {
                                HStack {
                                    Label(action.title, systemImage: action.systemImage)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
    }

    private func forecastExplainabilityRows(
        assumptionText: String,
        updatedAt: Date?,
        confidence: GoalDashboardForecastConfidence?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(assumptionText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Updated \(updatedAt?.formatted(.relative(presentation: .named)) ?? "recently")")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Confidence: \(confidence?.rawValue.capitalized ?? "Unavailable")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func moduleRecoveryButton(title: String, actionID: String) -> some View {
        Button(title) {
            handleAction(id: actionID)
        }
        .buttonStyle(.bordered)
    }

    private func statusChip(_ status: GoalDashboardRiskStatus) -> some View {
        let style: (icon: String, text: String, color: Color) = {
            switch status {
            case .onTrack:
                return ("checkmark.circle.fill", "On Track", VisualComponentTokens.statusSuccess)
            case .atRisk:
                return ("exclamationmark.triangle.fill", "At Risk", VisualComponentTokens.statusWarning)
            case .offTrack:
                return ("xmark.octagon.fill", "Off Track", VisualComponentTokens.statusError)
            }
        }()

        return HStack(spacing: 6) {
            Image(systemName: style.icon)
            Text(style.text)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(style.color.opacity(0.15))
        .foregroundColor(style.color)
        .clipShape(Capsule())
        .accessibilityLabel(accessibilityStatusLabel(for: status))
    }

    private var diagnosticsSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let diagnostics = sceneModel?.nextAction.diagnostics {
                    Text("Reason")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(diagnostics.reasonCode.replacingOccurrences(of: "_", with: " "))
                        .font(.body)

                    Text("Last Successful Refresh")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(diagnostics.lastSuccessfulRefreshAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unavailable")
                        .font(.body)

                    Text("Next Step")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(copy(for: diagnostics.nextStepCopyKey))
                        .font(.body)
                } else {
                    Text("No diagnostics available.")
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingDiagnostics = false }
                }
            }
        }
    }

    private func handleAction(id: String) {
        switch id {
        case "add_first_asset", "add_asset":
            showingAddAsset = true
        case "add_first_contribution", "add_contribution", "log_contribution":
            openContributionFlow()
        case "review_activity":
            openActivityFlow()
        case "edit_goal":
            showingEditGoal = true
        case "retry_data_sync", "refresh_data":
            Task { await viewModel.load() }
        case "view_diagnostics":
            showingDiagnostics = true
        case "resume_goal":
            Task {
                try? await DIContainer.shared.makeGoalMutationService(modelContext: modelContext).resumeGoal(goal)
                await viewModel.load()
            }
        case "rebalance_allocations", "open_allocation_health":
            openAllocationFlow()
        case "create_new_goal":
            actionInfoMessage = "Use the Goals tab to create a new goal."
        case "continue_last_data":
            actionInfoMessage = "Using the last successful dashboard snapshot."
        default:
            break
        }
    }

    private func openContributionFlow() {
        pendingAssetIntent = .addContribution
        if goalAssets.isEmpty {
            showingAddAsset = true
            return
        }
        if goalAssets.count == 1 {
            selectedAsset = goalAssets.first
            showingAddTransaction = selectedAsset != nil
            return
        }
        showingAssetPicker = true
    }

    private func openActivityFlow() {
        pendingAssetIntent = .reviewActivity
        guard !goalAssets.isEmpty else {
            actionInfoMessage = "Add an asset first to start building goal activity."
            return
        }
        if goalAssets.count == 1 {
            selectedAsset = goalAssets.first
            showingTransactionHistory = selectedAsset != nil
            return
        }
        showingAssetPicker = true
    }

    private func openAllocationFlow() {
        pendingAssetIntent = .rebalanceAllocations
        guard !goalAssets.isEmpty else {
            showingAddAsset = true
            return
        }
        if goalAssets.count == 1 {
            selectedAsset = goalAssets.first
            showingAllocationWorkspace = selectedAsset != nil
            return
        }
        showingAssetPicker = true
    }

    private func statusExplanation(for status: GoalDashboardRiskStatus?) -> String {
        switch status {
        case .onTrack:
            return "Current pace is sufficient for deadline."
        case .atRisk:
            return "Current pace may miss deadline unless contributions increase."
        case .offTrack:
            return "Current pace is not sufficient to reach target by deadline."
        case .none:
            return "Status explanation is unavailable."
        }
    }

    private func copy(for key: String) -> String {
        GoalDashboardCopyCatalog.text(for: key)
    }

    private func accessibilityStatusLabel(for status: GoalDashboardRiskStatus) -> String {
        switch status {
        case .onTrack:
            return "On track: current pace can reach deadline"
        case .atRisk:
            return "At risk: current pace may miss deadline"
        case .offTrack:
            return "Off track: current pace will miss deadline"
        }
    }

    private func dashboardCard<Content: View>(
        moduleID: GoalDashboardModuleID,
        title: String,
        systemImage: String,
        surface: DashboardCardSurface,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: VisualComponentTokens.dashboardCardCornerRadius)
                .fill(surface.shapeStyle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VisualComponentTokens.dashboardCardCornerRadius)
                .stroke(VisualComponentTokens.dashboardCardStroke, lineWidth: 1)
        )
        .accessibilityIdentifier(moduleID.rawValue)
    }
}

private enum DashboardCardSurface {
    case primary
    case secondary
    case emphasis

    var shapeStyle: AnyShapeStyle {
        switch self {
        case .primary:
            return VisualComponentTokens.dashboardCardPrimaryFill
        case .secondary:
            return VisualComponentTokens.dashboardCardSecondaryFill
        case .emphasis:
            return VisualComponentTokens.dashboardCardEmphasisFill
        }
    }
}
