//
//  MonthlyExecutionView.swift
//  CryptoSavingsTracker
//
//  Created for v2.1 - Monthly Planning Execution & Tracking
//  Main view for tracking monthly execution progress
//

import SwiftUI
import SwiftData

struct MonthlyExecutionView: View {
    @StateObject private var viewModel: MonthlyExecutionViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var showCompleteConfirmation = false
    @State private var showCompletedSection = true

    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: MonthlyExecutionViewModel(modelContext: modelContext))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection

                // Undo Banner
                if viewModel.showUndoBanner {
                    undoBanner
                }

                // Overall Progress
                overallProgressSection

                // Active Goals (unfulfilled)
                activeGoalsSection

                // Completed Goals (fulfilled)
                completedGoalsSection

                // Action Buttons
                actionButtons
            }
            .padding()
        }
        .navigationTitle("Monthly Execution")
        .task {
            await viewModel.loadCurrentMonth()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .alert("Complete this month?", isPresented: $showCompleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Finish Month") {
                Task {
                    await viewModel.markComplete()
                }
            }
        } message: {
            Text(completeConfirmationMessage)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: viewModel.statusIcon)
                    .font(.title2)
                Text(viewModel.statusDisplay)
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if let record = viewModel.executionRecord {
                    Text(formatMonthLabel(record.monthLabel))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            let goalCount = viewModel.displayGoalCount
            let planned = viewModel.displayTotalPlanned
            Text("\(goalCount) active goals • \(formatCurrency(planned)) planned")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Undo Banner

    private var undoBanner: some View {
        HStack {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundStyle(.blue)

            VStack(alignment: .leading) {
                Text("Action started")
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let expiresAt = viewModel.undoExpiresAt {
                    Text("Undo expires in \(timeRemaining(until: expiresAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Undo") {
                Task {
                    await viewModel.undoStateChange()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Overall Progress

    private var overallProgressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overall Progress")
                .font(.headline)

            let pct = min(max(viewModel.overallProgress, 0), 100)
            ProgressView(value: pct, total: 100)
                .tint(.green)

            HStack {
                Text("\(Int(viewModel.overallProgress))% complete")
                    .font(.subheadline)

                Spacer()

                let stats = MonthlyExecutionStatistics(
                    totalPlanned: viewModel.displayTotalPlanned,
                    totals: viewModel.contributedTotals,
                    fulfillment: viewModel.fulfillmentStatus,
                    goalsCount: viewModel.displayGoalCount
                )
                Text("\(stats.fulfilledCount) of \(stats.goalsCount) goals funded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Active Goals Section

    private var activeGoalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Goals (\(viewModel.activeGoals.count))")
                .font(.headline)

            if viewModel.activeGoals.isEmpty {
                // Show different messages based on whether there were any goals to begin with
                if let snapshot = viewModel.snapshot, snapshot.goalCount > 0 {
                    Text("All goals funded! 🎉")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    VStack(spacing: 16) {
                        Text("No goals in this month's plan")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("This may happen if the execution was started before the plan was properly saved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if viewModel.showUndoBanner {
                            Button("Reset to Planning Mode") {
                                Task {
                                    await viewModel.undoStateChange()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                }
            } else {
                ForEach(viewModel.activeGoals, id: \.goalId) { goalSnapshot in
                    GoalProgressCard(
                        goalSnapshot: goalSnapshot,
                        contributed: viewModel.contributedTotals[goalSnapshot.goalId] ?? 0,
                        isFulfilled: false,
                        viewModel: viewModel,
                        onAddContribution: nil
                    )
                }
            }
        }
        .padding()
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Completed Goals Section

    private var completedGoalsSection: some View {
        Group {
            if !viewModel.completedGoals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: { showCompletedSection.toggle() }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Completed This Month (\(viewModel.completedGoals.count))")
                                .font(.headline)
                            Spacer()
                            Image(systemName: showCompletedSection ? "chevron.up" : "chevron.down")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if showCompletedSection {
                        ForEach(viewModel.completedGoals, id: \.goalId) { goalSnapshot in
                            GoalProgressCard(
                                goalSnapshot: goalSnapshot,
                                contributed: viewModel.contributedTotals[goalSnapshot.goalId] ?? 0,
                                isFulfilled: true,
                                viewModel: viewModel,
                                onAddContribution: nil // No button for completed goals
                            )
                        }
                    }
                }
                .padding()
                #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
                .cornerRadius(12)
                .shadow(radius: 2)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if viewModel.isActive {
                Button {
                    showCompleteConfirmation = true
                } label: {
                    Label("Finish This Month", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("finishMonthButton")
            }

            if viewModel.isClosed {
                Text("This month is closed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top)
    }

    // MARK: - Helpers

    private var completeConfirmationMessage: String {
        let stats = MonthlyExecutionStatistics(
            totalPlanned: viewModel.displayTotalPlanned,
            totals: viewModel.contributedTotals,
            fulfillment: viewModel.fulfillmentStatus,
            goalsCount: viewModel.displayGoalCount
        )

        if stats.percentageComplete < 100 {
            return "Progress: \(formatCurrency(stats.totalContributed)) of \(formatCurrency(stats.totalPlanned)) (\(Int(stats.percentageComplete))%)\n\nNot fully funded. The remaining amount will roll into next month's calculations."
        } else {
            return "Progress: 100% complete! All goals have been funded for this month."
        }
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

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    private func timeRemaining(until date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Goal Progress Card

struct GoalProgressCard: View {
    let goalSnapshot: ExecutionGoalSnapshot
    let contributed: Double
    let isFulfilled: Bool
    let viewModel: MonthlyExecutionViewModel
    let onAddContribution: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(goalSnapshot.goalName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .accessibilityLabel(goalSnapshot.goalName)
                    .accessibilityIdentifier("goalCard-\(goalSnapshot.goalName)")

                Spacer()

                if isFulfilled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            let total = max(goalSnapshot.plannedAmount, 0.0001)
            let safeContributed = min(max(contributed, 0), total)
            ProgressView(value: safeContributed, total: total)
                .tint(isFulfilled ? .green : .blue)

            HStack {
                Text("\(formatCurrency(contributed, currency: goalSnapshot.currency)) / \(formatCurrency(goalSnapshot.plannedAmount, currency: goalSnapshot.currency))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !isFulfilled {
                    Text("\(formatCurrency(viewModel.remaining(for: goalSnapshot.goalId), currency: goalSnapshot.currency)) remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        #if os(macOS)
        .background(isFulfilled ? Color.green.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        #else
        .background(isFulfilled ? Color.green.opacity(0.1) : Color(.secondarySystemBackground))
        #endif
        .cornerRadius(8)
    }

    private func formatCurrency(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(amount)"
    }
}
