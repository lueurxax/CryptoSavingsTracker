//
//  FixedBudgetPlanningView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 03/01/2026.
//

import SwiftUI
import Combine

/// Main view for Fixed Budget planning mode
struct FixedBudgetPlanningView: View {
    @ObservedObject var viewModel: FixedBudgetPlanningViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onEditGoal: ((UUID) -> Void)?

    init(viewModel: FixedBudgetPlanningViewModel, onEditGoal: ((UUID) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onEditGoal = onEditGoal
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Budget Card
                    BudgetSummaryCard(
                        monthlyBudget: viewModel.monthlyBudget,
                        currency: viewModel.currency,
                        feasibility: viewModel.feasibilityResult,
                        onEditBudget: { viewModel.showBudgetEditor = true }
                    )

                    // Feasibility Warning (if applicable)
                    if !viewModel.feasibilityResult.isFeasible {
                        InfeasibilityWarningCard(
                            result: viewModel.feasibilityResult,
                            onSuggestionTap: { suggestion in
                                viewModel.handleSuggestion(suggestion, onEditGoal: onEditGoal)
                            }
                        )
                    }

                    // Current Focus Card (if plan exists)
                    if let currentGoal = viewModel.currentFocusGoal {
                        CurrentFocusCard(
                            goalName: currentGoal.goalName,
                            emoji: currentGoal.emoji,
                            progress: currentGoal.progress,
                            contributed: currentGoal.contributed,
                            target: currentGoal.target,
                            currency: viewModel.currency,
                            estimatedCompletion: currentGoal.estimatedCompletion
                        )
                    }

                    // Schedule Section
                    if !viewModel.scheduleBlocks.isEmpty {
                        ScheduleSection(
                            blocks: viewModel.scheduleBlocks,
                            payments: viewModel.schedulePayments,
                            currency: viewModel.currency,
                            currentPaymentNumber: viewModel.currentPaymentNumber,
                            goalRemainingById: viewModel.goalRemainingById
                        )
                    }
                }
                .padding()
            }

            // Recalculating Overlay
            if viewModel.isRecalculating && !reduceMotion {
                RecalculatingOverlay()
            }

            // Toast Notification
            if viewModel.showToast {
                VStack {
                    Spacer()
                    ToastView(message: viewModel.toastMessage)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 20)
                }
                .animation(reduceMotion ? .none : .spring(duration: 0.3), value: viewModel.showToast)
            }
        }
        .sheet(isPresented: $viewModel.showBudgetEditor) {
            BudgetEditorSheet(
                budget: $viewModel.editingBudget,
                currency: viewModel.currency,
                minimumRequired: viewModel.minimumRequired,
                onSave: {
                    viewModel.saveBudget()
                },
                onCancel: {
                    viewModel.showBudgetEditor = false
                }
            )
        }
        .sheet(isPresented: $viewModel.showSetupSheet) {
            FixedBudgetSetupSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.pendingQuickFix) { quickFix in
            QuickFixConfirmationSheet(
                quickFix: quickFix,
                onConfirm: {
                    viewModel.applyQuickFix(quickFix)
                },
                onCancel: {
                    viewModel.pendingQuickFix = nil
                }
            )
        }
    }
}

// MARK: - Budget Summary Card

struct BudgetSummaryCard: View {
    let monthlyBudget: Double
    let currency: String
    let feasibility: FeasibilityResult
    let onEditBudget: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Monthly Budget")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Edit", action: onEditBudget)
                    .font(.subheadline)
            }

            Text(CurrencyFormatter.format(amount: monthlyBudget, currency: currency, maximumFractionDigits: 2))
                .font(.system(size: 32, weight: .bold, design: .rounded))

            // Feasibility status
            HStack(spacing: 6) {
                Image(systemName: feasibility.statusLevel.iconName)
                    .foregroundStyle(statusColor)
                Text(feasibility.statusDescription)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
            }
        }
        .padding()
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #else
        .background(Color.gray.opacity(0.1))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusColor: Color {
        switch feasibility.statusLevel {
        case .achievable: return .green
        case .atRisk: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Infeasibility Warning Card

struct InfeasibilityWarningCard: View {
    let result: FeasibilityResult
    let onSuggestionTap: (FeasibilitySuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Budget Shortfall")
                    .font(.headline)
            }

            Text("Your budget cannot meet all deadlines.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Infeasible goals
            ForEach(result.infeasibleGoals) { goal in
                HStack {
                    VStack(alignment: .leading) {
                        Text(goal.goalName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Needs \(goal.formattedRequired)/mo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Shortfall: \(goal.formattedShortfall)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.vertical, 4)
            }

            // Quick fix suggestions
            if !result.suggestions.isEmpty {
                Divider()
                Text("Quick fixes:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(result.suggestions) { suggestion in
                    Button {
                        onSuggestionTap(suggestion)
                    } label: {
                        HStack {
                            Image(systemName: suggestion.icon)
                            Text(suggestion.title)
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        #if os(iOS)
                        .background(Color(.tertiarySystemGroupedBackground))
                        #else
                        .background(Color.gray.opacity(0.15))
                        #endif
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Current Focus Card

struct CurrentFocusCard: View {
    let goalName: String
    let emoji: String?
    let progress: Double
    let contributed: Double
    let target: Double
    let currency: String
    let estimatedCompletion: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let safeProgress = progress.isFinite ? progress : 0
            let clampedProgress = min(max(safeProgress, 0), 1)
            HStack {
                Text("Current Focus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("NOW")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }

            HStack {
                if let emoji = emoji {
                    Text(emoji)
                        .font(.title2)
                }
                Text(goalName)
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            // Progress bar
            ProgressView(value: clampedProgress)
                .tint(.blue)

            HStack {
                Text(CurrencyFormatter.format(amount: contributed, currency: currency, maximumFractionDigits: 2))
                    .font(.subheadline)
                Text("of \(CurrencyFormatter.format(amount: target, currency: currency, maximumFractionDigits: 2))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((safeProgress * 100).rounded()))%")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            if let completion = estimatedCompletion {
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Completes: \(completion.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #else
        .background(Color.gray.opacity(0.1))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Schedule Section

struct ScheduleSection: View {
    let blocks: [ScheduledGoalBlock]
    let payments: [ScheduledPayment]
    let currency: String
    let currentPaymentNumber: Int
    let goalRemainingById: [UUID: Double]
    @State private var expandedGoalIds: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming Schedule")
                .font(.headline)

            if !blocks.isEmpty {
                TimelineStepper(blocks: blocks, currentPaymentNumber: currentPaymentNumber)
            }

            ForEach(blocks) { block in
                ScheduleBlockCard(
                    block: block,
                    currency: currency,
                    remainingAmount: goalRemainingById[block.goalId],
                    isCurrent: block.startPaymentNumber <= currentPaymentNumber &&
                              block.endPaymentNumber >= currentPaymentNumber,
                    isExpanded: expandedGoalIds.contains(block.goalId),
                    onToggle: {
                        if expandedGoalIds.contains(block.goalId) {
                            expandedGoalIds.remove(block.goalId)
                        } else {
                            expandedGoalIds.insert(block.goalId)
                        }
                    },
                    paymentDetails: paymentDetails(for: block.goalId)
                )
            }
        }
    }

    private func paymentDetails(for goalId: UUID) -> [(date: Date, amount: Double, paymentNumber: Int)] {
        payments.compactMap { payment in
            let amount = payment.contributions
                .filter { $0.goalId == goalId }
                .reduce(0) { $0 + $1.amount }
            guard amount > 0.01 else { return nil }
            return (payment.paymentDate, amount, payment.paymentNumber)
        }
    }
}

struct ScheduleBlockCard: View {
    let block: ScheduledGoalBlock
    let currency: String
    let remainingAmount: Double?
    let isCurrent: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let paymentDetails: [(date: Date, amount: Double, paymentNumber: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(block.dateRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("(\(block.paymentCount) payment\(block.paymentCount == 1 ? "" : "s"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isCurrent {
                    Text("NOW")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }

            HStack {
                if let emoji = block.emoji {
                    Text(emoji)
                }
                Text(block.goalName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            if let remainingAmount {
                Text("Planned: \(CurrencyFormatter.format(amount: block.totalAmount, currency: currency, maximumFractionDigits: 2)) of \(CurrencyFormatter.format(amount: remainingAmount, currency: currency, maximumFractionDigits: 2))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(CurrencyFormatter.format(amount: block.totalAmount, currency: currency, maximumFractionDigits: 2) + " total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let remainingAmount {
                let shortfall = max(remainingAmount - block.totalAmount, 0)
                if shortfall > 0.01 {
                    Text("Shortfall: \(CurrencyFormatter.format(amount: shortfall, currency: currency, maximumFractionDigits: 2))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if !paymentDetails.isEmpty {
                Button(action: onToggle) {
                    Text(isExpanded ? "Hide month-by-month" : "Show month-by-month")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(paymentDetails, id: \.paymentNumber) { detail in
                        HStack {
                            Text(detail.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(CurrencyFormatter.format(amount: detail.amount, currency: currency, maximumFractionDigits: 2))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let remainingAmount {
                        let shortfall = max(remainingAmount - block.totalAmount, 0)
                        if shortfall > 0.01 {
                            Text("Remaining after schedule: \(CurrencyFormatter.format(amount: shortfall, currency: currency, maximumFractionDigits: 2))")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .padding()
        #if os(iOS)
        .background(isCurrent ? Color.blue.opacity(0.1) : Color(.tertiarySystemGroupedBackground))
        #else
        .background(isCurrent ? Color.blue.opacity(0.1) : Color.gray.opacity(0.15))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct TimelineStepper: View {
    let blocks: [ScheduledGoalBlock]
    let currentPaymentNumber: Int

    var body: some View {
        GeometryReader { geo in
            let totalPayments = max(1, blocks.reduce(0) { $0 + $1.paymentCount })
            let markerPosition = CGFloat(min(max(currentPaymentNumber - 1, 0), totalPayments)) / CGFloat(totalPayments)

            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(blocks) { block in
                        let width = CGFloat(block.paymentCount) / CGFloat(totalPayments)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: geo.size.width * width, height: 10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                            )
                    }
                }

                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 2, height: 16)
                    .offset(x: geo.size.width * markerPosition)
            }
        }
        .frame(height: 16)
    }
}

// MARK: - Budget Editor Sheet

struct BudgetEditorSheet: View {
    @Binding var budget: Double
    let currency: String
    let minimumRequired: Double
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var budgetText: String = ""
    @State private var useMinimum: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Monthly Budget", text: $budgetText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif

                    Toggle("Use minimum required", isOn: $useMinimum)
                        .onChange(of: useMinimum) { _, newValue in
                            if newValue {
                                budgetText = String(format: "%.2f", minimumRequired)
                            }
                        }
                } header: {
                    Text("Monthly Savings Amount")
                } footer: {
                    Text("Minimum required: \(CurrencyFormatter.format(amount: minimumRequired, currency: currency, maximumFractionDigits: 2))")
                }
            }
            .navigationTitle("Edit Budget")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value = Double(budgetText) {
                            budget = value
                        }
                        onSave()
                    }
                }
            }
            .onAppear {
                budgetText = String(format: "%.2f", budget)
            }
        }
    }
}

// MARK: - Setup Sheet

struct FixedBudgetSetupSheet: View {
    @ObservedObject var viewModel: FixedBudgetPlanningViewModel
    @State private var step: Int = 1

    var body: some View {
        NavigationStack {
            VStack {
                if step == 1 {
                    SetupStep1View(
                        budget: $viewModel.editingBudget,
                        currency: viewModel.currency,
                        minimumRequired: viewModel.minimumRequired,
                        onContinue: { step = 2 }
                    )
                } else {
                    SetupStep2View(
                        completionBehavior: $viewModel.completionBehavior,
                        onDone: {
                            viewModel.completeSetup()
                        },
                        onBack: { step = 1 }
                    )
                }
            }
            .navigationTitle(step == 1 ? "Set Your Budget" : "Completion Behavior")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelSetup()
                    }
                }
            }
        }
    }
}

struct SetupStep1View: View {
    @Binding var budget: Double
    let currency: String
    let minimumRequired: Double
    let onContinue: () -> Void

    @State private var budgetText: String = ""
    @State private var useMinimum: Bool = false

    var body: some View {
        Form {
            Section {
                Text("How much can you save each month?")
                    .font(.headline)

                TextField("Amount", text: $budgetText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .font(.title2)

                Toggle("Use minimum required", isOn: $useMinimum)
                    .onChange(of: useMinimum) { _, newValue in
                        if newValue {
                            budgetText = String(format: "%.0f", minimumRequired)
                        }
                    }
            } footer: {
                Text("Suggested minimum: \(CurrencyFormatter.format(amount: minimumRequired, currency: currency, maximumFractionDigits: 2))")
            }

            Section {
                Button("Continue") {
                    if let value = Double(budgetText) {
                        budget = value
                    }
                    onContinue()
                }
                .frame(maxWidth: .infinity)
                .disabled(budgetText.isEmpty)
            }
        }
        .onAppear {
            budgetText = budget > 0 ? String(format: "%.0f", budget) : ""
        }
    }
}

struct SetupStep2View: View {
    @Binding var completionBehavior: CompletionBehavior
    let onDone: () -> Void
    let onBack: () -> Void

    var body: some View {
        Form {
            Section {
                Text("What should happen when you complete a goal ahead of schedule?")
                    .font(.headline)
            }

            Section {
                ForEach(CompletionBehavior.allCases, id: \.self) { behavior in
                    Button {
                        completionBehavior = behavior
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(behavior.displayName)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(behavior.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if completionBehavior == behavior {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } footer: {
                Text("You can change this anytime in settings.")
            }

            Section {
                HStack {
                    Button("Back", action: onBack)
                    Spacer()
                    Button("Done", action: onDone)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Quick Fix Model

struct PendingQuickFix: Identifiable {
    let id = UUID()
    let suggestion: FeasibilitySuggestion
    let goalId: UUID
    let goalName: String

    var title: String {
        switch suggestion {
        case .extendDeadline(_, _, let months):
            return "Extend \(goalName) by \(months) month\(months == 1 ? "" : "s")"
        case .reduceTarget(_, _, let to, let currency):
            return "Reduce \(goalName) target to \(CurrencyFormatter.format(amount: to, currency: currency, maximumFractionDigits: 2))"
        case .increaseBudget:
            return suggestion.title
        }
    }

    var description: String {
        switch suggestion {
        case .extendDeadline(_, _, let months):
            return "This will move the deadline forward by \(months) month\(months == 1 ? "" : "s"), giving you more time to reach this goal."
        case .reduceTarget(_, _, let to, let currency):
            return "This will lower the target amount to \(CurrencyFormatter.format(amount: to, currency: currency, maximumFractionDigits: 2)), making the goal achievable with your current budget."
        case .increaseBudget(let to, let currency):
            return "This will increase your monthly budget to \(CurrencyFormatter.format(amount: to, currency: currency, maximumFractionDigits: 2))."
        }
    }

    var actionButtonLabel: String {
        switch suggestion {
        case .extendDeadline:
            return "Extend Deadline"
        case .reduceTarget:
            return "Reduce Target"
        case .increaseBudget:
            return "Increase Budget"
        }
    }
}

// MARK: - Quick Fix Confirmation Sheet

struct QuickFixConfirmationSheet: View {
    let quickFix: PendingQuickFix
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: quickFix.suggestion.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                // Title
                Text(quickFix.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                // Description
                Text(quickFix.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button(action: onConfirm) {
                        Text(quickFix.actionButtonLabel)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Cancel", action: onCancel)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Confirm Quick Fix")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Recalculating Overlay

/// Loading overlay shown during schedule recalculation
struct RecalculatingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)

                Text("Updating schedule...")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityLabel("Recalculating schedule")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Toast View

/// Simple toast notification for feedback
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.8))
            .clipShape(Capsule())
            .shadow(radius: 4)
            .accessibilityLabel(message)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - View Model

@MainActor
class FixedBudgetPlanningViewModel: ObservableObject {
    @Published var monthlyBudget: Double = 0
    @Published var editingBudget: Double = 0
    @Published var currency: String = "USD"
    @Published var minimumRequired: Double = 0
    @Published var feasibilityResult: FeasibilityResult = .empty
    @Published var scheduleBlocks: [ScheduledGoalBlock] = []
    @Published var schedulePayments: [ScheduledPayment] = []
    @Published var goalRemainingById: [UUID: Double] = [:]
    @Published var currentFocusGoal: CurrentFocusInfo?
    @Published var currentPaymentNumber: Int = 1
    @Published var completionBehavior: CompletionBehavior = .finishFaster

    @Published var showBudgetEditor: Bool = false
    @Published var showSetupSheet: Bool = false
    @Published var pendingQuickFix: PendingQuickFix?

    // Recalculation feedback
    @Published var isRecalculating: Bool = false
    @Published var showToast: Bool = false
    @Published var toastMessage: String = ""

    private let service: FixedBudgetPlanningService
    private let settings: MonthlyPlanningSettings
    private var goals: [Goal] = []

    struct CurrentFocusInfo: Identifiable {
        let id = UUID()
        let goalName: String
        let emoji: String?
        let progress: Double
        let contributed: Double
        let target: Double
        let estimatedCompletion: Date?
    }

    init(service: FixedBudgetPlanningService, settings: MonthlyPlanningSettings = .shared) {
        self.service = service
        self.settings = settings
        loadSettings()
    }

    func loadSettings() {
        monthlyBudget = settings.monthlyBudget ?? 0
        editingBudget = monthlyBudget
        currency = settings.budgetCurrency
        completionBehavior = settings.completionBehavior

        if !settings.hasCompletedFixedBudgetOnboarding && monthlyBudget == 0 {
            showSetupSheet = true
        }
    }

    func loadGoals(_ goals: [Goal]) async {
        self.goals = goals
        await refreshCalculations()
    }

    func refreshCalculations() async {
        guard !goals.isEmpty else { return }

        let oldBlockCount = scheduleBlocks.count

        // Show recalculating state (respecting reduce motion)
        isRecalculating = true
        defer { isRecalculating = false }

        minimumRequired = await service.calculateMinimumBudget(goals: goals, currency: currency)
        feasibilityResult = await service.checkFeasibility(goals: goals, budget: monthlyBudget, currency: currency)

        if monthlyBudget > 0 {
            let plan = await service.generateSchedule(goals: goals, budget: monthlyBudget, currency: currency)

            // Animate schedule changes
            withAnimation(.spring(duration: 0.3)) {
                scheduleBlocks = service.buildTimelineBlocks(from: plan, goals: goals)
                schedulePayments = plan.schedule
            }
            goalRemainingById = plan.goalRemainingById
            updateCurrentFocus(from: plan)

            // Show toast if schedule changed
            if scheduleBlocks.count != oldBlockCount && oldBlockCount > 0 {
                showRecalculationToast("Schedule updated")
            }
        } else {
            withAnimation(.spring(duration: 0.3)) {
                scheduleBlocks = []
                schedulePayments = []
            }
            goalRemainingById = [:]
        }
    }

    private func showRecalculationToast(_ message: String) {
        toastMessage = message
        showToast = true

        // Auto-dismiss after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showToast = false
        }
    }

    private func updateCurrentFocus(from plan: FixedBudgetPlan) {
        guard let firstPayment = plan.schedule.first,
              let firstContribution = firstPayment.contributions.first else {
            currentFocusGoal = nil
            return
        }

        let goal = goals.first { $0.id == firstContribution.goalId }
        let targetAmount = goal?.targetAmount ?? 0
        let rawProgress = targetAmount > 0 ? (firstContribution.runningTotal / targetAmount) : 0

        currentFocusGoal = CurrentFocusInfo(
            goalName: firstContribution.goalName,
            emoji: goal?.emoji,
            progress: rawProgress,
            contributed: firstContribution.runningTotal,
            target: targetAmount,
            estimatedCompletion: plan.schedule.first { payment in
                payment.contributions.contains { $0.goalId == firstContribution.goalId && $0.isGoalComplete }
            }?.paymentDate
        )
    }

    func saveBudget() {
        monthlyBudget = editingBudget
        settings.monthlyBudget = monthlyBudget
        showBudgetEditor = false

        Task {
            await refreshCalculations()
        }
    }

    /// Handle a suggestion tap - either apply directly or show confirmation
    func handleSuggestion(_ suggestion: FeasibilitySuggestion, onEditGoal: ((UUID) -> Void)?) {
        switch suggestion {
        case .increaseBudget(let to, _):
            // Apply directly
            editingBudget = to
            monthlyBudget = to
            settings.monthlyBudget = to
            Task {
                await refreshCalculations()
            }

        case .extendDeadline(let goalId, let goalName, _):
            // Show confirmation sheet
            pendingQuickFix = PendingQuickFix(suggestion: suggestion, goalId: goalId, goalName: goalName)

        case .reduceTarget(let goalId, let goalName, _, _):
            // Show confirmation sheet
            pendingQuickFix = PendingQuickFix(suggestion: suggestion, goalId: goalId, goalName: goalName)
        }
    }

    /// Apply the confirmed quick fix
    func applyQuickFix(_ quickFix: PendingQuickFix) {
        pendingQuickFix = nil

        Task {
            guard let goal = goals.first(where: { $0.id == quickFix.goalId }) else { return }

            switch quickFix.suggestion {
            case .extendDeadline(_, _, let months):
                // Extend the goal's deadline
                let calendar = Calendar.current
                if let newDeadline = calendar.date(byAdding: .month, value: months, to: goal.deadline) {
                    goal.deadline = newDeadline
                }

            case .reduceTarget(_, _, let newTarget, _):
                // Reduce the goal's target
                goal.targetAmount = newTarget

            case .increaseBudget(let to, _):
                // This shouldn't happen but handle it anyway
                monthlyBudget = to
                settings.monthlyBudget = to
            }

            await refreshCalculations()
        }
    }

    /// Legacy method for backwards compatibility
    func applySuggestion(_ suggestion: FeasibilitySuggestion) {
        handleSuggestion(suggestion, onEditGoal: nil)
    }

    func completeSetup() {
        settings.monthlyBudget = editingBudget
        settings.completionBehavior = completionBehavior
        settings.hasCompletedFixedBudgetOnboarding = true
        monthlyBudget = editingBudget
        showSetupSheet = false

        Task {
            await refreshCalculations()
        }
    }

    func cancelSetup() {
        showSetupSheet = false
        settings.planningMode = .perGoal
    }
}
