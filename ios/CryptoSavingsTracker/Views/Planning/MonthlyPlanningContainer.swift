//
//  MonthlyPlanningContainer.swift
//  CryptoSavingsTracker
//
//  Created for v2.1 - Monthly Planning Execution & Tracking
//  Container that switches between planning and execution views
//

import SwiftUI
import SwiftData
import Combine

/// Container view that shows either planning or execution view based on state
struct MonthlyPlanningContainer: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        MonthlyPlanningContainerContent(modelContext: modelContext)
    }
}

/// Shared coordinator for execution state between Container and ExecutionView
@MainActor
class ExecutionStateCoordinator: ObservableObject {
    @Published var isExecuting: Bool = false

    /// Callback to reload state after completion (set by Container)
    var onCompletionReload: (() async -> Void)?

    /// Request the Container to reload execution state
    @Published var reloadRequested: Bool = false
}

/// Implementation detail that binds the container to a single `ModelContext`.
private struct MonthlyPlanningContainerContent: View {
    let modelContext: ModelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var executionRecord: MonthlyExecutionRecord?
    @State private var isLoading = true
    @State private var showStartTrackingConfirmation = false
    @State private var showReturnToPlanningConfirmation = false
    @State private var showFinishMonthConfirmation = false
    @State private var showActionErrorAlert = false
    @State private var actionErrorMessage = ""
    @State private var showingSettings = false
    @State private var showingAddGoal = false
    @State private var hasInitiallyLoaded = false
    @State private var isExecuting = false  // Local @State synced from coordinator
    @State private var cycleState: UiCycleState = .planning(
        month: MonthlyExecutionRecord.monthLabel(from: Date()),
        source: .currentMonth
    )
    @State private var dockPhase: DockPhase = .expanded
    @State private var planningVisualEnabled = VisualSystemRollout.shared.isEnabled(flow: .planning)
    @StateObject private var executionCoordinator = ExecutionStateCoordinator()
    @StateObject private var planningViewModel: MonthlyPlanningViewModel

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        _planningViewModel = StateObject(wrappedValue: MonthlyPlanningViewModel(modelContext: modelContext))
    }

    var body: some View {
        VStack(spacing: 0) {
            if shouldShowStateIndicatorBanner {
                stateIndicatorBanner(cycleState: cycleState)
            }

            // Keep the execution/planning shell consistent regardless of rollout flag.
            // The old bare PlanningView fallback dropped the start-tracking CTA and bypassed
            // execution mode entirely, which is a product regression.
            if isLoading {
                ProgressView("Loading...")
            } else if isExecuting && executionCoordinator.isExecuting {
                MonthlyExecutionView(modelContext: modelContext, coordinator: executionCoordinator)
            } else {
                planningViewWithStartButton
            }
        }
        .background(AccessibleColors.surfaceBase.ignoresSafeArea())
        .navigationTitle("Monthly Planning")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AccessibleColors.surfaceBase, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("openSettingsButton")
                .platformTouchTarget()

                Button {
                    showingAddGoal = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add goal")
                .accessibilityIdentifier("addGoalButton")
                .platformTouchTarget()
            }
        }
        #endif
        .onChange(of: executionCoordinator.isExecuting) { _, newValue in
            // Sync local @State from coordinator changes
            isExecuting = newValue
        }
        .onChange(of: executionCoordinator.reloadRequested) { _, newValue in
            // When MonthlyExecutionView requests reload after completion
            // Immediately set states to switch view, then reload in background
            if newValue {
                executionCoordinator.reloadRequested = false
                // Set states immediately (synchronously) to trigger view switch
                isExecuting = false
                executionCoordinator.isExecuting = false
                // Then reload from database to get updated record/labels
                Task {
                    await loadExecutionRecord()
                    await planningViewModel.loadMonthlyRequirements()
                }
            }
        }
        .task {
            planningVisualEnabled = VisualSystemRollout.shared.isEnabled(flow: .planning)

            // Set up the completion callback for the coordinator
            executionCoordinator.onCompletionReload = { [self] in
                await loadExecutionRecord()
                await planningViewModel.loadMonthlyRequirements()
            }

            // Ensure UI test seed (if requested) completes before loading execution/planning state
            await CryptoSavingsTrackerApp.runUITestSeedIfNeeded(context: modelContext)
            await loadExecutionRecord()
            // Also load monthly requirements after execution record is loaded
            await planningViewModel.loadMonthlyRequirements()
        }
        .onReceive(NotificationCenter.default.publisher(for: .monthlyExecutionCompleted)) { notification in
            // When execution is completed, immediately set states to trigger view switch
            isExecuting = false
            executionCoordinator.isExecuting = false

            // Update record from notification object for banner update
            if let record = notification.object as? MonthlyExecutionRecord {
                executionRecord = record
            }

            // Also reload from database to ensure consistent state
            Task {
                await loadExecutionRecord()
                await planningViewModel.loadMonthlyRequirements()
            }
        }
        .alert("Back to Planning \(formattedActionMonth())?", isPresented: $showReturnToPlanningConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Back to Planning \(formattedActionMonth())") {
                Task {
                    await returnToPlanning()
                }
            }
        } message: {
            Text("This will return \(formattedActionMonth()) to planning mode and stop execution tracking.")
        }
        .alert("Finish \(formattedActionMonth())?", isPresented: $showFinishMonthConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Finish \(formattedActionMonth())") {
                Task {
                    await finishMonth()
                }
            }
        } message: {
            Text("This will close \(formattedActionMonth()) and open planning for the next month.")
        }
        .alert("Action unavailable", isPresented: $showActionErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage)
        }
        .navigationDestination(isPresented: $showingAddGoal) {
            AddGoalView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private var planningViewWithStartButton: some View {
        PlanningView(viewModel: planningViewModel, onAddGoal: {
            showingAddGoal = true
        })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPreferenceChange(DockPhasePreferenceKey.self) { newPhase in
                dockPhase = newPhase
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if allowsStartTracking {
                    CommitDock(
                        phase: dockPhase,
                        showConfirmation: $showStartTrackingConfirmation,
                        planningMonthLabel: planningMonthLabelForStartTracking()
                    )
                }
            }
        .alert("Start Tracking \(formattedPlanningMonth())?", isPresented: $showStartTrackingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Start Tracking \(formattedPlanningMonth())") {
                Task {
                    await startTracking()
                }
            }
        } message: {
            Text("This starts tracking for \(formattedPlanningMonth()). You can undo within \(MonthlyPlanningSettings.shared.undoWindowString).")
        }
    }

    // MARK: - State Indicator Banner

    private var allowsStartTracking: Bool {
        if case .planning = cycleState {
            return true
        }
        return false
    }

    private var shouldShowStateIndicatorBanner: Bool {
        guard !isLoading else { return false }
        switch cycleState {
        case .planning:
            return planningVisualEnabled
        case .executing, .closed, .conflict:
            // Execution and closed-month controls are operational, not decorative.
            // Hiding them behind the planning visual rollout makes core actions like
            // "Finish Month" unreachable in production builds.
            return true
        }
    }

    @ViewBuilder
    private func stateIndicatorBanner(cycleState: UiCycleState) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: iconName(for: cycleState))
                    .font(.title3)
                    .foregroundColor(iconColor(for: cycleState))

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText(for: cycleState))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("executionStatusLabel")

                    Text(subtitleText(for: cycleState))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("planningMonthLabel")
                }

                Spacer()
            }

            if case .executing(let month, _, let canUndoStart) = cycleState {
                VStack(spacing: 8) {
                    Button {
                        if UITestFlags.isEnabled {
                            Task {
                                await finishMonth()
                            }
                        } else {
                            showFinishMonthConfirmation = true
                        }
                    } label: {
                        Label("Finish \(formatMonthLabel(month))", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AccessibleColors.success)
                    .accessibilityIdentifier("finishMonthButton")

                    Button {
                        showReturnToPlanningConfirmation = true
                    } label: {
                        Label("Back to Planning \(formatMonthLabel(month))", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canUndoStart)
                    .accessibilityIdentifier("returnToPlanningButton")
                }
            } else if case .closed(let month, let canUndoCompletion) = cycleState, canUndoCompletion {
                Button {
                    Task {
                        await undoCompletion()
                    }
                } label: {
                    Label("Undo Finish \(formatMonthLabel(month))", systemImage: "arrow.uturn.backward.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AccessibleColors.warning)
                .accessibilityIdentifier("undoFinishButton")
            }
        }
        .padding()
        .background(backgroundColor(for: cycleState))
    }

    private func formatMonthLabel(_ label: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM"
        if let date = formatter.date(from: label) {
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
        return label
    }

    private func titleText(for state: UiCycleState) -> String {
        switch state {
        case .planning:
            return "Planning Mode"
        case .executing:
            return "Tracking Mode"
        case .closed:
            return "Month Complete"
        case .conflict:
            return "State Conflict"
        }
    }

    private func subtitleText(for state: UiCycleState) -> String {
        switch state {
        case .planning(let month, _):
            return "Planning for \(formatMonthLabel(month))"
        case .executing(let month, _, _):
            return "Recording contributions for \(formatMonthLabel(month))"
        case .closed(let month, let canUndo):
            if canUndo {
                return "Undo available for \(formatMonthLabel(month))"
            }
            return "\(formatMonthLabel(month)) is completed"
        case .conflict(let month, _):
            if let month {
                return "Monthly state conflict for \(formatMonthLabel(month)). Refresh required."
            }
            return "Monthly state conflict. Refresh required."
        }
    }

    private func iconName(for state: UiCycleState) -> String {
        switch state {
        case .planning:
            return "doc.text"
        case .executing:
            return "chart.line.uptrend.xyaxis"
        case .closed:
            return "checkmark.circle.fill"
        case .conflict:
            return "exclamationmark.triangle.fill"
        }
    }

    private func iconColor(for state: UiCycleState) -> Color {
        switch state {
        case .planning:
            return AccessibleColors.secondaryText
        case .executing:
            return AccessibleColors.primaryInteractive
        case .closed:
            return AccessibleColors.success
        case .conflict:
            return AccessibleColors.warning
        }
    }

    private func backgroundColor(for state: UiCycleState) -> Color {
        switch state {
        case .planning:
            return AccessibleColors.surfaceSubtle
        case .executing:
            return AccessibleColors.primaryInteractiveBackground
        case .closed:
            return AccessibleColors.success.opacity(0.08)
        case .conflict:
            return AccessibleColors.warning.opacity(0.12)
        }
    }

    // MARK: - Actions

    private func loadExecutionRecord() async {
        isLoading = true
        dockPhase = .expanded
        // Only reset on initial load in UI tests, not on reloads after state changes
        if UITestFlags.isEnabled && !hasInitiallyLoaded {
            executionRecord = nil
            isExecuting = false
            executionCoordinator.isExecuting = false
            hasInitiallyLoaded = true
        }

        do {
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            let allRecords = try executionService.getAllRecords()
            let currentStorageMonth = MonthlyExecutionRecord.monthLabel(from: Date())
            let resolverInput = ResolverInput(
                nowUtc: Date(),
                displayTimeZone: .current,
                currentStorageMonthLabelUtc: currentStorageMonth,
                records: allRecords.map {
                    ExecutionRecordSnapshot(
                        monthLabel: $0.monthLabel,
                        status: $0.status,
                        completedAt: $0.completedAt,
                        startedAt: $0.startedAt,
                        canUndoUntil: $0.canUndoUntil
                    )
                },
                undoWindowSeconds: TimeInterval(MonthlyPlanningSettings.shared.undoGracePeriodHours * 3600)
            )

            cycleState = MonthlyCycleStateResolver().resolve(resolverInput)

            switch cycleState {
            case .planning(let month, _):
                planningViewModel.planningMonthLabel = month
                executionRecord = allRecords
                    .filter { $0.monthLabel == month }
                    .sorted(by: { ($0.createdAt) > ($1.createdAt) })
                    .first
                isExecuting = false
                executionCoordinator.isExecuting = false
            case .executing(let month, _, _):
                executionRecord = allRecords.first(where: { $0.monthLabel == month && $0.status == .executing })
                planningViewModel.planningMonthLabel = month
                isExecuting = true
                executionCoordinator.isExecuting = true
            case .closed(let month, _):
                executionRecord = allRecords
                    .filter { $0.monthLabel == month && $0.status == .closed }
                    .sorted(by: { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) })
                    .first
                planningViewModel.planningMonthLabel = currentStorageMonth
                isExecuting = false
                executionCoordinator.isExecuting = false
            case .conflict:
                executionRecord = nil
                planningViewModel.planningMonthLabel = currentStorageMonth
                isExecuting = false
                executionCoordinator.isExecuting = false
            }
        } catch {
            AppLog.error(
                "Failed to load execution record: \(error.localizedDescription)",
                category: .monthlyPlanning
            )
            isExecuting = false
            executionCoordinator.isExecuting = false
        }
        isLoading = false
    }

    private func startTracking() async {
        guard canPerform(.startTracking) else {
            return
        }
        do {
            AppLog.info("startTracking: Step 1 - Fetching active goals", category: .executionTracking)
            // 1. Fetch active goals
            let descriptor = FetchDescriptor<Goal>(
                predicate: #Predicate { goal in
                    goal.lifecycleStatusRawValue == "active"
                }
            )
            let goals = try modelContext.fetch(descriptor)
            AppLog.info("startTracking: Found \(goals.count) active goals", category: .executionTracking)

            // 2. Get MonthlyPlanService through DI
            let planService = DIContainer.shared.makeMonthlyPlanService(modelContext: modelContext)
            let planningMutationService = DIContainer.shared.makePlanningMutationService(modelContext: modelContext)
            let monthLabel = planningViewModel.planningMonthLabel.isEmpty
                ? planService.currentMonthLabel()
                : planningViewModel.planningMonthLabel

            AppLog.info("startTracking: Step 3 - Getting/creating plans for \(monthLabel)", category: .executionTracking)
            // 3. Get or create plans (serialized via AsyncSerialExecutor)
            let plans = try await planService.getOrCreatePlans(for: monthLabel, goals: goals)

            if plans.isEmpty {
                showActionError(MonthlyCycleCopyCatalog.startBlockedMissingPlan())
                return
            }

            // Note: We do NOT call applyBulkFlexAdjustment here.
            // The plans already have their correct customAmount values from:
            // - Budget Calculator allocations
            // - User's flex slider adjustments (applied when slider changes)
            // Calling it again would overwrite user's budget with calculated requiredMonthly values.

            try planningMutationService.preparePlansForExecution(plans)

            AppLog.info("startTracking: Step 5 - Validating plans", category: .executionTracking)
            // 5. Validate plans before transition
            try planService.validatePlansForExecution(plans)

            AppLog.info("startTracking: Step 6 - Starting execution", category: .executionTracking)
            // 6. Transition plans from draft to executing
            try planService.startExecution(for: plans)

            AppLog.info("startTracking: Step 7 - Creating execution record", category: .executionTracking)
            // 7. Create execution record with snapshot
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)

            let record = try executionService.startTracking(
                for: monthLabel,
                from: plans,
                goals: goals
            )

            executionRecord = record
            cycleState = .executing(
                month: monthLabel,
                canFinish: true,
                canUndoStart: true
            )
            isExecuting = true
            executionCoordinator.isExecuting = true
            AppLog.info("startTracking: Successfully started tracking for \(monthLabel)", category: .executionTracking)

        } catch {
            AppLog.error(
                "Failed to start tracking: \(error.localizedDescription)",
                category: .executionTracking
            )
            showActionError(error.localizedDescription)
        }
    }

    /// Return from execution mode to planning by undoing tracking and resetting plan state.
    private func returnToPlanning() async {
        guard canPerform(.undoStart) else { return }
        guard let record = executionRecord else {
            showActionError(MonthlyCycleCopyCatalog.recordConflict())
            return
        }
        guard record.status == .executing else {
            showActionError(MonthlyCycleCopyCatalog.undoStartExpired(month: formatMonthLabel(record.monthLabel)))
            return
        }
        isLoading = true

        do {
            // Reset plan states to draft for this month
            let planService = DIContainer.shared.makeMonthlyPlanService(modelContext: modelContext)
            let plans = try planService.fetchPlans(for: record.monthLabel)
            try DIContainer.shared.makePlanningMutationService(modelContext: modelContext).resetPlansToDraft(plans)

            // Undo start tracking (respects undo window)
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            try executionService.undoStartTracking(record)
            cycleState = .planning(
                month: record.monthLabel,
                source: .currentMonth
            )

            // Refresh state and planning data
            executionRecord = record
            await loadExecutionRecord()
            await planningViewModel.loadMonthlyRequirements()
        } catch {
            AppLog.error(
                "Failed to return to planning: \(error.localizedDescription)",
                category: .executionTracking
            )
            if let executionError = error as? ExecutionTrackingService.ExecutionError,
               case .undoPeriodExpired = executionError {
                showActionError(MonthlyCycleCopyCatalog.undoStartExpired(month: formatMonthLabel(record.monthLabel)))
            } else {
                showActionError(error.localizedDescription)
            }
        }

        isLoading = false
    }

    /// Complete the current month and transition to planning for next month.
    private func finishMonth() async {
        guard canPerform(.finishMonth) else { return }
        guard let record = executionRecord else {
            showActionError(MonthlyCycleCopyCatalog.recordConflict())
            return
        }
        guard record.status == .executing else {
            showActionError(MonthlyCycleCopyCatalog.finishBlockedNoExecuting())
            return
        }

        // Set states FIRST to immediately switch view (before async work)
        isExecuting = false
        executionCoordinator.isExecuting = false

        do {
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            try await executionService.markComplete(record)
            let nextMonth = nextMonthLabel(after: record.monthLabel) ?? MonthlyExecutionRecord.monthLabel(from: Date())
            cycleState = .planning(
                month: nextMonth,
                source: .nextMonthAfterClosed
            )

            // Update record and reload state
            executionRecord = record
            await loadExecutionRecord()
            await planningViewModel.loadMonthlyRequirements()
        } catch {
            // If completion fails, restore executing state
            isExecuting = true
            executionCoordinator.isExecuting = true
            showActionError(error.localizedDescription)
        }
    }

    private func undoCompletion() async {
        guard canPerform(.undoCompletion) else { return }
        guard let record = executionRecord else {
            showActionError(MonthlyCycleCopyCatalog.recordConflict())
            return
        }
        isLoading = true

        do {
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            try executionService.undoCompletion(record)
            cycleState = .executing(
                month: record.monthLabel,
                canFinish: true,
                canUndoStart: record.canUndo
            )
            await loadExecutionRecord()
            await planningViewModel.loadMonthlyRequirements()
        } catch {
            AppLog.error(
                "Failed to undo completion: \(error.localizedDescription)",
                category: .executionTracking
            )
            if let executionError = error as? ExecutionTrackingService.ExecutionError,
               case .undoPeriodExpired = executionError {
                showActionError(MonthlyCycleCopyCatalog.undoCompletionExpired(month: formatMonthLabel(record.monthLabel)))
            } else {
                showActionError(error.localizedDescription)
            }
        }

        isLoading = false
    }

    private func formattedPlanningMonth() -> String {
        switch cycleState {
        case .planning(let month, _):
            return formatMonthLabel(month)
        case .executing(let month, _, _):
            return formatMonthLabel(month)
        case .closed(let month, _):
            return formatMonthLabel(month)
        case .conflict:
            return formatMonthLabel(MonthlyExecutionRecord.monthLabel(from: Date()))
        }
    }

    private func planningMonthLabelForStartTracking() -> String {
        if case .planning(let month, _) = cycleState {
            return month
        }
        if !planningViewModel.planningMonthLabel.isEmpty {
            return planningViewModel.planningMonthLabel
        }
        return MonthlyExecutionRecord.monthLabel(from: Date())
    }

    private func formattedActionMonth() -> String {
        switch cycleState {
        case .executing(let month, _, _):
            return formatMonthLabel(month)
        case .closed(let month, _):
            return formatMonthLabel(month)
        case .planning(let month, _):
            return formatMonthLabel(month)
        case .conflict:
            return formatMonthLabel(MonthlyExecutionRecord.monthLabel(from: Date()))
        }
    }

    private func showActionError(_ message: String) {
        actionErrorMessage = message
        showActionErrorAlert = true
    }

    private func canPerform(_ action: MonthlyCycleAction) -> Bool {
        let decision = MonthlyCycleActionGate.evaluate(state: cycleState, action: action)
        guard !decision.allowed else { return true }
        showActionError(blockedActionMessage(for: decision, state: cycleState))
        return false
    }

    private func blockedActionMessage(for decision: MonthlyCycleActionDecision, state: UiCycleState) -> String {
        let monthDisplay = displayMonth(for: state)
        switch decision.blockedCopyKey {
        case .startBlockedAlreadyExecuting:
            return MonthlyCycleCopyCatalog.startBlockedAlreadyExecuting(month: monthDisplay)
        case .startBlockedClosedMonth:
            return MonthlyCycleCopyCatalog.startBlockedClosedMonth()
        case .finishBlockedNoExecuting:
            return MonthlyCycleCopyCatalog.finishBlockedNoExecuting()
        case .undoStartExpired:
            return MonthlyCycleCopyCatalog.undoStartExpired(month: monthDisplay)
        case .undoCompletionExpired:
            return MonthlyCycleCopyCatalog.undoCompletionExpired(month: monthDisplay)
        case .recordConflict:
            return MonthlyCycleCopyCatalog.recordConflict()
        case nil:
            return decision.blockedMessage ?? MonthlyCycleCopyCatalog.recordConflict()
        }
    }

    private func displayMonth(for state: UiCycleState) -> String {
        switch state {
        case .planning(let month, _):
            return formatMonthLabel(month)
        case .executing(let month, _, _):
            return formatMonthLabel(month)
        case .closed(let month, _):
            return formatMonthLabel(month)
        case .conflict(let month, _):
            if let month {
                return formatMonthLabel(month)
            }
            return formatMonthLabel(MonthlyExecutionRecord.monthLabel(from: Date()))
        }
    }

    private func nextMonthLabel(after monthLabel: String) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: monthLabel) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let next = calendar.date(byAdding: .month, value: 1, to: date) else { return nil }
        return formatter.string(from: next)
    }
}
