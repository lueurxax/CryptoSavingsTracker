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
    @State private var showingCurrencyPicker = false
    @State private var showingAssetPicker = false
    @State private var showingAllocationSheet = false
    @State private var selectedGoalSnapshot: ExecutionGoalSnapshot?
    @State private var selectedAsset: Asset?
    @State private var selectedAllocationAsset: Asset?
    @State private var suggestedAmount: Double?
    @State private var isComputingSuggestion = false

    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: MonthlyExecutionViewModel(modelContext: modelContext))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Combined Progress Header
                progressHeaderSection

                // Undo Banner
                if viewModel.showUndoBanner {
                    undoBanner
                }

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
        .sheet(isPresented: $showingCurrencyPicker) {
            SearchableCurrencyPicker(
                selectedCurrency: $viewModel.displayCurrency,
                pickerType: .fiat
            )
        }
        .sheet(isPresented: $showingAssetPicker) {
            if let goalSnapshot = selectedGoalSnapshot {
                let assets = viewModel.assetsForContribution(goalId: goalSnapshot.goalId)
                NavigationView {
                    Group {
                        if assets.isEmpty {
                            Text("No assets available. Add an asset first.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List(assets, id: \.id) { asset in
                                Button {
                                    showingAssetPicker = false
                                    if asset.allocations.count > 1 {
                                        selectedAllocationAsset = asset
                                        showingAllocationSheet = true
                                    } else {
                                        beginSuggestedContribution(for: goalSnapshot, asset: asset)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "bitcoinsign.circle")
                                        Text(asset.currency)
                                        Spacer()
                                        if asset.allocations.count > 1 {
                                            Image(systemName: "chart.pie.fill")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .accessibilityIdentifier("assetPickerCell-\(asset.currency)")
                            }
                        }
                    }
                    .navigationTitle("Select Asset")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingAssetPicker = false }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedAsset != nil },
            set: { if !$0 { selectedAsset = nil } }
        )) {
            if let asset = selectedAsset, let goalSnapshot = selectedGoalSnapshot {
                AddTransactionView(
                    asset: asset,
                    prefillAmount: suggestedAmount,
                    autoAllocateGoalId: goalSnapshot.goalId
                )
            }
        }
        .sheet(isPresented: $showingAllocationSheet, onDismiss: {
            selectedAllocationAsset = nil
        }) {
            if let asset = selectedAllocationAsset, let goalSnapshot = selectedGoalSnapshot {
                AssetSharingView(
                    asset: asset,
                    currentGoalId: goalSnapshot.goalId,
                    prefillCloseMonthGoalId: goalSnapshot.goalId
                )
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if isComputingSuggestion {
                ProgressView("Calculating...")
            }
        }
    }

    // MARK: - Combined Progress Header Section

    private var progressHeaderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title row with month
            HStack {
                Image(systemName: viewModel.statusIcon)
                    .font(.title2)
                    .foregroundStyle(.primary)
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

            // Progress bar
            let pct = min(max(viewModel.overallProgress, 0), 100)
            ProgressView(value: pct, total: 100)
                .tint(.green)
                .scaleEffect(y: 1.5)

            HStack {
                Text("Display Currency")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingCurrencyPicker = true
                } label: {
                    Text(viewModel.displayCurrency)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("executionDisplayCurrencyButton")
            }

            if let updatedAt = viewModel.displayRateUpdatedAt {
                Text(rateUpdateLabel(updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if viewModel.hasRateConversionWarning {
                Label("Some rates unavailable. Showing goal currency for those goals.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if let focus = viewModel.currentFocusGoal {
                Text("Current focus: \(focus.goalName) (until \(formatFocusDate(focus.deadline)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Stats row
            HStack {
                let stats = MonthlyExecutionStatistics(
                    totalPlanned: viewModel.displayTotalPlanned,
                    totals: viewModel.contributedTotals,
                    fulfillment: viewModel.fulfillmentStatus,
                    goalsCount: viewModel.displayGoalCount
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(viewModel.overallProgress))%")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(viewModel.overallProgress >= 100 ? .green : .primary)
                    Text("complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .center, spacing: 2) {
                    Text("\(stats.fulfilledCount)/\(stats.goalsCount)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("goals funded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCurrency(viewModel.displayTotalPlanned))
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("planned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let totalRemaining = viewModel.displayTotalRemaining {
                Text("Remaining this month: \(formatCurrency(totalRemaining, currency: viewModel.displayCurrency))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if viewModel.hasRateConversionWarning {
                Text("Remaining this month: unavailable (rate missing)")
                    .font(.caption)
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
                    let remainingToClose = viewModel.remainingToClose(for: goalSnapshot)
                    GoalProgressCard(
                        goalSnapshot: goalSnapshot,
                        contributed: viewModel.contributedTotals[goalSnapshot.goalId] ?? 0,
                        isFulfilled: false,
                        isClosedForGoal: remainingToClose <= 0,
                        remainingDisplayAmount: viewModel.remainingDisplayAmount(for: goalSnapshot),
                        displayCurrency: viewModel.remainingDisplayCurrency(for: goalSnapshot),
                        viewModel: viewModel,
                        onAddContribution: (viewModel.isActive && remainingToClose > 0) ? {
                            selectedGoalSnapshot = goalSnapshot
                            showingAssetPicker = true
                        } : nil
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
                                isClosedForGoal: true,
                                remainingDisplayAmount: viewModel.remainingDisplayAmount(for: goalSnapshot),
                                displayCurrency: viewModel.remainingDisplayCurrency(for: goalSnapshot),
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
                    if UITestFlags.isEnabled {
                        Task {
                            await viewModel.markComplete()
                        }
                    } else {
                        showCompleteConfirmation = true
                    }
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

    private func formatCurrency(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(amount)"
    }

    private func rateUpdateLabel(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return "Rates updated \(relative)"
    }

    private func formatFocusDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
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

    private func beginSuggestedContribution(for goalSnapshot: ExecutionGoalSnapshot, asset: Asset) {
        isComputingSuggestion = true
        Task {
            let suggestion = await viewModel.suggestedDepositAmount(
                for: asset.currency,
                goalSnapshot: goalSnapshot
            )
            suggestedAmount = suggestion
            selectedAsset = asset
            isComputingSuggestion = false
        }
    }
}

// MARK: - Goal Progress Card

struct GoalProgressCard: View {
    let goalSnapshot: ExecutionGoalSnapshot
    let contributed: Double
    let isFulfilled: Bool
    let isClosedForGoal: Bool
    let remainingDisplayAmount: Double?
    let displayCurrency: String
    let viewModel: MonthlyExecutionViewModel
    let onAddContribution: (() -> Void)?

    private var progressPercentage: Int {
        let total = max(goalSnapshot.plannedAmount, 0.0001)
        return Int(min(contributed / total * 100, 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row
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
                } else {
                    Text("\(progressPercentage)%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar
            let total = max(goalSnapshot.plannedAmount, 0.0001)
            let safeContributed = min(max(contributed, 0), total)
            ProgressView(value: safeContributed, total: total)
                .tint(isFulfilled ? .green : .blue)

            // Amount row - simplified, no redundant "remaining"
            Text("\(formatCurrency(contributed, currency: goalSnapshot.currency)) / \(formatCurrency(goalSnapshot.plannedAmount, currency: goalSnapshot.currency))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let remainingDisplayAmount, remainingDisplayAmount > 0 {
                Text("Remaining to close: \(formatCurrency(remainingDisplayAmount, currency: displayCurrency))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if isClosedForGoal && !isFulfilled {
                Text("Month already closed for this goal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("goalClosedMessage-\(goalSnapshot.goalId.uuidString)")
            }

            if let onAddContribution, !isFulfilled {
                Button {
                    onAddContribution()
                } label: {
                    Text("Add to Close Month")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("addToCloseMonthButton-\(goalSnapshot.goalName)")
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
