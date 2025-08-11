//
//  MonthlyPlanningSettings.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 10/08/2025.
//

import Foundation
import SwiftUI
import Combine

/// User preferences for monthly planning display and calculations
@MainActor
final class MonthlyPlanningSettings: ObservableObject {
    
    // MARK: - Singleton
    
    /// Shared instance for app-wide settings
    static let shared = MonthlyPlanningSettings()
    
    // MARK: - Published Properties
    
    /// Currency to display total monthly requirements in
    @Published var displayCurrency: String {
        didSet {
            UserDefaults.standard.set(displayCurrency, forKey: Keys.displayCurrency)
        }
    }
    
    /// Day of month when payments are due (1-28 to avoid month-length issues)
    @Published var paymentDay: Int {
        didSet {
            UserDefaults.standard.set(paymentDay, forKey: Keys.paymentDay)
        }
    }
    
    /// Whether to show notifications for upcoming payment deadlines
    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }
    
    /// How many days before payment day to send reminder notifications
    @Published var notificationDays: Int {
        didSet {
            UserDefaults.standard.set(notificationDays, forKey: Keys.notificationDays)
        }
    }
    
    // MARK: - Computed Properties
    
    /// Next payment deadline based on current date and payment day
    var nextPaymentDate: Date {
        let calendar = Calendar.current
        let now = Date()
        let currentComponents = calendar.dateComponents([.year, .month], from: now)
        
        // Try this month first
        var components = DateComponents()
        components.year = currentComponents.year
        components.month = currentComponents.month
        components.day = paymentDay
        
        if let thisMonthDate = calendar.date(from: components),
           thisMonthDate > now {
            return thisMonthDate
        }
        
        // If this month's date has passed, use next month
        components.month = (currentComponents.month ?? 1) + 1
        if components.month! > 12 {
            components.month = 1
            components.year = (currentComponents.year ?? 2024) + 1
        }
        
        return calendar.date(from: components) ?? now
    }
    
    /// Days remaining until next payment
    var daysUntilPayment: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: nextPaymentDate)
        return max(0, components.day ?? 0)
    }
    
    /// Formatted display of next payment date
    var nextPaymentFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: nextPaymentDate)
    }
    
    // MARK: - Initialization
    
    init() {
        self.displayCurrency = UserDefaults.standard.string(forKey: Keys.displayCurrency) ?? "USD"
        self.paymentDay = UserDefaults.standard.integer(forKey: Keys.paymentDay).clamped(to: 1...28, default: 1)
        self.notificationsEnabled = UserDefaults.standard.bool(forKey: Keys.notificationsEnabled)
        self.notificationDays = UserDefaults.standard.integer(forKey: Keys.notificationDays).clamped(to: 1...7, default: 3)
    }
    
    // MARK: - Public Methods
    
    /// Reset all settings to defaults
    func resetToDefaults() {
        displayCurrency = "USD"
        paymentDay = 1
        notificationsEnabled = true
        notificationDays = 3
    }
    
    /// Validate payment day for current month
    func validatePaymentDay() -> Bool {
        return paymentDay >= 1 && paymentDay <= 28
    }
    
    /// Get payment day options with descriptions
    func getPaymentDayOptions() -> [(value: Int, description: String)] {
        var options: [(Int, String)] = []
        
        // Popular options
        options.append((1, "1st of every month"))
        options.append((15, "15th of every month"))
        
        // Other options
        for day in 2...28 {
            if day != 15 {
                let suffix = day.ordinalSuffix
                options.append((day, "\(day)\(suffix) of every month"))
            }
        }
        
        return options
    }
}

// MARK: - Private Extensions

private extension MonthlyPlanningSettings {
    
    enum Keys {
        static let displayCurrency = "MonthlyPlanning.DisplayCurrency"
        static let paymentDay = "MonthlyPlanning.PaymentDay"
        static let notificationsEnabled = "MonthlyPlanning.NotificationsEnabled"
        static let notificationDays = "MonthlyPlanning.NotificationDays"
    }
}

private extension Int {
    /// Clamp integer value to range with default fallback
    func clamped(to range: ClosedRange<Int>, default defaultValue: Int) -> Int {
        if self == 0 {
            return defaultValue
        }
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
    
    /// Get ordinal suffix for day numbers (1st, 2nd, 3rd, etc.)
    var ordinalSuffix: String {
        switch self % 100 {
        case 11...13:
            return "th"
        default:
            switch self % 10 {
            case 1:
                return "st"
            case 2:
                return "nd"
            case 3:
                return "rd"
            default:
                return "th"
            }
        }
    }
}