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
    @StateObject private var currencyViewModel = CurrencyViewModel()
    
    @State private var name = ""
    @State private var currency = ""
    @State private var targetAmount = ""
    @State private var deadline = Date().addingTimeInterval(86400 * 30)
    @State private var startDate = Date()
    @State private var frequency: ReminderFrequency = .weekly
    @State private var isReminderEnabled = true
    @State private var reminderTime: Date? = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
    @State private var firstReminderDate: Date?
    @State private var showingCurrencyPicker = false
    
    // Template and validation state
    @State private var selectedTemplate: GoalTemplate?
    @State private var showingTemplates = false
    @State private var hasAttemptedSubmit = false
    @State private var showValidationWarnings = false

    private var isUITestFlow: Bool {
        UITestFlags.isEnabled
    }
    
    // Computed validation properties
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !currency.isEmpty &&
        (Double(targetAmount) ?? 0) > 0 &&
        deadline > Date()
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
        
        return issues
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
                                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
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
                                .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
                        }
                        
                        // Validation warnings (only show after interaction)
                        if (hasAttemptedSubmit || showValidationWarnings) && !validationIssues.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(validationIssues, id: \.self) { issue in
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                            .font(.caption)
                                        Text(issue)
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
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
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reminders")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ReminderConfigurationView(
                                isEnabled: $isReminderEnabled,
                                frequency: $frequency,
                                reminderTime: $reminderTime,
                                firstReminderDate: $firstReminderDate,
                                startDate: startDate,
                                deadline: deadline,
                                showAdvancedOptions: false
                            )
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
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    Button("Save") {
                        saveGoal()
                    }
                    .disabled(!isValidInput)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("saveGoalButtonMac")
                }
                .padding()
            }
            .frame(minWidth: 450, minHeight: 350)
#else
            NavigationView {
                Form {
                    Section(header: Text("Goal Details")) {
                        TextField("Goal Name", text: $name)
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("goalNameField")
                        
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
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("targetAmountField")
                        
                        DatePicker("Deadline", selection: $deadline, in: Date()..., displayedComponents: .date)
                            .padding(.vertical, 4)
                        
                        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                            .padding(.vertical, 4)
                    }
                    
                    Section(header: Text("Reminders")) {
                        ReminderConfigurationView(
                            isEnabled: $isReminderEnabled,
                            frequency: $frequency,
                            reminderTime: $reminderTime,
                            firstReminderDate: $firstReminderDate,
                            startDate: startDate,
                            deadline: deadline,
                            showAdvancedOptions: false
                        )
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.top, 8)
                .navigationTitle("New Goal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            saveGoal()
                        }
                        .disabled(!isValidInput)
                        .accessibilityIdentifier("saveGoalButton")
                    }
                }
            }
#endif
        }
        .task {
            if currencyViewModel.coinInfos.isEmpty {
                await currencyViewModel.fetchCoins()
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { isUITestFlow && showingCurrencyPicker },
            set: { newValue in
                if isUITestFlow {
                    showingCurrencyPicker = newValue
                }
            }
        )) {
            SearchableCurrencyPicker(selectedCurrency: $currency, pickerType: .fiat)
        }
        .sheet(isPresented: Binding(
            get: { !isUITestFlow && showingCurrencyPicker },
            set: { newValue in
                if !isUITestFlow {
                    showingCurrencyPicker = newValue
                }
            }
        )) {
            SearchableCurrencyPicker(selectedCurrency: $currency, pickerType: .fiat)
        }
        .sheet(isPresented: $showingTemplates) {
            GoalTemplateSelectionView(selectedTemplate: $selectedTemplate) { template in
                // Apply template to form
                name = template.name
                currency = template.currency
                targetAmount = String(format: "%.0f", template.defaultAmount)
                deadline = Date().addingTimeInterval(TimeInterval(template.defaultTimeframe * 86400))
                
                // Keep the current reminder configuration when applying template
                // User can modify it separately if needed
                
                selectedTemplate = template
                showingTemplates = false
            }
        }
    }
    
    private var isValidInput: Bool {
        isFormValid
    }
    
    private func saveGoal() {
        hasAttemptedSubmit = true
        
        guard isFormValid, let amount = Double(targetAmount) else { 
            showValidationWarnings = true
            return 
        }
        
        let newGoal = Goal(name: name, currency: currency.uppercased(), targetAmount: amount, deadline: deadline, startDate: startDate, frequency: frequency)
        
        // Set reminder properties
        if isReminderEnabled {
            newGoal.reminderFrequency = frequency.rawValue
            newGoal.reminderTime = reminderTime
            newGoal.firstReminderDate = firstReminderDate
        } else {
            newGoal.reminderFrequency = nil
            newGoal.reminderTime = nil
            newGoal.firstReminderDate = nil
        }
        
        modelContext.insert(newGoal)
        
        do {
            try modelContext.save()
        } catch {
            // TODO: Show user-friendly error message like "Unable to save your goal. Please try again."
            print("❌ Goal saving failed: \(error)")
        }
        
        Task {
            await NotificationManager.shared.scheduleReminders(for: newGoal)
        }
        dismiss()
    }
}

// MARK: - Goal Template Selection View
struct GoalTemplateSelectionView: View {
    @Binding var selectedTemplate: GoalTemplate?
    let onTemplateSelected: (GoalTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
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
                                .foregroundColor(.green)
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
                                .foregroundColor(.green)
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

#Preview {
    AddGoalView()
        .modelContainer(for: [Goal.self, Asset.self, Transaction.self], inMemory: true)
}
