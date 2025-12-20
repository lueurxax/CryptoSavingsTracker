//
//  ReminderConfigurationView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI

struct ReminderConfigurationView: View {
    @Binding var isEnabled: Bool
    @Binding var frequency: ReminderFrequency
    @Binding var reminderTime: Date?
    @Binding var firstReminderDate: Date?
    let startDate: Date
    let deadline: Date
    let showAdvancedOptions: Bool

    @State private var showingAdvanced = false

    /// Safe date range that handles cases where startDate > deadline
    private var safeDateRange: ClosedRange<Date> {
        if startDate <= deadline {
            return startDate...deadline
        } else {
            // Fallback: use deadline as both bounds if dates are inverted
            return deadline...deadline
        }
    }
    
    private var defaultReminderTime: Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }
    
    private var nextReminderPreview: String? {
        guard isEnabled, let time = reminderTime else { return nil }
        
        // Use first reminder date if set, otherwise use start date
        let baseDate = firstReminderDate ?? startDate
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        let hour = timeComponents.hour ?? 9
        let minute = timeComponents.minute ?? 0
        
        if let nextDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: nextDate)
        }
        
        return "No upcoming reminders"
    }
    
    private func calculateTotalReminders() -> Int {
        guard isEnabled, let _ = reminderTime else { return 0 }
        
        let calendar = Calendar.current
        var count = 0
        var currentDate = firstReminderDate ?? startDate
        
        while currentDate <= deadline {
            count += 1
            guard let nextDate = calendar.date(byAdding: frequency.dateComponents, to: currentDate) else { break }
            currentDate = nextDate
        }
        
        return count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Enable/Disable Toggle
            Toggle("Enable Reminders", isOn: $isEnabled)
                .toggleStyle(SwitchToggleStyle())
                .accessibilityHint("Turn on to receive periodic reminders about your savings goal")
                .onChange(of: isEnabled) { _, newValue in
                    if newValue && reminderTime == nil {
                        reminderTime = defaultReminderTime
                    } else if !newValue {
                        reminderTime = nil
                    }
                }
            
            if isEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    // Frequency Selection
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reminder Frequency")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Picker("Frequency", selection: $frequency) {
                            ForEach(ReminderFrequency.allCases) { freq in
                                Text(freq.displayName).tag(freq)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("How often you want to receive reminders")
                    }
                    
                    // Time Selection
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reminder Time")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        DatePicker(
                            "Time",
                            selection: Binding(
                                get: { reminderTime ?? defaultReminderTime },
                                set: { newTime in
                                    reminderTime = newTime
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.compact)
                        .accessibilityLabel("What time of day to send reminders")
                    }
                    
                    // First Reminder Date Selection
                    VStack(alignment: .leading, spacing: 4) {
                        Text("First Reminder Date")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        DatePicker(
                            "First Reminder Date",
                            selection: Binding(
                                get: { firstReminderDate ?? startDate },
                                set: { newDate in
                                    firstReminderDate = newDate
                                }
                            ),
                            in: safeDateRange,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .accessibilityLabel("Choose the date for your first reminder")
                        
                        HStack {
                            Text("Subsequent reminders will follow the selected frequency")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            
                            if firstReminderDate != nil && firstReminderDate != startDate {
                                Button("Reset to Start Date") {
                                    firstReminderDate = nil
                                }
                                .font(.caption2)
                                .foregroundColor(.accessiblePrimary)
                            }
                        }
                    }
                    
                    
                    // Schedule Preview
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(.accessiblePrimary)
                                .font(.subheadline)
                            Text("Schedule Preview")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Pattern:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(frequency.displayName) reminders")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            
                            if let preview = nextReminderPreview {
                                HStack {
                                    Text("Next:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(preview)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.accessiblePrimary)
                                    Spacer()
                                }
                            }
                            
                            let totalReminders = calculateTotalReminders()
                            if totalReminders > 0 {
                                HStack {
                                    Text("Total:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(totalReminders) reminder\(totalReminders == 1 ? "" : "s")")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Spacer()
                                }
                            }
                        }
                        .padding(8)
                        .background(AccessibleColors.primaryInteractive.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .onChange(of: frequency) { _, _ in
            // Update preview when frequency changes
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reminder configuration")
    }
}

#Preview("Basic Configuration") {
    @Previewable @State var isEnabled = true
    @Previewable @State var frequency = ReminderFrequency.weekly
    @Previewable @State var reminderTime: Date? = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
    @Previewable @State var firstReminderDate: Date? = nil
    
    VStack {
        ReminderConfigurationView(
            isEnabled: $isEnabled,
            frequency: $frequency,
            reminderTime: $reminderTime,
            firstReminderDate: $firstReminderDate,
            startDate: Date(),
            deadline: Date().addingTimeInterval(86400 * 30),
            showAdvancedOptions: true
        )
        .padding()
        
        Divider()
        
        Text("Reminders: \(isEnabled ? "Enabled" : "Disabled") - \(frequency.displayName)")
            .font(.caption)
            .padding()
    }
}