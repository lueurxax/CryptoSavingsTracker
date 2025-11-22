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
        }
    }

    private var planningViewWithStartButton: some View {
        VStack(spacing: 0) {
            // Planning view in a ScrollView
            ScrollView {
                PlanningView(viewModel: MonthlyPlanningViewModel(modelContext: modelContext))
                    .frame(minHeight: 500, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            // Start Tracking button section - always visible at bottom
            VStack(spacing: 12) {
                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)

                    Text("Ready to commit to this plan?")
                        .font(.headline)

                    Spacer()
                }

                Text("This will lock in your monthly amounts and enable contribution tracking. You can undo this action within 24 hours.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showStartTrackingConfirmation = true
                } label: {
                    Label("Lock Plan & Start Tracking", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .background(.regularMaterial)
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
            // Fetch all active goals
            let descriptor = FetchDescriptor<Goal>(
                predicate: #Predicate { goal in
                    goal.archivedDate == nil
                }
            )
            let goals = try modelContext.fetch(descriptor)
            AppLog.debug("Found \(goals.count) active goals", category: .executionTracking)

            // Get or create plans using unified MonthlyPlanService
            let goalCalculationService = GoalCalculationService(
                container: DIContainer.shared,
                modelContext: modelContext
            )
            let planService = MonthlyPlanService(
                modelContext: modelContext,
                goalCalculationService: goalCalculationService
            )

            // This will either return existing draft plans or create new ones (with duplicate prevention)
            let plans = try await planService.getOrCreatePlansForCurrentMonth(goals: goals)
            AppLog.info("Using \(plans.count) persisted plans for execution", category: .executionTracking)

            // Verify plans before passing
            for plan in plans {
                AppLog.debug("Plan before tracking - goalId: \(plan.goalId), effectiveAmount: \(plan.effectiveAmount), currency: \(plan.currency), monthLabel: \(plan.monthLabel)", category: .executionTracking)
            }

            // Transition plans from draft to executing
            try planService.startExecution(for: plans)

            // Start tracking
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
            AppLog.info("Starting tracking for month: \(monthLabel)", category: .executionTracking)
            AppLog.debug("Passing \(plans.count) plans and \(goals.count) goals to startTracking()", category: .executionTracking)
            let record = try executionService.startTracking(for: monthLabel, from: plans, goals: goals)
            AppLog.debug("Created execution record with \(record.snapshot?.goalCount ?? 0) goals in snapshot", category: .executionTracking)

            // Check what's in the snapshot
            if let snapshot = record.snapshot {
                AppLog.debug("Snapshot details - totalPlanned: \(snapshot.totalPlanned), goalSnapshots.count: \(snapshot.goalSnapshots.count)", category: .executionTracking)
                for goalSnapshot in snapshot.goalSnapshots {
                    AppLog.debug("Goal snapshot - name: \(goalSnapshot.goalName), amount: \(goalSnapshot.plannedAmount), currency: \(goalSnapshot.currency)", category: .executionTracking)
                }
            } else {
                AppLog.error("Snapshot is nil!", category: .executionTracking)
            }

            executionRecord = record
        } catch {
            AppLog.error("Error starting tracking: \(error)", category: .executionTracking)
        }
    }
}
