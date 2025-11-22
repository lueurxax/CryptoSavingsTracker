//
//  MonthlyPlanningSettingsView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 10/08/2025.
//

import SwiftUI
import SwiftData

// Simplified Goal definition for settings preview
struct SimpleGoal {
    let id = UUID()
    let name: String
    let currency: String
    let targetAmount: Double
    let deadline: Date
}

/// Settings interface for monthly planning preferences
struct MonthlyPlanningSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject private var settings = MonthlyPlanningSettings.shared
    @State private var showingCurrencyPicker = false
    @State private var showingPaymentDayPicker = false
    @State private var showAdvancedOptions = false
    @State private var previewTotal: Double = 0
    @State private var isLoadingPreview = false
    
    // For preview calculations - simplified to avoid dependencies
    let goals: [SimpleGoal]
    
    // Convenience initializer for actual Goal objects
    init(goals: [Any]) {
        // Convert any Goal-like objects to SimpleGoal for preview
        self.goals = goals.compactMap { goal in
            // Use reflection to extract properties safely
            let mirror = Mirror(reflecting: goal)
            var name = "Unknown"
            var currency = "USD"
            var targetAmount = 0.0
            var deadline = Date()
            
            for child in mirror.children {
                switch child.label {
                case "name": name = child.value as? String ?? "Unknown"
                case "currency": currency = child.value as? String ?? "USD"
                case "targetAmount": targetAmount = child.value as? Double ?? 0.0
                case "deadline": deadline = child.value as? Date ?? Date()
                default: break
                }
            }
            
            return SimpleGoal(name: name, currency: currency, targetAmount: targetAmount, deadline: deadline)
        }
    }
    
    var body: some View {
        NavigationView {
            settingsContent
                .navigationTitle("Monthly Planning Settings")
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
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                    #else
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                    #endif
                }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 600, maxWidth: 700, minHeight: 500, idealHeight: 600, maxHeight: 700)
        #else
        .presentationDetents([.large])
        #endif
        .task {
            await loadPreviewTotal()
        }
        .onChange(of: settings.displayCurrency) { _, _ in
            Task {
                await loadPreviewTotal()
            }
        }
    }
    
    @ViewBuilder
    private var settingsContent: some View {
        Form {
            // Display Preferences Section
            Section {
                displayCurrencyRow
                previewRow
            } header: {
                Text("Display Preferences")
            } footer: {
                Text("Choose which currency to show your total monthly requirements in.")
            }
            
            // Payment Cycle Section
            Section {
                paymentDayRow
                nextPaymentRow
            } header: {
                Text("Payment Cycle")
            } footer: {
                Text("Set when your monthly payments are due. We'll calculate requirements based on this schedule.")
            }
            
            // Notification Section
            Section {
                notificationToggle
                
                if settings.notificationsEnabled {
                    notificationDaysRow
                }
            } header: {
                Text("Reminders")
            } footer: {
                if settings.notificationsEnabled {
                    Text("You'll receive reminders \(settings.notificationDays) day\(settings.notificationDays == 1 ? "" : "s") before your payment deadline.")
                } else {
                    Text("Enable to receive payment deadline reminders.")
                }
            }
            
            // Automation Section
            Section {
                autoStartToggle
                autoCompleteToggle
                gracePeriodPicker
            } header: {
                Text("Automation")
            } footer: {
                Text("Automatically start tracking on the 1st of each month and mark complete on the last day. All automated actions include an undo grace period.")
            }

            // Advanced Options
            DisclosureGroup("Advanced Options", isExpanded: $showAdvancedOptions) {
                advancedOptionsContent
            }

            // Reset Section
            Section {
                resetButton
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Display Preferences
    
    private var displayCurrencyRow: some View {
        HStack {
            Label("Display Currency", systemImage: "dollarsign.circle")
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                showingCurrencyPicker = true
            }) {
                HStack(spacing: 4) {
                    Text(settings.displayCurrency)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Display currency for monthly planning")
        .accessibilityHint("Double tap to select currency for showing total requirements")
        .accessibilityValue("Currently \(settings.displayCurrency)")
        .sheet(isPresented: $showingCurrencyPicker) {
            // For monthly planning, we want fiat currency options like in goal settings
            SearchableCurrencyPicker(selectedCurrency: $settings.displayCurrency, pickerType: .fiat)
                #if os(macOS)
                .frame(minWidth: 600, idealWidth: 700, maxWidth: 800, minHeight: 500, maxHeight: 700)
                #endif
        }
    }
    
    private var previewRow: some View {
        HStack {
            Label("Total Preview", systemImage: "eye")
                .foregroundColor(.secondary)
            
            Spacer()
            
            if isLoadingPreview {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Text(CurrencyFormatter.format(amount: previewTotal, currency: settings.displayCurrency))
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
        }
        .accessibilityLabel("Total monthly requirements preview")
        .accessibilityValue(isLoadingPreview ? "Loading" : CurrencyFormatter.format(amount: previewTotal, currency: settings.displayCurrency))
    }
    
    // MARK: - Payment Cycle
    
    private var paymentDayRow: some View {
        HStack {
            Label("Payment Day", systemImage: "calendar")
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                showingPaymentDayPicker = true
            }) {
                HStack(spacing: 4) {
                    Text("\(settings.paymentDay)\(settings.paymentDay.ordinalSuffix) of month")
                        .fontWeight(.medium)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Payment cycle deadline")
        .accessibilityHint("Select which day of the month payments are due")
        .accessibilityValue("Currently \(settings.paymentDay)\(settings.paymentDay.ordinalSuffix) of every month")
        .sheet(isPresented: $showingPaymentDayPicker) {
            PaymentDayPickerSheet(selectedDay: $settings.paymentDay)
        }
    }
    
    private var nextPaymentRow: some View {
        HStack {
            Label("Next Payment", systemImage: "clock")
                .foregroundColor(.secondary)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(settings.nextPaymentFormatted)
                    .fontWeight(.medium)
                
                Text("\(settings.daysUntilPayment) days remaining")
                    .font(.caption)
                    .foregroundColor(
                        settings.daysUntilPayment <= 3 ? .red :
                        settings.daysUntilPayment <= 7 ? .orange :
                            .secondary
                    )
            }
        }
        .accessibilityLabel("Next payment deadline")
        .accessibilityValue("\(settings.nextPaymentFormatted), \(settings.daysUntilPayment) days remaining")
    }
    
    // MARK: - Notifications

    private var notificationToggle: some View {
        Toggle(isOn: $settings.notificationsEnabled) {
            Label("Payment Reminders", systemImage: "bell")
                .foregroundColor(.primary)
        }
        .tint(.blue)
        .accessibilityLabel("Enable payment reminder notifications")
        .accessibilityHint("Toggle to enable or disable payment deadline notifications")
    }

    // MARK: - Automation

    private var autoStartToggle: some View {
        Toggle(isOn: $settings.autoStartEnabled) {
            Label("Auto-start new month", systemImage: "play.circle")
                .foregroundColor(.primary)
        }
        .tint(.blue)
        .accessibilityLabel("Automatically start tracking on the 1st of each month")
        .accessibilityHint("When enabled, monthly tracking will start automatically with an undo grace period")
    }

    private var autoCompleteToggle: some View {
        Toggle(isOn: $settings.autoCompleteEnabled) {
            Label("Auto-complete previous month", systemImage: "checkmark.circle")
                .foregroundColor(.primary)
        }
        .tint(.blue)
        .accessibilityLabel("Automatically complete tracking on the last day of month")
        .accessibilityHint("When enabled, monthly tracking will be marked complete automatically with an undo grace period")
    }

    private var gracePeriodPicker: some View {
        HStack {
            Label("Undo grace period", systemImage: "arrow.uturn.backward.circle")
                .foregroundColor(.primary)

            Spacer()

            Picker("Grace Period", selection: $settings.undoGracePeriodHours) {
                Text("24 hours").tag(24)
                Text("48 hours").tag(48)
                Text("7 days").tag(168)
                Text("No undo").tag(0)
            }
            .pickerStyle(.menu)
            .tint(.blue)
        }
        .accessibilityLabel("Undo grace period for automated actions")
        .accessibilityHint("Select how long you have to undo automated state transitions")
        .accessibilityValue(gracePeriodDescription)
    }

    private var gracePeriodDescription: String {
        switch settings.undoGracePeriodHours {
        case 24: return "24 hours"
        case 48: return "48 hours"
        case 168: return "7 days"
        case 0: return "No undo - actions are final"
        default: return "\(settings.undoGracePeriodHours) hours"
        }
    }
    
    private var notificationDaysRow: some View {
        HStack {
            Label("Reminder Days", systemImage: "bell.badge")
                .foregroundColor(.primary)
            
            Spacer()
            
            Picker("Notification Days", selection: $settings.notificationDays) {
                ForEach(1...7, id: \.self) { days in
                    Text("\(days) day\(days == 1 ? "" : "s") before")
                        .tag(days)
                }
            }
            .pickerStyle(.menu)
            .tint(.blue)
        }
        .accessibilityLabel("Reminder notification timing")
        .accessibilityHint("Select how many days before payment deadline to receive notifications")
        .accessibilityValue("\(settings.notificationDays) day\(settings.notificationDays == 1 ? "" : "s") before")
    }
    
    // MARK: - Advanced Options
    
    @ViewBuilder
    private var advancedOptionsContent: some View {
        HStack {
            Label("Validation", systemImage: "checkmark.shield")
                .foregroundColor(.secondary)
            
            Spacer()
            
            if settings.validatePaymentDay() {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                    Text("Valid")
                        .foregroundColor(.green)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Check settings")
                        .foregroundColor(.orange)
                }
            }
        }
        .font(.subheadline)
    }
    
    // MARK: - Reset
    
    private var resetButton: some View {
        Button(role: .destructive) {
            withAnimation {
                settings.resetToDefaults()
                Task {
                    await loadPreviewTotal()
                }
            }
        } label: {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                Text("Reset to Defaults")
            }
        }
        .accessibilityLabel("Reset monthly planning settings to defaults")
        .accessibilityHint("Double tap to restore all settings to their original values")
    }
    
    // MARK: - Helper Methods
    
    private func loadPreviewTotal() async {
        isLoadingPreview = true
        
        // Simple calculation for preview (sum all goals)
        let total = goals.reduce(0) { $0 + $1.targetAmount }
        
        await MainActor.run {
            self.previewTotal = total
            self.isLoadingPreview = false
        }
    }
}

// MARK: - Supporting Views

struct PaymentDayPickerSheet: View {
    @Binding var selectedDay: Int
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(1...28, id: \.self) { day in
                    HStack {
                        Text("\(day)\(day.ordinalSuffix) of every month")
                            .fontWeight(selectedDay == day ? .semibold : .regular)
                        
                        Spacer()
                        
                        if selectedDay == day {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedDay = day
                        dismiss()
                    }
                }
            }
            .navigationTitle("Payment Day")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 500, maxWidth: 600, minHeight: 500, idealHeight: 600, maxHeight: 700)
        #endif
    }
}

// MARK: - Extensions

private extension Int {
    var ordinalSuffix: String {
        switch self % 100 {
        case 11...13:
            return "th"
        default:
            switch self % 10 {
            case 1: return "st"
            case 2: return "nd"
            case 3: return "rd"
            default: return "th"
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let goal1 = SimpleGoal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
    let goal2 = SimpleGoal(name: "Ethereum Fund", currency: "EUR", targetAmount: 25000, deadline: Date().addingTimeInterval(86400 * 60))
    
    MonthlyPlanningSettingsView(goals: [goal1, goal2])
}