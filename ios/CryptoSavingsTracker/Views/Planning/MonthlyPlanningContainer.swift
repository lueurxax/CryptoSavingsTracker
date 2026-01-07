//
//  MonthlyPlanningContainer.swift
//  CryptoSavingsTracker
//
//  Created for v2.1 - Monthly Planning Execution & Tracking
//  Container that switches between planning and execution views
//

import SwiftUI
import SwiftData

/// Container view that shows either planning or execution view based on state
struct MonthlyPlanningContainer: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        MonthlyPlanningContainerContent(modelContext: modelContext)
    }
}

/// Implementation detail that binds the container to a single `ModelContext`.
private struct MonthlyPlanningContainerContent: View {
    let modelContext: ModelContext
    @State private var executionRecord: MonthlyExecutionRecord?
    @State private var isLoading = true
    @State private var showStartTrackingConfirmation = false
    @State private var showReturnToPlanningConfirmation = false
    @State private var hasInitiallyLoaded = false
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

            Group {
                if isLoading {
                    ProgressView("Loading...")
                } else if let record = executionRecord, record.status == .executing {
                    // Show execution view
                    MonthlyExecutionView(modelContext: modelContext)
                } else {
                    // Show planning view with start tracking button
                    planningViewWithStartButton
                }
            }
        }
        .navigationTitle("Monthly Planning")
        .task {
            // Ensure UI test seed (if requested) completes before loading execution/planning state
            await CryptoSavingsTrackerApp.runUITestSeedIfNeeded(context: modelContext)
            await loadExecutionRecord()
            // Also load monthly requirements after execution record is loaded
            await planningViewModel.loadMonthlyRequirements()
        }
        .onReceive(NotificationCenter.default.publisher(for: .monthlyExecutionCompleted)) { notification in
            if let record = notification.object as? MonthlyExecutionRecord {
                executionRecord = record
            }
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
    }

    private var planningViewWithStartButton: some View {
        VStack(spacing: 0) {
            // Planning view in a ScrollView - takes available space
            PlanningView(viewModel: planningViewModel)
                .padding(.bottom, 20)
                .frame(maxHeight: .infinity)

            // Start Tracking button section - compact and responsive
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
            .frame(maxWidth: .infinity)
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

            // Bottom row: Primary action button (full width)
            if record.status == .executing {
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
            hasInitiallyLoaded = true
        }

        do {
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            if let activeRecord = try executionService.getActiveRecord() {
                executionRecord = activeRecord
            } else {
                executionRecord = try executionService.getCurrentMonthRecord()
            }
        } catch {
            print("Error loading execution record: \(error)")
        }

        updatePlanningMonthLabel()
        isLoading = false
    }

    private func startTracking() async {
        do {
            // 1. Fetch active goals
            let descriptor = FetchDescriptor<Goal>(
                predicate: #Predicate { goal in
                    goal.lifecycleStatusRawValue == "active"
                }
            )
            let goals = try modelContext.fetch(descriptor)
            // 2. Get MonthlyPlanService through DI
            let planService = DIContainer.shared.makeMonthlyPlanService(modelContext: modelContext)
            let monthLabel = planningViewModel.planningMonthLabel.isEmpty
                ? planService.currentMonthLabel()
                : planningViewModel.planningMonthLabel

            // 3. Get or create plans (serialized via AsyncSerialExecutor)
            let plans = try await planService.getOrCreatePlans(for: monthLabel, goals: goals)
            // 3.5. Check if plans are already in non-draft state and reset if needed
            let nonDraftPlans = plans.filter { $0.state != .draft }
            if !nonDraftPlans.isEmpty {
                for plan in nonDraftPlans {
                    plan.state = .draft
                }
                try modelContext.save()
            }

            // 4. Apply flex adjustments from ViewModel to plans
            // This ensures the plans have the correct customAmount set based on user's flex settings
            try await planService.applyBulkFlexAdjustment(
                plans: plans,
                adjustment: planningViewModel.flexAdjustment,
                protectedGoalIds: planningViewModel.protectedGoalIds,
                skippedGoalIds: planningViewModel.skippedGoalIds
            )

            // 5. Validate plans before transition
            try planService.validatePlansForExecution(plans)

            // 6. Transition plans from draft to executing
            try planService.startExecution(for: plans)

            // 7. Create execution record with snapshot
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)

            let record = try executionService.startTracking(
                for: monthLabel,
                from: plans,
                goals: goals
            )

            executionRecord = record

        } catch {
            // TODO: Show error to user
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
