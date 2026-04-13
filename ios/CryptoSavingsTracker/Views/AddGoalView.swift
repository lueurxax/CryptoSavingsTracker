    //
    //  AddGoalView.swift
    //  CryptoSavingsTracker
    //
    //  Created by user on 26/07/2025.
    //

import SwiftUI
import SwiftData


struct AddGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var currencyViewModel: CurrencyViewModel

    private enum Field: Hashable {
        case name
        case targetAmount
    }

    struct PreviewState {
        var name: String = ""
        var currency: String = ""
        var targetAmount: String = ""
        var deadline: Date = Date().addingTimeInterval(86400 * 30)
        var startDate: Date = Date()
        var selectedTemplate: GoalTemplate? = nil
        var hasAttemptedSubmit: Bool = false
        var showValidationWarnings: Bool = false
        var saveErrorMessage: String? = nil
    }
    
    @State private var name = ""
    @State private var currency = ""
    @State private var targetAmount = ""
    @State private var deadline = Date().addingTimeInterval(86400 * 30)
    @State private var startDate = Date()
    @State private var showingCurrencyPicker = false
    
    // Template and validation state
    @State private var selectedTemplate: GoalTemplate?
    @State private var showingTemplates = false
    @State private var hasAttemptedSubmit = false
    @State private var showValidationWarnings = false
    @State private var hasStartedTelemetryFlow = false
    @State private var showingDiscardConfirmation = false
    @State private var saveErrorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    init(previewState: PreviewState = PreviewState()) {
        _currencyViewModel = StateObject(wrappedValue: CurrencyViewModel())
        _name = State(initialValue: previewState.name)
        _currency = State(initialValue: previewState.currency)
        _targetAmount = State(initialValue: previewState.targetAmount)
        _deadline = State(initialValue: previewState.deadline)
        _startDate = State(initialValue: previewState.startDate)
        _selectedTemplate = State(initialValue: previewState.selectedTemplate)
        _hasAttemptedSubmit = State(initialValue: previewState.hasAttemptedSubmit)
        _showValidationWarnings = State(initialValue: previewState.showValidationWarnings)
        _saveErrorMessage = State(initialValue: previewState.saveErrorMessage)
    }

    private var isUITestFlow: Bool {
        UITestFlags.isEnabled
    }

    private var shouldShowValidationFeedback: Bool {
        hasAttemptedSubmit || showValidationWarnings
    }

    private var isDirty: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !currency.isEmpty ||
        !(targetAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var focusedFieldIdentifier: String? {
        switch focusedField {
        case .name:
            return "name"
        case .targetAmount:
            return "targetAmount"
        case nil:
            return nil
        }
    }
    
    // Computed validation properties
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !currency.isEmpty &&
        (Double(targetAmount) ?? 0) > 0 &&
        deadline > Date() &&
        startDate <= deadline
    }
    
    private var validationIssues: [String] {
        var issues: [String] = []
        
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Goal name is required")
        }
        
        if currency.isEmpty {
            issues.append("Currency selection is required")
        }
        
        let amount = Double(targetAmount) ?? 0
        if amount <= 0 {
            issues.append("Target amount must be greater than 0")
        }
        
        if deadline <= Date() {
            issues.append("Deadline must be in the future")
        }

        if startDate > deadline {
            issues.append("Start date must be before deadline")
        }

        return issues
    }

    private var nameValidationMessage: String? {
        guard shouldShowValidationFeedback,
              name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return "Goal name is required"
    }

    private var currencyValidationMessage: String? {
        guard shouldShowValidationFeedback, currency.isEmpty else { return nil }
        return "Currency selection is required"
    }

    private var amountValidationMessage: String? {
        guard shouldShowValidationFeedback else { return nil }
        let amount = Double(targetAmount) ?? 0
        guard amount <= 0 else { return nil }
        return "Target amount must be greater than 0"
    }

    private var deadlineValidationMessage: String? {
        guard shouldShowValidationFeedback, deadline <= Date() else { return nil }
        return "Deadline must be in the future"
    }

    private var startDateValidationMessage: String? {
        guard shouldShowValidationFeedback, startDate > deadline else { return nil }
        return "Start date must be before deadline"
    }
    
    private var goalGuidance: String? {
        let amount = Double(targetAmount) ?? 0
        let daysUntilDeadline = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
        
        if amount > 0 && daysUntilDeadline > 0 {
            let dailyAmount = amount / Double(daysUntilDeadline)
            
            if dailyAmount > 100 {
                return "⚠️ This requires saving \(String(format: "%.2f", dailyAmount)) \(currency) per day. Consider extending the deadline or reducing the target."
            } else if dailyAmount > 50 {
                return "💪 This is ambitious! You'll need to save \(String(format: "%.2f", dailyAmount)) \(currency) per day."
            } else if dailyAmount > 10 {
                return "✅ Good goal! Save about \(String(format: "%.2f", dailyAmount)) \(currency) per day."
            } else {
                return "🎯 Very achievable! Just \(String(format: "%.2f", dailyAmount)) \(currency) per day."
            }
        }
        
        return nil
    }
    
    var body: some View {
        Group {
#if os(macOS)
            VStack(spacing: 0) {
                Text("New Goal")
                    .font(.title2)
                    .padding()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Template selection section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Start with a template")
                                    .font(.headline)
                                Spacer()
                                Button("Browse Templates") {
                                    showingTemplates = true
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accessiblePrimary)
                            }
                            
                            if let template = selectedTemplate {
                                HStack {
                                    Image(systemName: template.icon)
                                        .foregroundColor(.accessiblePrimary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(template.description)
                                            .font(.caption)
                                            .foregroundColor(.accessibleSecondary)
                                    }
                                    Spacer()
                                    Button("Clear") {
                                        selectedTemplate = nil
                                        name = ""
                                        currency = ""
                                        targetAmount = ""
                                    }
                                    .font(.caption)
                                    .foregroundColor(.accessibleSecondary)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .padding(12)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                Text("Choose a template to get started quickly, or create your own goal below.")
                                    .font(.caption)
                                    .foregroundColor(.accessibleSecondary)
                            }
                        }
                        
                        Divider()
                        
                        // Form fields
                        VStack(alignment: .leading, spacing: 12) {
                        TextField("Goal Name", text: $name)
                            .accessibilityIdentifier("goalNameField")
                            .padding(.vertical, 4)
                        
                        HStack {
                            Text("Currency:")
                            Spacer()
                            Button {
                                showingCurrencyPicker = true
                            } label: {
                                HStack {
                                    Text(currency.isEmpty ? "Select Currency" : currency)
                                        .foregroundColor(currency.isEmpty ? .secondary : .primary)
                                        .accessibilityIdentifier("currencyValueLabel")
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("currencyButton")
                            .accessibilityValue(currency.isEmpty ? "unset" : currency.uppercased())
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showingCurrencyPicker = true
                        }

                        #if os(iOS)
                        if isUITestFlow {
                            TextField("Currency (Test)", text: $currency)
                                .textInputAutocapitalization(.characters)
                                .disableAutocorrection(true)
                                .accessibilityIdentifier("goalCurrencyOverrideField")
                                .padding(.vertical, 4)
                        }
                        #endif

                        TextField("Target Amount", text: $targetAmount)
                            .accessibilityIdentifier("targetAmountField")
                            .padding(.vertical, 4)
                        
                        // Goal guidance and validation
                        if let guidance = goalGuidance {
                            Text(guidance)
                                .font(.caption)
                                .padding(12)
                                .background(Color.accessiblePrimaryBackground)
                                .foregroundColor(.accessiblePrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        // Validation warnings (only show after interaction)
                        if (hasAttemptedSubmit || showValidationWarnings) && !validationIssues.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(validationIssues, id: \.self) { issue in
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(AccessibleColors.error)
                                            .font(.caption)
                                        Text(issue)
                                            .font(.caption)
                                            .foregroundColor(AccessibleColors.error)
                                    }
                                }
                            }
                            .padding(12)
                            .background(AccessibleColors.errorBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Deadline")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            DatePicker("", selection: $deadline, in: Date()..., displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .labelsHidden()
                        }
                        .padding(.vertical, 4)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Start Date")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            DatePicker("", selection: $startDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                        }
                        .padding(.vertical, 4)
                        
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.top, 8)
                
                Divider()
                
                HStack {
                    Button("Cancel") {
                        requestCancel(stage: "mac_toolbar_cancel")
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    Button("Save") {
                        Task {
                            await saveGoal()
                        }
                    }
                    .disabled(!isValidInput)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("saveGoalButtonMac")
                }
                .padding()
            }
            .frame(minWidth: 450, minHeight: 350)
#else
            NavigationStack {
                Form {
                    Section(header: Text("Goal Details")) {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Goal Name", text: $name)
                                .padding(.vertical, 4)
                                .accessibilityIdentifier("goalNameField")
                                .focused($focusedField, equals: .name)

                            if let nameValidationMessage {
                                GoalFormInlineError(message: nameValidationMessage)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Currency:")
                                Spacer()
                                Button {
                                    showingCurrencyPicker = true
                                } label: {
                                    HStack {
                                        Text(currency.isEmpty ? "Select Currency" : currency)
                                            .foregroundColor(currency.isEmpty ? .secondary : .primary)
                                            .accessibilityIdentifier("currencyValueLabel")
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("currencyButton")
                                .accessibilityValue(currency.isEmpty ? "unset" : currency.uppercased())
                            }
                            .padding(.vertical, 4)

                            if let currencyValidationMessage {
                                GoalFormInlineError(message: currencyValidationMessage)
                            }
                        }

                        #if os(iOS)
                        if isUITestFlow {
                            TextField("Currency (Test)", text: $currency)
                                .textInputAutocapitalization(.characters)
                                .disableAutocorrection(true)
                                .accessibilityIdentifier("goalCurrencyOverrideField")
                                .padding(.vertical, 4)
                        }
                        #endif

                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Target Amount", text: $targetAmount)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .padding(.vertical, 4)
                                .accessibilityIdentifier("targetAmountField")
                                .focused($focusedField, equals: .targetAmount)

                            if let amountValidationMessage {
                                GoalFormInlineError(message: amountValidationMessage)
                            }
                        }

                        if let guidance = goalGuidance {
                            Text(guidance)
                                .font(.caption)
                                .padding(12)
                                .background(Color.accessiblePrimaryBackground)
                                .foregroundColor(.accessiblePrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            DatePicker("Deadline", selection: $deadline, in: Date()..., displayedComponents: .date)
                                .padding(.vertical, 4)

                            if let deadlineValidationMessage {
                                GoalFormInlineError(message: deadlineValidationMessage)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                                .padding(.vertical, 4)

                            if let startDateValidationMessage {
                                GoalFormInlineError(message: startDateValidationMessage)
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .navigationTitle("New Goal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            requestCancel(stage: "ios_toolbar_cancel")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    GoalFormBottomActionBar(
                        validationIssues: shouldShowValidationFeedback ? validationIssues : [],
                        saveErrorMessage: saveErrorMessage,
                        isSaving: isSaving,
                        primaryButtonTitle: saveErrorMessage == nil ? "Save Goal" : "Retry Save",
                        primaryButtonIdentifier: "saveGoalButton",
                        focusedFieldIdentifier: focusedFieldIdentifier,
                        onRetry: saveErrorMessage == nil ? nil : { Task { await saveGoal() } },
                        onPrimaryAction: { Task { await saveGoal() } }
                    )
                }
            }
#endif
        }
        .overlay(alignment: .topLeading) {
            GoalFormUITestHooks(focusedFieldIdentifier: focusedFieldIdentifier)
        }
        .task {
            if currencyViewModel.coinInfos.isEmpty {
                await currencyViewModel.fetchCoins()
            }
        }
        .onAppear {
            guard !hasStartedTelemetryFlow else { return }
            hasStartedTelemetryFlow = true
            DIContainer.shared.navigationTelemetryTracker.flowStarted(
                journeyID: NavigationJourney.goalCreateEdit,
                entryPoint: "add_goal_sheet"
            )
        }
        .onChange(of: name) { _, _ in clearTransientFeedback() }
        .onChange(of: currency) { _, _ in clearTransientFeedback() }
        .onChange(of: targetAmount) { _, _ in clearTransientFeedback() }
        .onChange(of: deadline) { _, _ in clearTransientFeedback() }
        .onChange(of: startDate) { _, _ in clearTransientFeedback() }
        // NAV-MOD: MOD-01
        .sheet(isPresented: $showingCurrencyPicker) {
            SearchableCurrencyPicker(selectedCurrency: $currency, pickerType: .fiat)
        }
        // NAV-MOD: MOD-01
        .sheet(isPresented: $showingTemplates) {
            GoalTemplateSelectionView(selectedTemplate: $selectedTemplate) { template in
                // Apply template to form
                name = template.name
                currency = template.currency
                targetAmount = String(format: "%.0f", template.defaultAmount)
                deadline = Date().addingTimeInterval(TimeInterval(template.defaultTimeframe * 86400))
                
                selectedTemplate = template
                showingTemplates = false
            }
        }
        .interactiveDismissDisabled(isDirty)
        // NAV-MOD: MOD-02
        .confirmationDialog(
            "Discard Changes?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                DIContainer.shared.navigationTelemetryTracker.discardConfirmed(
                    journeyID: NavigationJourney.goalCreateEdit,
                    formType: "goal_create"
                )
                dismiss()
            }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("Unsaved goal inputs will be lost.")
        }
    }
    
    private var isValidInput: Bool {
        isFormValid
    }
    
    @MainActor
    private func saveGoal() async {
        hasAttemptedSubmit = true
        showValidationWarnings = true
        saveErrorMessage = nil
        
        guard isFormValid, let amount = Double(targetAmount) else { 
            focusFirstInvalidField()
            DIContainer.shared.navigationTelemetryTracker.recoveryCompleted(
                journeyID: NavigationJourney.goalCreateEdit,
                recoveryPath: "validation_error",
                success: false
            )
            return 
        }

        isSaving = true
        defer { isSaving = false }

        if UITestFlags.consumeSimulatedGoalSaveFailureIfNeeded() {
            saveErrorMessage = "Unable to save this goal right now. Please try again."
            DIContainer.shared.navigationTelemetryTracker.recoveryCompleted(
                journeyID: NavigationJourney.goalCreateEdit,
                recoveryPath: "save_error",
                success: false
            )
            return
        }
        
        let newGoal = Goal(name: name, currency: currency.uppercased(), targetAmount: amount, deadline: deadline, startDate: startDate)
        newGoal.clearRetiredReminderState()
        
        do {
            try await DIContainer.shared.makeGoalMutationService(modelContext: modelContext).createGoal(newGoal)
            DIContainer.shared.navigationTelemetryTracker.flowCompleted(
                journeyID: NavigationJourney.goalCreateEdit,
                result: "saved"
            )
            dismiss()
        } catch {
            saveErrorMessage = "Unable to save this goal right now. Please try again."
            DIContainer.shared.navigationTelemetryTracker.recoveryCompleted(
                journeyID: NavigationJourney.goalCreateEdit,
                recoveryPath: "save_error",
                success: false
            )
            return
        }
    }

    private func clearTransientFeedback() {
        saveErrorMessage = nil
    }

    private func focusFirstInvalidField() {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            focusedField = .name
            return
        }

        if currency.isEmpty {
            showingCurrencyPicker = true
            return
        }

        let amount = Double(targetAmount) ?? 0
        if amount <= 0 {
            focusedField = .targetAmount
        }
    }

    private func trackCancel(stage: String) {
        DIContainer.shared.navigationTelemetryTracker.cancelled(
            journeyID: NavigationJourney.goalCreateEdit,
            isDirty: isDirty,
            cancelStage: stage
        )
    }

    private func requestCancel(stage: String) {
        if isDirty {
            trackCancel(stage: stage)
            showingDiscardConfirmation = true
            return
        }
        trackCancel(stage: stage)
        dismiss()
    }
}

// MARK: - Goal Template Selection View
struct GoalTemplateSelectionView: View {
    @Binding var selectedTemplate: GoalTemplate?
    let onTemplateSelected: (GoalTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(GoalType.allCases, id: \.self) { goalType in
                    let typeTemplates = GoalTemplate.allTemplates.filter { $0.type == goalType }
                    
                    if !typeTemplates.isEmpty {
                        Section(header: 
                            HStack {
                                Image(systemName: iconForGoalType(goalType))
                                    .foregroundColor(.accessiblePrimary)
                                Text(goalType.displayName)
                            }
                        ) {
                            ForEach(typeTemplates) { template in
                                GoalTemplateRow(
                                    template: template,
                                    isSelected: selectedTemplate?.id == template.id
                                ) {
                                    onTemplateSelected(template)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Goal Templates")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
#else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
#endif
            }
        }
        .frame(minWidth: 600, minHeight: 500)
#if os(macOS)
        .frame(idealWidth: 700, idealHeight: 600)
#endif
    }
    
    private func iconForGoalType(_ type: GoalType) -> String {
        switch type {
        case .emergency: return "shield.fill"
        case .retirement: return "house.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .travel: return "airplane"
        case .purchase: return "cart.fill"
        case .education: return "graduationcap.fill"
        }
    }
}

struct GoalTemplateRow: View {
    let template: GoalTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(template.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(template.difficulty.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(template.difficulty.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(template.difficulty.color.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    Text(template.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle")
                                .foregroundColor(AccessibleColors.success)
                                .font(.caption)
                            Text("$\(Int(template.defaultAmount).formatted())")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.circle")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text(template.timeframeDescription)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AccessibleColors.success)
                                .font(.title2)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
