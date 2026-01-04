//
//  BudgetCalculatorSheet.swift
//  CryptoSavingsTracker
//
//  Bottom sheet for budget calculator preview and apply.
//

import SwiftUI
import SwiftData

struct BudgetCalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var viewModel: MonthlyPlanningViewModel

    @State private var budgetText: String = ""
    @State private var currency: String = "USD"
    @State private var showingCurrencyPicker = false
    @State private var isApplying = false
    @State private var isApplyingSuggestion = false
    @State private var editingGoal: Goal?
    @State private var selectedGoalBlock: ScheduledGoalBlock?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    budgetInputSection
                    feasibilitySection
                    previewSection
                    timelineSection
                    errorSection

                    if !canApply && !viewModel.budgetFeasibility.isFeasible {
                        Text("Resolve budget shortfall to save")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Saving will update contribution amounts for all active goals.")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
            }
            .navigationTitle("Budget Plan")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        applyBudget()
                    } label: {
                        Text("Save Budget Plan")
                            .fontWeight(.semibold)
                    }
                    .disabled(!canApply)
                }
            }
        }
        .sheet(isPresented: $showingCurrencyPicker) {
            SearchableCurrencyPicker(selectedCurrency: $currency, pickerType: .fiat)
        }
        .sheet(item: $editingGoal) { goal in
            EditGoalView(goal: goal, modelContext: goal.modelContext ?? modelContext)
        }
        .sheet(item: $selectedGoalBlock) { block in
            GoalPaymentScheduleSheet(
                block: block,
                plan: viewModel.budgetPreviewPlan,
                currency: currency
            )
        }
        .onAppear {
            currency = viewModel.budgetCurrency
            if viewModel.hasBudget {
                budgetText = String(format: "%.2f", viewModel.budgetAmount)
            }
            Task {
                await refreshPreview()
            }
        }
        .onChange(of: budgetText) { _, _ in
            Task {
                await refreshPreview()
            }
        }
        .onChange(of: currency) { _, _ in
            Task {
                await refreshPreview()
            }
        }
        .overlay {
            if viewModel.isBudgetPreviewLoading || isApplying {
                ProgressView(viewModel.isBudgetPreviewLoading ? "Calculating..." : "Applying...")
            }
        }
    }

    private var parsedBudget: Double? {
        let sanitized = budgetText.filter { $0.isNumber || $0 == "." }
        return Double(sanitized)
    }

    private var canApply: Bool {
        guard let amount = parsedBudget, amount > 0 else { return false }
        guard viewModel.budgetFeasibility.isFeasible else { return false }
        return viewModel.budgetPreviewPlan != nil && !viewModel.isBudgetPreviewLoading && !isApplying
    }

    private var budgetInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monthly Savings Budget")
                .font(.headline)

            HStack(spacing: 12) {
                Button {
                    showingCurrencyPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(currency)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                #if os(iOS)
                TextField("Amount", text: $budgetText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                #else
                TextField("Amount", text: $budgetText)
                    .textFieldStyle(.roundedBorder)
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var feasibilitySection: some View {
        let feasibility = viewModel.budgetFeasibility
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: feasibility.statusLevel.iconName)
                    .foregroundColor(feasibilityColor)
                Text(feasibility.statusDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !feasibility.isFeasible {
                Text("Minimum required: \(feasibility.formattedMinimum)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    budgetText = String(format: "%.2f", feasibility.minimumRequired)
                } label: {
                    Label("Use Minimum \(feasibility.formattedMinimum)", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                if !feasibility.infeasibleGoals.isEmpty {
                    Divider()
                    Text("Budget Shortfall")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ForEach(feasibility.infeasibleGoals) { goal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.goalName)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("Needs \(goal.formattedRequired)/mo")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("Shortfall: \(goal.formattedShortfall)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if !feasibility.suggestions.isEmpty {
                    Divider()
                    Text("Quick fixes")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ForEach(feasibility.suggestions) { suggestion in
                        if suggestion.isIncreaseBudget {
                            Button {
                                applySuggestion(suggestion)
                            } label: {
                                Label(suggestion.title, systemImage: suggestion.icon)
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isApplyingSuggestion)
                        } else {
                            Button {
                                applySuggestion(suggestion)
                            } label: {
                                Label(suggestion.title, systemImage: suggestion.icon)
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isApplyingSuggestion)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This Month's Contribution")
                .font(.headline)

            if let payment = viewModel.budgetPreviewPlan?.schedule.first, !payment.contributions.isEmpty {
                ForEach(payment.contributions) { contribution in
                    HStack {
                        Text(contribution.goalName)
                            .font(.subheadline)
                        Spacer()
                        Text(CurrencyFormatter.format(
                            amount: contribution.amount,
                            currency: currency,
                            maximumFractionDigits: 2
                        ))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    }
                }
            } else {
                Text("Enter a budget to preview contributions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Upcoming Schedule")
                    .font(.headline)
                HelpTooltip(
                    title: "Allocation Order",
                    description: "Goals are funded in order of deadline. The earliest deadline receives contributions first, ensuring all targets can be met.",
                    icon: "questionmark.circle"
                )
            }

            if viewModel.budgetPreviewTimeline.isEmpty {
                Text("Timeline preview will appear here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                BudgetTimelineBar(blocks: viewModel.budgetPreviewTimeline, currency: currency)

                ForEach(Array(viewModel.budgetPreviewTimeline.enumerated()), id: \.element.id) { index, block in
                    Button {
                        selectedGoalBlock = block
                    } label: {
                        HStack(alignment: .top) {
                            Circle()
                                .fill(timelineColor(for: index))
                                .frame(width: 10, height: 10)
                                .padding(.top, 4)
                            if let emoji = block.emoji {
                                Text(emoji)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(block.goalName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    if block.isComplete {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                                Text(block.dateRange)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 12) {
                                    Text("Total: \(CurrencyFormatter.format(amount: block.totalAmount, currency: currency, maximumFractionDigits: 0))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    if block.paymentCount > 0 {
                                        let monthlyAmount = block.totalAmount / Double(block.paymentCount)
                                        Label(
                                            "\(CurrencyFormatter.format(amount: monthlyAmount, currency: currency, maximumFractionDigits: 0))/mo",
                                            systemImage: "calendar"
                                        )
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(block.paymentCount) payments")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var errorSection: some View {
        Group {
            if let error = viewModel.budgetPreviewError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var feasibilityColor: Color {
        switch viewModel.budgetFeasibility.statusLevel {
        case .achievable: return .green
        case .atRisk: return .orange
        case .critical: return .red
        }
    }

    private func timelineColor(for index: Int) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .pink, .teal, .indigo]
        return palette[index % palette.count].opacity(0.6)
    }

    private func refreshPreview() async {
        guard let amount = parsedBudget else {
            viewModel.budgetPreviewPlan = nil
            viewModel.budgetPreviewTimeline = []
            viewModel.budgetPreviewError = nil
            return
        }
        await viewModel.previewBudget(amount: amount, currency: currency)
    }

    private func applyBudget() {
        guard let amount = parsedBudget, let plan = viewModel.budgetPreviewPlan else { return }
        isApplying = true
        Task {
            let applied = await viewModel.applyBudgetPlan(plan: plan, amount: amount, currency: currency)
            isApplying = false
            if applied {
                dismiss()
            }
        }
    }

    private func applySuggestion(_ suggestion: FeasibilitySuggestion) {
        switch suggestion {
        case .increaseBudget(let to, _):
            budgetText = String(format: "%.2f", to)
        case .editGoal(let goalId, _):
            editingGoal = viewModel.goals.first { $0.id == goalId }
        default:
            let amount = parsedBudget ?? 0
            isApplyingSuggestion = true
            Task {
                _ = await viewModel.applyFeasibilitySuggestion(
                    suggestion,
                    currentBudget: amount,
                    currency: currency
                )
                isApplyingSuggestion = false
                await refreshPreview()
            }
        }
    }
}

private struct BudgetTimelineBar: View {
    let blocks: [ScheduledGoalBlock]
    let currency: String
    @State private var selectedBlock: ScheduledGoalBlock?

    private var totalPayments: Double {
        let total = blocks.map(\.paymentCount).reduce(0, +)
        return max(1, Double(total))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            HStack(spacing: 4) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    let fraction = Double(block.paymentCount) / totalPayments
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color(for: index))
                        .frame(width: width * fraction, height: 10)
                        .onTapGesture {
                            selectedBlock = block
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 10)
        .popover(item: $selectedBlock) { block in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let emoji = block.emoji {
                        Text("\(emoji) \(block.goalName)")
                            .font(.headline)
                    } else {
                        Text(block.goalName)
                            .font(.headline)
                    }
                    if block.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Label(block.dateRange, systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Label("\(block.paymentCount) monthly payments", systemImage: "repeat")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Total: \(CurrencyFormatter.format(amount: block.totalAmount, currency: currency, maximumFractionDigits: 0))")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if block.paymentCount > 0 {
                        let monthlyAmount = block.totalAmount / Double(block.paymentCount)
                        Label(
                            "\(CurrencyFormatter.format(amount: monthlyAmount, currency: currency, maximumFractionDigits: 0))/month",
                            systemImage: "creditcard"
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }

    private func color(for index: Int) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .pink, .teal, .indigo]
        return palette[index % palette.count].opacity(0.6)
    }
}

// MARK: - Goal Payment Schedule Sheet

private struct GoalPaymentScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let block: ScheduledGoalBlock
    let plan: BudgetCalculatorPlan?
    let currency: String

    private var goalPayments: [(payment: ScheduledPayment, contribution: GoalContribution)] {
        guard let plan = plan else { return [] }
        var result: [(ScheduledPayment, GoalContribution)] = []
        for payment in plan.schedule {
            if let contribution = payment.contributions.first(where: { $0.goalId == block.goalId }) {
                result.append((payment, contribution))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryRow
                } header: {
                    Text("Summary")
                }

                Section {
                    ForEach(goalPayments, id: \.payment.id) { payment, contribution in
                        paymentRow(payment: payment, contribution: contribution)
                    }
                } header: {
                    Text("Payment Schedule")
                }
            }
            .navigationTitle(block.goalName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var summaryRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let emoji = block.emoji {
                    Text(emoji)
                        .font(.title)
                }
                VStack(alignment: .leading) {
                    Text(block.goalName)
                        .font(.headline)
                    Text(block.dateRange)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if block.isComplete {
                    Label("Completes", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(CurrencyFormatter.format(amount: block.totalAmount, currency: currency, maximumFractionDigits: 2))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Spacer()

                VStack(alignment: .leading) {
                    Text("Payments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(block.paymentCount)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Spacer()

                if block.paymentCount > 0 {
                    VStack(alignment: .leading) {
                        Text("Per Month")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        let monthlyAmount = block.totalAmount / Double(block.paymentCount)
                        Text(CurrencyFormatter.format(amount: monthlyAmount, currency: currency, maximumFractionDigits: 2))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func paymentRow(payment: ScheduledPayment, contribution: GoalContribution) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.formattedDateFull)
                    .font(.subheadline)
                HStack(spacing: 8) {
                    Text("Payment #\(payment.paymentNumber)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if contribution.isGoalComplete {
                        Text("Complete")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.format(amount: contribution.amount, currency: currency, maximumFractionDigits: 2))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Running: \(CurrencyFormatter.format(amount: contribution.runningTotal, currency: currency, maximumFractionDigits: 0))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
