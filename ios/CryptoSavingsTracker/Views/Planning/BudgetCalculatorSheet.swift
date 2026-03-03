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
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: MonthlyPlanningViewModel

    @State private var budgetText: String = ""
    @State private var currency: String = "USD"
    @State private var showingCurrencyPicker = false
    @State private var isApplying = false
    @State private var isApplyingSuggestion = false
    @State private var editingGoal: Goal?
    @State private var selectedGoalBlock: ScheduledGoalBlock?
    @State private var lastSubmittedMinorValue: Int64?
    @State private var lastSubmittedCurrency: String = "USD"
    @State private var initialBudgetFingerprint: String = ""
    @State private var showingDiscardConfirmation = false
    @State private var hasStartedTelemetryFlows = false
    @FocusState private var isAmountFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    budgetInputSection
                    feasibilitySection
                    previewSection
                    timelineSection
                    errorSection

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(AccessibleColors.primaryInteractive)
                        Text("Saving will update contribution amounts for all active goals.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("Budget Plan")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            trackCancel(stage: "toolbar_cancel")
                            showingDiscardConfirmation = true
                        } else {
                            trackCancel(stage: "toolbar_cancel")
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        applyBudget()
                    } label: {
                        Text("Save Budget Plan")
                            .fontWeight(.semibold)
                    }
                    .accessibilityIdentifier("saveBudgetPlanButton")
                    .disabled(!canApply)
                }
            }
        }
        // NAV-MOD: MOD-01
        .sheet(isPresented: $showingCurrencyPicker) {
            SearchableCurrencyPicker(selectedCurrency: $currency, pickerType: .fiat)
        }
        // NAV-MOD: MOD-01
        .sheet(item: $editingGoal) { goal in
            EditGoalView(goal: goal, modelContext: goal.modelContext ?? modelContext)
        }
        // NAV-MOD: MOD-01
        .sheet(item: $selectedGoalBlock) { block in
            GoalPaymentScheduleSheet(
                block: block,
                plan: viewModel.budgetPreviewPlan,
                currency: currency
            )
        }
        .onAppear {
            currency = viewModel.budgetCurrency
            lastSubmittedCurrency = currency.uppercased()
            if viewModel.hasBudget {
                let canonical = MoneyQuantizer.normalize(
                    Decimal(viewModel.budgetAmount),
                    currency: currency,
                    mode: .halfUp
                )
                budgetText = canonicalDecimalText(for: canonical)
            }
            Task {
                await refreshPreview()
            }
            if !hasStartedTelemetryFlows {
                hasStartedTelemetryFlows = true
                let tracker = DIContainer.shared.navigationTelemetryTracker
                tracker.flowStarted(
                    journeyID: NavigationJourney.monthlyBudgetAdjust,
                    entryPoint: "budget_calculator_sheet"
                )
                tracker.flowStarted(
                    journeyID: NavigationJourney.planningFlowCancelRecovery,
                    entryPoint: "budget_calculator_sheet"
                )
            }
            initialBudgetFingerprint = fingerprint(amount: parsedBudget, currency: currency)
        }
        .onChange(of: budgetText) { _, _ in
            Task {
                await refreshPreview()
            }
        }
        .onChange(of: currency) { _, _ in
            lastSubmittedMinorValue = nil
            lastSubmittedCurrency = currency.uppercased()
            Task {
                await refreshPreview(force: true)
            }
        }
        .onChange(of: isAmountFieldFocused) { _, isFocused in
            if !isFocused {
                normalizeDisplayTextIfPossible()
            }
        }
        .overlay {
            if viewModel.isBudgetPreviewLoading || isApplying {
                ProgressView(viewModel.isBudgetPreviewLoading ? "Calculating..." : "Applying...")
            }
        }
        .interactiveDismissDisabled(isDirty)
        // NAV-MOD: MOD-02
        .confirmationDialog(
            "Discard Budget Changes?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                DIContainer.shared.navigationTelemetryTracker.discardConfirmed(
                    journeyID: NavigationJourney.monthlyBudgetAdjust,
                    formType: "budget_plan"
                )
                dismiss()
            }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("Unsaved budget edits will be lost.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isAmountFieldFocused = false
                    normalizeDisplayTextIfPossible()
                }
                .accessibilityIdentifier("budgetKeyboardDoneButton")
            }
        }
    }

    private var parsedBudget: MoneyAmount? {
        parseResult.amount
    }

    private var parseResult: MoneyInputParseResult {
        MoneyInputParser.parse(
            rawText: budgetText,
            currency: currency,
            locale: locale,
            mode: .halfUp
        )
    }

    private var saveDisabledReason: String? {
        if let parseFailure = parseResult.failure {
            return parseFailure.message
        }
        if parsedBudget != nil, !isSnapshotCurrent {
            return "Calculating latest amount..."
        }
        if viewModel.isBudgetPreviewLoading {
            return "Calculating latest amount..."
        }
        return viewModel.budgetSaveDisabledReason
    }

    private var isSnapshotCurrent: Bool {
        guard let parsedBudget, let snapshot = viewModel.budgetComputationResult else { return false }
        return MoneyQuantizer.compare(parsedBudget, snapshot.enteredBudgetCanonical) == .orderedSame
    }

    private var canApply: Bool {
        guard let parsedBudget else { return false }
        guard let snapshot = viewModel.budgetComputationResult, snapshot.state == .readyFeasible else { return false }
        guard isSnapshotCurrent else { return false }
        guard MoneyQuantizer.compare(parsedBudget, snapshot.minimumRequiredCanonical) != .orderedAscending else { return false }
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
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("budgetCurrencyButton")

                #if os(iOS)
                TextField("Amount", text: $budgetText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($isAmountFieldFocused)
                    .accessibilityIdentifier("budgetAmountField")
                #else
                TextField("Amount", text: $budgetText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isAmountFieldFocused)
                    .accessibilityIdentifier("budgetAmountField")
                #endif

                if isAmountFieldFocused {
                    Button("Done") {
                        isAmountFieldFocused = false
                        normalizeDisplayTextIfPossible()
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("budgetKeyboardDoneButton")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var feasibilitySection: some View {
        let feasibility = viewModel.budgetFeasibility
        let state = viewModel.budgetComputationResult?.state
        let reduceMotion = reduceMotion

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: feasibility.statusLevel.iconName)
                    .foregroundStyle(feasibilityColor)
                Text(feasibility.statusDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("budgetFeasibilityStatusText")
            }

            if !canApply, let reason = saveDisabledReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(AccessibleColors.warning)
                    .accessibilityIdentifier("budgetShortfallSaveWarning")
            }

            if state == .blockedRates {
                Text("Rates unavailable for conversion. Refresh rates to validate this budget.")
                    .font(.caption)
                    .foregroundStyle(AccessibleColors.warning)

                Button {
                    Task { await refreshPreview(force: true) }
                } label: {
                    Label("Refresh Rates", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }

            if !viewModel.isBudgetPreviewLoading, isSnapshotCurrent, !feasibility.isFeasible {
                let minimumCanonical = viewModel.budgetComputationResult?.minimumRequiredCanonical
                    ?? MoneyQuantizer.normalize(
                        Decimal(feasibility.minimumRequired),
                        currency: currency,
                        mode: .up
                    )
                let minimumFormatted = CurrencyFormatter.format(amount: minimumCanonical)

                Text("Minimum required: \(minimumFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("budgetMinimumRequiredText")

                Button {
                    budgetText = canonicalDecimalText(for: minimumCanonical)
                    BudgetPlanAnalytics.log(.useMinimumTap)
                    Task {
                        await refreshPreview(force: true)
                    }
                } label: {
                    Label("Use Minimum \(minimumFormatted)", systemImage: "arrow.up.circle.fill")
                }
                .accessibilityIdentifier("useMinimumBudgetButton")
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBudgetPreviewLoading || !isSnapshotCurrent)

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
                                .foregroundStyle(.secondary)
                            Text("Shortfall: \(goal.formattedShortfall)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
        .frame(minHeight: 132, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(!canApply && saveDisabledReason != nil ? "budgetShortfallSaveWarning" : "budgetFeasibilityCard")
        .accessibilityLabel("Budget status")
        .accessibilityValue(feasibility.statusDescription)
        .accessibilityHint(canApply ? "Double tap to save budget plan." : "Resolve the issue before saving.")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state)
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
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
                    .foregroundStyle(.secondary)
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
                                            .foregroundStyle(AccessibleColors.success)
                                    }
                                }
                                Text(block.dateRange)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 12) {
                                    Text("Total: \(CurrencyFormatter.format(amount: block.totalAmount, currency: currency, maximumFractionDigits: 0))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    if block.paymentCount > 0 {
                                        let monthlyAmount = block.totalAmount / Double(block.paymentCount)
                                        Label(
                                            "\(CurrencyFormatter.format(amount: monthlyAmount, currency: currency, maximumFractionDigits: 0))/mo",
                                            systemImage: "calendar"
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(block.paymentCount) payments")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var errorSection: some View {
        Group {
            if let error = viewModel.budgetPreviewError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AccessibleColors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var feasibilityColor: Color {
        switch viewModel.budgetFeasibility.statusLevel {
        case .achievable: return AccessibleColors.success
        case .atRisk: return AccessibleColors.warning
        case .critical: return AccessibleColors.error
        }
    }

    private func timelineColor(for index: Int) -> Color {
        let palette = AccessibleColors.chartColors
        return palette[index % palette.count].opacity(0.6)
    }

    private func refreshPreview(force: Bool = false) async {
        guard let amount = parsedBudget else {
            // Reset submission fingerprint so returning to the same canonical value
            // after invalid input still triggers a fresh preview.
            lastSubmittedMinorValue = nil
            lastSubmittedCurrency = currency.uppercased()
            if let failure = parseResult.failure {
                BudgetPlanAnalytics.log(.parseFailure)
                BudgetPlanAnalytics.log(.parseFailureType, properties: ["type": failure.rawValue])
                DIContainer.shared.navigationTelemetryTracker.recoveryCompleted(
                    journeyID: NavigationJourney.planningFlowCancelRecovery,
                    recoveryPath: "budget_parse_failure_\\(failure.rawValue)",
                    success: false
                )
                viewModel.budgetSaveDisabledReason = failure.message
            }
            viewModel.budgetPreviewPlan = nil
            viewModel.budgetPreviewTimeline = []
            viewModel.budgetPreviewError = nil
            viewModel.budgetComputationResult = nil
            viewModel.isBudgetPreviewLoading = false
            return
        }

        let minorValue = amount.minorUnitValue
        if !force,
           minorValue == lastSubmittedMinorValue,
           lastSubmittedCurrency == currency.uppercased() {
            return
        }

        lastSubmittedMinorValue = minorValue
        lastSubmittedCurrency = currency.uppercased()
        await viewModel.previewBudget(amount: amount, currency: currency)
    }

    private func applyBudget() {
        guard let amount = parsedBudget, let plan = viewModel.budgetPreviewPlan else { return }
        isApplying = true
        Task {
            let applied = await viewModel.applyBudgetPlan(plan: plan, amount: amount.doubleValue, currency: currency)
            isApplying = false
            if applied {
                let tracker = DIContainer.shared.navigationTelemetryTracker
                tracker.flowCompleted(
                    journeyID: NavigationJourney.monthlyBudgetAdjust,
                    result: "saved"
                )
                tracker.flowCompleted(
                    journeyID: NavigationJourney.planningFlowCancelRecovery,
                    result: "saved"
                )
                tracker.recoveryCompleted(
                    journeyID: NavigationJourney.planningFlowCancelRecovery,
                    recoveryPath: "budget_apply",
                    success: true
                )
                dismiss()
            }
        }
    }

    private func applySuggestion(_ suggestion: FeasibilitySuggestion) {
        switch suggestion {
        case .increaseBudget(let to, _):
            let canonical = MoneyQuantizer.normalize(Decimal(to), currency: currency, mode: .halfUp)
            budgetText = canonicalDecimalText(for: canonical)
        case .editGoal(let goalId, _):
            editingGoal = viewModel.goals.first { $0.id == goalId }
        default:
            let amount = parsedBudget?.doubleValue ?? 0
            isApplyingSuggestion = true
            Task {
                _ = await viewModel.applyFeasibilitySuggestion(
                    suggestion,
                    currentBudget: amount,
                    currency: currency
                )
                isApplyingSuggestion = false
                await refreshPreview(force: true)
            }
        }
    }

    private func canonicalDecimalText(for amount: MoneyAmount) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.minimumFractionDigits = amount.minorUnits
        formatter.maximumFractionDigits = amount.minorUnits
        return formatter.string(from: NSDecimalNumber(decimal: amount.value))
            ?? NSDecimalNumber(decimal: amount.value).stringValue
    }

    private func normalizeDisplayTextIfPossible() {
        guard let amount = parsedBudget else { return }
        budgetText = canonicalDecimalText(for: amount)
    }

    private var isDirty: Bool {
        fingerprint(amount: parsedBudget, currency: currency) != initialBudgetFingerprint
    }

    private func fingerprint(amount: MoneyAmount?, currency: String) -> String {
        let minorValue = amount?.minorUnitValue ?? Int64.min
        return "\(currency.uppercased()):\(minorValue)"
    }

    private func trackCancel(stage: String) {
        let tracker = DIContainer.shared.navigationTelemetryTracker
        tracker.cancelled(
            journeyID: NavigationJourney.monthlyBudgetAdjust,
            isDirty: isDirty,
            cancelStage: stage
        )
        tracker.cancelled(
            journeyID: NavigationJourney.planningFlowCancelRecovery,
            isDirty: isDirty,
            cancelStage: stage
        )
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
        // NAV-MOD: MOD-01
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
                            .foregroundStyle(AccessibleColors.success)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Label(block.dateRange, systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Label("\(block.paymentCount) monthly payments", systemImage: "repeat")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

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
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }

    private func color(for index: Int) -> Color {
        let palette = AccessibleColors.chartColors
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
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if block.isComplete {
                    Label("Completes", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AccessibleColors.success)
                }
            }

            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.format(amount: block.totalAmount, currency: currency, maximumFractionDigits: 2))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Spacer()

                VStack(alignment: .leading) {
                    Text("Payments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(block.paymentCount)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Spacer()

                if block.paymentCount > 0 {
                    VStack(alignment: .leading) {
                        Text("Per Month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                    if contribution.isGoalComplete {
                        Text("Complete")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AccessibleColors.successBackground)
                            .foregroundStyle(AccessibleColors.success)
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
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
