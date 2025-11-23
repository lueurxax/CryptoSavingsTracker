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
    @State private var executionRecord: MonthlyExecutionRecord?
    @State private var isLoading = true
    @State private var showStartTrackingConfirmation = false
    @StateObject private var planningViewModel: MonthlyPlanningViewModel

    init() {
        let context = CryptoSavingsTrackerApp.sharedModelContainer.mainContext
        let viewModel = MonthlyPlanningViewModel(modelContext: context)
        _planningViewModel = StateObject(wrappedValue: viewModel)
        AppLog.debug("MonthlyPlanningContainer init, viewModel identity: \(ObjectIdentifier(viewModel))", category: .monthlyPlanning)
    }

    var body: some View {
        VStack(spacing: 0) {
            // State indicator banner
            if let record = executionRecord {
                stateIndicatorBanner(for: record)
            }

            Group {
                if isLoading {
                    ProgressView("Loading...")
                } else if let record = executionRecord, record.status == .executing || record.status == .closed {
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
            await loadExecutionRecord()
            // Also load monthly requirements after execution record is loaded
            await planningViewModel.loadMonthlyRequirements()
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
    private func stateIndicatorBanner(for record: MonthlyExecutionRecord) -> some View {
        let isTracking = record.status == .executing || record.status == .closed

        HStack(spacing: 12) {
            Image(systemName: isTracking ? "chart.line.uptrend.xyaxis" : "doc.text")
                .font(.title3)
                .foregroundColor(isTracking ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(isTracking ? "Tracking Mode" : "Planning Mode")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(isTracking ? "Recording contributions for \(formatMonthLabel(record.monthLabel))" : "Planning for \(formatMonthLabel(record.monthLabel))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if record.status == .closed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
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

        do {
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            executionRecord = try executionService.getCurrentMonthRecord()
        } catch {
            print("Error loading execution record: \(error)")
        }

        isLoading = false
    }

    private func startTracking() async {
        do {
            // 1. Fetch active goals
            let descriptor = FetchDescriptor<Goal>(
                predicate: #Predicate { goal in
                    goal.archivedDate == nil
                }
            )
            let goals = try modelContext.fetch(descriptor)
            AppLog.debug("Found \(goals.count) active goals", category: .executionTracking)

            // 2. Get MonthlyPlanService through DI
            let planService = DIContainer.shared.makeMonthlyPlanService(modelContext: modelContext)

            // 3. Get or create plans (serialized via AsyncSerialExecutor)
            let plans = try await planService.getOrCreatePlansForCurrentMonth(goals: goals)
            AppLog.info("Using \(plans.count) persisted plans for execution", category: .executionTracking)

            // 3.5. Check if plans are already in non-draft state and reset if needed
            let nonDraftPlans = plans.filter { $0.state != .draft }
            if !nonDraftPlans.isEmpty {
                AppLog.warning("Found \(nonDraftPlans.count) non-draft plans, resetting to draft state", category: .executionTracking)
                for plan in nonDraftPlans {
                    plan.state = .draft
                }
                try modelContext.save()
            }

            // 4. Apply flex adjustments from ViewModel to plans
            // This ensures the plans have the correct customAmount set based on user's flex settings
            AppLog.debug("Applying flex adjustments: \(Int(planningViewModel.flexAdjustment * 100))%", category: .executionTracking)

            try await planService.applyBulkFlexAdjustment(
                plans: plans,
                adjustment: planningViewModel.flexAdjustment,
                protectedGoalIds: planningViewModel.protectedGoalIds,
                skippedGoalIds: planningViewModel.skippedGoalIds
            )

            // 5. Validate plans before transition
            try planService.validatePlansForExecution(plans)

            // 6. Log the effective amounts for debugging
            for plan in plans {
                AppLog.debug("Plan validated - goalId: \(plan.goalId), effectiveAmount: \(plan.effectiveAmount), customAmount: \(plan.customAmount ?? -1), requiredMonthly: \(plan.requiredMonthly)",
                            category: .executionTracking)
            }

            // 7. Transition plans from draft to executing
            try planService.startExecution(for: plans)

            // 8. Create execution record with snapshot
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())

            AppLog.info("Starting tracking for month: \(monthLabel)", category: .executionTracking)
            let record = try executionService.startTracking(
                for: monthLabel,
                from: plans,
                goals: goals
            )

            // 9. Verify snapshot
            if let snapshot = record.snapshot {
                AppLog.info("Created execution record with \(snapshot.goalSnapshots.count) goals, total: \(snapshot.totalPlanned)",
                           category: .executionTracking)
                for goalSnapshot in snapshot.goalSnapshots {
                    AppLog.debug("Snapshot: \(goalSnapshot.goalName) - \(goalSnapshot.plannedAmount) \(goalSnapshot.currency)",
                                category: .executionTracking)
                }
            } else {
                AppLog.error("Snapshot is nil!", category: .executionTracking)
            }

            executionRecord = record

        } catch {
            AppLog.error("Failed to start tracking: \(error)", category: .executionTracking)
            // TODO: Show error to user
        }
    }
}
