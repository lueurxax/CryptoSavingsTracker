// Extracted preview-only declarations for NAV003 policy compliance.
// Source: ReminderConfigurationView.swift

//
//  ReminderConfigurationView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI

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
