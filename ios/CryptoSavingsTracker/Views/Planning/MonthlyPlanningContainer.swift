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
    @State private var executionRecord: MonthlyExecutionRecord?
    @State private var isLoading = true
    @State private var showStartTrackingConfirmation = false
    @State private var showReturnToPlanningConfirmation = false
    @State private var showFinishMonthConfirmation = false
    @State private var hasInitiallyLoaded = false
    @State private var isExecuting = false  // Local @State synced from coordinator
    @StateObject private var executionCoordinator = ExecutionStateCoordinator()
    @StateObject private var planningViewModel: MonthlyPlanningViewModel

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        _planningViewModel = StateObject(wrappedValue: MonthlyPlanningViewModel(modelContext: modelContext))
    }

    var body: some View {
        VStack(spacing: 0) {
            // State indicator banner
            if let record = executionRecord {
                stateIndicatorBanner(for: record, planningMonthLabel: planningViewModel.planningMonthLabel)
            }

            // Use AND logic: show execution only if BOTH local @State AND coordinator say so
            // This ensures either source setting false will immediately show planning
            if isLoading {
                ProgressView("Loading...")
            } else if isExecuting && executionCoordinator.isExecuting {
                // Show execution view with shared coordinator
                MonthlyExecutionView(modelContext: modelContext, coordinator: executionCoordinator)
            } else {
                // Show planning view with start tracking button
                planningViewWithStartButton
            }
        }
        .navigationTitle("Monthly Planning")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
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
                updatePlanningMonthLabel()
            }

            // Also reload from database to ensure consistent state
            Task {
                await loadExecutionRecord()
                await planningViewModel.loadMonthlyRequirements()
            }
        }
        .alert("Return to Planning Mode?", isPresented: $showReturnToPlanningConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Return to Planning") {
                Task {
                    await returnToPlanning()
                }
            }
        } message: {
            Text("This will move this month back to planning mode and stop execution tracking. You can start tracking again later.")
        }
        .alert("Complete this month?", isPresented: $showFinishMonthConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Finish Month") {
                Task {
                    await finishMonth()
                }
            }
        } message: {
            Text("This will mark the current month as complete and move to planning mode for next month.")
        }
    }

    private var planningViewWithStartButton: some View {
        PlanningView(viewModel: planningViewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                startTrackingDock
            }
        .alert("Start Tracking?", isPresented: $showStartTrackingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Start Tracking") {
                Task {
                    await startTracking()
                }
            }
        } message: {
            Text("This will begin tracking your contributions for this month. You can undo this action within 24 hours.")
        }
    }

    private var startTrackingDock: some View {
        VStack(spacing: 8) {
            Divider()

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)

                Text("Ready to commit to this plan?")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()
            }

            Text("This will lock in your monthly amounts and enable contribution tracking. You can undo this action within 24 hours.")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)

            Button {
                showStartTrackingConfirmation = true
            } label: {
                Label("Lock Plan & Start Tracking", systemImage: "lock.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityIdentifier("startTrackingButton")
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: - State Indicator Banner

    @ViewBuilder
    private func stateIndicatorBanner(for record: MonthlyExecutionRecord, planningMonthLabel: String) -> some View {
        let isTracking = record.status == .executing
        let isClosed = record.status == .closed
        let planningLabel = formatMonthLabel(planningMonthLabel)
        let trackingLabel = formatMonthLabel(record.monthLabel)

        VStack(spacing: 12) {
            // Top row: Status info
            HStack(spacing: 12) {
                Image(systemName: isTracking ? "chart.line.uptrend.xyaxis" : "doc.text")
                    .font(.title3)
                    .foregroundColor(isTracking ? .blue : (isClosed ? .green : .secondary))

                VStack(alignment: .leading, spacing: 2) {
                    Text(isTracking ? "Tracking Mode" : (isClosed ? "Month Complete" : "Planning Mode"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("executionStatusLabel")

                    Text(isTracking ? "Recording contributions for \(trackingLabel)" : "Planning for \(planningLabel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("planningMonthLabel")
                }

                Spacer()

                if isClosed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }

            }

            // Bottom row: Action buttons (full width)
            if record.status == .executing {
                VStack(spacing: 8) {
                    // Finish Month button - in UI tests, tapping this runs directly in Container context
                    Button {
                        if UITestFlags.isEnabled {
                            // In UI tests: complete immediately (no confirmation dialog)
                            Task {
                                await finishMonth()
                            }
                        } else {
                            showFinishMonthConfirmation = true
                        }
                    } label: {
                        Label("Finish This Month", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .accessibilityIdentifier("finishMonthButton")

                    Button {
                        showReturnToPlanningConfirmation = true
                    } label: {
                        Label("Return to Planning", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("returnToPlanningButton")
                }
            }
        }
        .padding()
        .background(isTracking ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
    }

    private func formatMonthLabel(_ label: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        if let date = formatter.date(from: label) {
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
        return label
    }

    // MARK: - Actions

    private func loadExecutionRecord() async {
        isLoading = true
        // Only reset on initial load in UI tests, not on reloads after state changes
        if UITestFlags.isEnabled && !hasInitiallyLoaded {
            executionRecord = nil
            isExecuting = false
            executionCoordinator.isExecuting = false
            hasInitiallyLoaded = true
        }

        do {
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            if let activeRecord = try executionService.getActiveRecord() {
                executionRecord = activeRecord
                let newValue = activeRecord.status == .executing
                isExecuting = newValue
                executionCoordinator.isExecuting = newValue
            } else {
                executionRecord = try executionService.getCurrentMonthRecord()
                let newValue = executionRecord?.status == .executing
                isExecuting = newValue
                executionCoordinator.isExecuting = newValue
            }
        } catch {
            print("Error loading execution record: \(error)")
            isExecuting = false
            executionCoordinator.isExecuting = false
        }

        updatePlanningMonthLabel()
        isLoading = false
    }

    private func startTracking() async {
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
            let monthLabel = planningViewModel.planningMonthLabel.isEmpty
                ? planService.currentMonthLabel()
                : planningViewModel.planningMonthLabel

            AppLog.info("startTracking: Step 3 - Getting/creating plans for \(monthLabel)", category: .executionTracking)
            // 3. Get or create plans (serialized via AsyncSerialExecutor)
            let plans = try await planService.getOrCreatePlans(for: monthLabel, goals: goals)

            // 3.5. Check if plans are already in non-draft state and reset if needed
            let nonDraftPlans = plans.filter { $0.state != .draft }
            if !nonDraftPlans.isEmpty {
                AppLog.info("startTracking: Resetting \(nonDraftPlans.count) non-draft plans to draft", category: .executionTracking)
                for plan in nonDraftPlans {
                    plan.state = .draft
                }
                try modelContext.save()
            }

            // Note: We do NOT call applyBulkFlexAdjustment here.
            // The plans already have their correct customAmount values from:
            // - Budget Calculator allocations
            // - User's flex slider adjustments (applied when slider changes)
            // Calling it again would overwrite user's budget with calculated requiredMonthly values.

            // 4. Auto-skip plans with zero effective amount (goal already funded or no remaining)
            let zeroAmountPlans = plans.filter { !$0.isSkipped && $0.effectiveAmount <= 0 }
            if !zeroAmountPlans.isEmpty {
                AppLog.info("startTracking: Auto-skipping \(zeroAmountPlans.count) plans with zero effective amount", category: .executionTracking)
                for plan in zeroAmountPlans {
                    plan.isSkipped = true
                }
                try modelContext.save()
            }

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
            isExecuting = true
            executionCoordinator.isExecuting = true
            AppLog.info("startTracking: Successfully started tracking for \(monthLabel)", category: .executionTracking)

        } catch {
            AppLog.error("Failed to start tracking: \(error)", category: .executionTracking)
        }
    }

    /// Return from execution mode to planning by undoing tracking and resetting plan state.
    private func returnToPlanning() async {
        guard let record = executionRecord else { return }
        isLoading = true

        do {
            // Reset plan states to draft for this month
            let planService = DIContainer.shared.makeMonthlyPlanService(modelContext: modelContext)
            let plans = try planService.fetchPlans(for: record.monthLabel)
            for plan in plans {
                plan.state = .draft
            }
            try modelContext.save()

            // Undo start tracking (respects undo window)
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            try executionService.undoStartTracking(record)

            // Refresh state and planning data
            executionRecord = record
            await loadExecutionRecord()
            await planningViewModel.loadMonthlyRequirements()
        } catch {
        }

        isLoading = false
    }

    /// Complete the current month and transition to planning for next month.
    private func finishMonth() async {
        guard let record = executionRecord else { return }

        // Set states FIRST to immediately switch view (before async work)
        isExecuting = false
        executionCoordinator.isExecuting = false

        do {
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            try await executionService.markComplete(record)

            // Update record and reload state
            executionRecord = record
            await loadExecutionRecord()
            await planningViewModel.loadMonthlyRequirements()
        } catch {
            // If completion fails, restore executing state
            isExecuting = true
            executionCoordinator.isExecuting = true
        }
    }

    private func updatePlanningMonthLabel() {
        let fallbackLabel = monthLabel(from: Date())
        guard let record = executionRecord else {
            planningViewModel.planningMonthLabel = fallbackLabel
            return
        }

        if record.status == .closed {
            planningViewModel.planningMonthLabel = nextMonthLabel(from: record.monthLabel) ?? fallbackLabel
        } else {
            planningViewModel.planningMonthLabel = fallbackLabel
        }
    }

    private func nextMonthLabel(from monthLabel: String) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: monthLabel),
              let nextDate = Calendar.current.date(byAdding: .month, value: 1, to: date) else {
            return nil
        }
        return formatter.string(from: nextDate)
    }

    private func monthLabel(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}
