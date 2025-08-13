//
//  NotificationManager.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import UserNotifications
import Foundation
import SwiftData

class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            // Notification permission failed - user will need to enable manually
            return false
        }
    }
    
    func scheduleReminders(for goal: Goal) async {
        let center = UNUserNotificationCenter.current()
        
        // Cancel existing notifications for this goal
        await cancelNotifications(for: goal)
        
        // Check if reminders are enabled
        guard goal.isReminderEnabled else { return }
        
        // Get reminder dates from the goal
        let reminderDates = goal.reminderDates
        
        // Filter to only future dates
        let futureReminderDates = reminderDates.filter { $0 > Date() }
        
        guard !futureReminderDates.isEmpty else { return }
        
        // Get current total for suggested deposit calculation
        // Note: Uses manual balance only. For accurate values with currency conversion, 
        // this would need to use GoalViewModel, but for notification scheduling we use basic calculation
        let currentTotal = goal.currentTotal
        let remainingAmount = max(goal.targetAmount - currentTotal, 0)
        let suggestedDepositAmount = remainingAmount / Double(futureReminderDates.count)
        
        // Schedule new reminders
        for date in futureReminderDates {
            let content = UNMutableNotificationContent()
            content.title = "Savings Reminder: \(goal.name)"
            
            // Create personalized message based on goal progress
            let progressPercent = Int((currentTotal / goal.targetAmount) * 100)
            if progressPercent >= 90 {
                content.body = "You're \(progressPercent)% there! Consider adding \(String(format: "%.2f", suggestedDepositAmount)) \(goal.currency) to reach your goal."
            } else if progressPercent >= 50 {
                content.body = "Halfway there! Add \(String(format: "%.2f", suggestedDepositAmount)) \(goal.currency) to stay on track."
            } else {
                content.body = "Time to save! Add \(String(format: "%.2f", suggestedDepositAmount)) \(goal.currency) toward your \(goal.name) goal."
            }
            
            content.sound = .default
            content.categoryIdentifier = "SAVINGS_REMINDER"
            
            // Use the exact date and time from reminder configuration
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd-HHmm"
            let dateString = dateFormatter.string(from: date)
            let identifier = "\(goal.id.uuidString)-reminder-\(dateString)"
            
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            
            do {
                try await center.add(request)
            } catch {
                print("Failed to schedule notification for \(date): \(error)")
            }
        }
        
        // Log successful scheduling
        print("Scheduled \(futureReminderDates.count) reminders for goal: \(goal.name)")
        if let nextReminder = futureReminderDates.first {
            print("Next reminder: \(nextReminder)")
        }
    }
    
    func cancelNotifications(for goal: Goal) async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        
        let identifiersToRemove = pendingRequests
            .filter { $0.identifier.hasPrefix("\(goal.id.uuidString)-reminder-") || $0.identifier.hasPrefix("\(goal.id.uuidString)-monthly-") }
            .map { $0.identifier }
        
        if !identifiersToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
            print("Cancelled \(identifiersToRemove.count) notifications for goal: \(goal.name)")
        }
    }
    
    // MARK: - Monthly Payment Reminders
    
    /// Schedule monthly payment reminders for all active goals based on Required Monthly calculations
    func scheduleMonthlyPaymentReminders(
        requirements: [MonthlyRequirement],
        modelContext: ModelContext,
        settings: MonthlyReminderSettings
    ) async {
        let center = UNUserNotificationCenter.current()
        
        // Cancel existing monthly reminders
        await cancelAllMonthlyPaymentReminders()
        
        // Group by next payment date
        let upcomingReminders = generateMonthlyReminderSchedule(
            from: requirements,
            settings: settings
        )
        
        for reminder in upcomingReminders {
            do {
                let content = createMonthlyReminderContent(reminder)
                let trigger = createMonthlyReminderTrigger(for: reminder.scheduledDate)
                let identifier = "monthly-payment-\(reminder.month)-\(reminder.year)"
                
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                try await center.add(request)
                
                // Store reminder in database for tracking
                let storedReminder = StoredMonthlyReminder(
                    month: reminder.month,
                    year: reminder.year,
                    scheduledDate: reminder.scheduledDate,
                    totalAmount: reminder.totalAmount,
                    goalCount: reminder.goalRequirements.count,
                    currency: reminder.displayCurrency
                )
                modelContext.insert(storedReminder)
                
                print("📅 Scheduled monthly reminder for \(reminder.month)/\(reminder.year): \(reminder.totalAmount) \(reminder.displayCurrency)")
                
            } catch {
                print("❌ Failed to schedule monthly reminder for \(reminder.month)/\(reminder.year): \(error)")
            }
        }
        
        // Save stored reminders
        try? modelContext.save()
        
        print("✅ Scheduled \(upcomingReminders.count) monthly payment reminders")
    }
    
    /// Schedule smart reminders that adapt based on goal urgency and progress
    func scheduleSmartReminders(
        requirements: [MonthlyRequirement],
        adjustedRequirements: [AdjustedRequirement]? = nil,
        modelContext: ModelContext
    ) async {
        let center = UNUserNotificationCenter.current()
        
        // Cancel existing smart reminders
        await cancelSmartReminders()
        
        let effectiveRequirements = adjustedRequirements ?? requirements.map { req in
            AdjustedRequirement(
                requirement: req,
                adjustedAmount: req.requiredMonthly,
                adjustmentFactor: 1.0,
                redistributionAmount: 0,
                impactAnalysis: ImpactAnalysis(changeAmount: 0, changePercentage: 0, estimatedDelay: 0, riskLevel: .low)
            )
        }
        
        for adjusted in effectiveRequirements {
            let reminderSchedule = generateSmartReminderSchedule(for: adjusted)
            
            for reminderDate in reminderSchedule {
                do {
                    let content = createSmartReminderContent(adjusted, scheduledDate: reminderDate)
                    let trigger = createSmartReminderTrigger(for: reminderDate)
                    let identifier = "smart-\(adjusted.requirement.goalId.uuidString)-\(Int(reminderDate.timeIntervalSince1970))"
                    
                    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                    try await center.add(request)
                    
                } catch {
                    print("❌ Failed to schedule smart reminder for \(adjusted.requirement.goalName): \(error)")
                }
            }
        }
    }
    
    /// Schedule deadline approach warnings for critical goals
    func scheduleDeadlineWarnings(requirements: [MonthlyRequirement]) async {
        let center = UNUserNotificationCenter.current()
        
        // Cancel existing deadline warnings
        await cancelDeadlineWarnings()
        
        let criticalRequirements = requirements.filter { $0.status == .critical || $0.monthsRemaining <= 1 }
        
        for requirement in criticalRequirements {
            let warningDates = generateDeadlineWarningDates(for: requirement)
            
            for (warningDate, warningType) in warningDates {
                do {
                    let content = createDeadlineWarningContent(requirement, type: warningType)
                    let trigger = createDeadlineWarningTrigger(for: warningDate)
                    let identifier = "deadline-\(requirement.goalId.uuidString)-\(warningType.rawValue)"
                    
                    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                    try await center.add(request)
                    
                } catch {
                    print("❌ Failed to schedule deadline warning for \(requirement.goalName): \(error)")
                }
            }
        }
        
        print("⚠️ Scheduled deadline warnings for \(criticalRequirements.count) critical goals")
    }
    
    /// Cancel all monthly payment reminders
    func cancelAllMonthlyPaymentReminders() async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        
        let monthlyIdentifiers = pendingRequests
            .filter { $0.identifier.hasPrefix("monthly-payment-") }
            .map { $0.identifier }
        
        if !monthlyIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: monthlyIdentifiers)
            print("🗑️ Cancelled \(monthlyIdentifiers.count) monthly payment reminders")
        }
    }
    
    /// Cancel smart reminders
    private func cancelSmartReminders() async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        
        let smartIdentifiers = pendingRequests
            .filter { $0.identifier.hasPrefix("smart-") }
            .map { $0.identifier }
        
        if !smartIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: smartIdentifiers)
        }
    }
    
    /// Cancel deadline warnings
    private func cancelDeadlineWarnings() async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        
        let warningIdentifiers = pendingRequests
            .filter { $0.identifier.hasPrefix("deadline-") }
            .map { $0.identifier }
        
        if !warningIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: warningIdentifiers)
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func generateMonthlyReminderSchedule(
        from requirements: [MonthlyRequirement],
        settings: MonthlyReminderSettings
    ) -> [MonthlyReminder] {
        let calendar = Calendar.current
        let today = Date()
        
        var reminders: [MonthlyReminder] = []
        
        // Generate reminders for next 12 months
        for monthOffset in 0..<12 {
            guard let targetMonth = calendar.date(byAdding: .month, value: monthOffset, to: today) else { continue }
            
            let monthComponents = calendar.dateComponents([.year, .month], from: targetMonth)
            let year = monthComponents.year!
            let month = monthComponents.month!
            
            // Calculate scheduled date based on settings
            var scheduledDateComponents = DateComponents()
            scheduledDateComponents.year = year
            scheduledDateComponents.month = month
            scheduledDateComponents.day = settings.dayOfMonth
            scheduledDateComponents.hour = settings.hour
            scheduledDateComponents.minute = settings.minute
            
            guard let scheduledDate = calendar.date(from: scheduledDateComponents),
                  scheduledDate > today else { continue }
            
            // Filter requirements that are still active for this month
            let activeRequirements = requirements.filter { requirement in
                return requirement.deadline >= scheduledDate && requirement.monthsRemaining > monthOffset
            }
            
            guard !activeRequirements.isEmpty else { continue }
            
            let totalAmount = activeRequirements.reduce(0) { sum, req in
                // Convert to display currency (simplified - in real implementation would use ExchangeRateService)
                if req.currency == settings.displayCurrency {
                    return sum + req.requiredMonthly
                } else {
                    return sum + req.requiredMonthly // Fallback to original amount
                }
            }
            
            let reminder = MonthlyReminder(
                month: month,
                year: year,
                scheduledDate: scheduledDate,
                totalAmount: totalAmount,
                goalRequirements: activeRequirements,
                displayCurrency: settings.displayCurrency
            )
            
            reminders.append(reminder)
        }
        
        return reminders
    }
    
    private func generateSmartReminderSchedule(for adjusted: AdjustedRequirement) -> [Date] {
        let calendar = Calendar.current
        let today = Date()
        
        var dates: [Date] = []
        
        // Determine reminder frequency based on risk level and urgency
        let frequency: Int
        switch adjusted.impactAnalysis.riskLevel {
        case .high:
            frequency = adjusted.requirement.monthsRemaining <= 2 ? 3 : 2 // 3x or 2x per month
        case .medium:
            frequency = adjusted.requirement.monthsRemaining <= 3 ? 2 : 1 // 2x or 1x per month
        case .low:
            frequency = 1 // Once per month
        }
        
        // Generate dates for next 3 months
        for monthOffset in 0..<3 {
            guard let targetMonth = calendar.date(byAdding: .month, value: monthOffset, to: today) else { continue }
            
            let monthComponents = calendar.dateComponents([.year, .month], from: targetMonth)
            
            for i in 0..<frequency {
                let dayOffset = (30 / frequency) * i + 5 // Spread throughout month, starting on 5th
                
                var components = monthComponents
                components.day = min(dayOffset, 28) // Avoid month-end issues
                components.hour = 10
                components.minute = 0
                
                if let date = calendar.date(from: components), date > today {
                    dates.append(date)
                }
            }
        }
        
        return dates
    }
    
    private func generateDeadlineWarningDates(for requirement: MonthlyRequirement) -> [(Date, DeadlineWarningType)] {
        let calendar = Calendar.current
        var warnings: [(Date, DeadlineWarningType)] = []
        
        // 1 month before deadline
        if let oneMonthBefore = calendar.date(byAdding: .month, value: -1, to: requirement.deadline) {
            warnings.append((oneMonthBefore, .oneMonth))
        }
        
        // 1 week before deadline
        if let oneWeekBefore = calendar.date(byAdding: .weekOfYear, value: -1, to: requirement.deadline) {
            warnings.append((oneWeekBefore, .oneWeek))
        }
        
        // 1 day before deadline
        if let oneDayBefore = calendar.date(byAdding: .day, value: -1, to: requirement.deadline) {
            warnings.append((oneDayBefore, .oneDay))
        }
        
        return warnings.filter { $0.0 > Date() }
    }
    
    private func createMonthlyReminderContent(_ reminder: MonthlyReminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "💰 Monthly Savings Reminder"
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let monthString = formatter.string(from: reminder.scheduledDate)
        
        let formattedAmount = formatAmount(reminder.totalAmount, currency: reminder.displayCurrency)
        
        if reminder.goalRequirements.count == 1 {
            let goalName = reminder.goalRequirements.first!.goalName
            content.body = "Time to save \(formattedAmount) for your \(goalName) goal this month (\(monthString))"
        } else {
            content.body = "Time to save \(formattedAmount) across \(reminder.goalRequirements.count) goals this month (\(monthString))"
        }
        
        content.sound = .default
        content.categoryIdentifier = "MONTHLY_PAYMENT_REMINDER"
        content.badge = NSNumber(value: reminder.goalRequirements.count)
        
        // Add action buttons
        content.categoryIdentifier = "MONTHLY_SAVINGS"
        
        return content
    }
    
    private func createSmartReminderContent(_ adjusted: AdjustedRequirement, scheduledDate: Date) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        
        let formattedAmount = formatAmount(adjusted.adjustedAmount, currency: adjusted.requirement.currency)
        
        switch adjusted.impactAnalysis.riskLevel {
        case .high:
            content.title = "🚨 Critical Goal Alert"
            content.body = "Your \(adjusted.requirement.goalName) goal needs \(formattedAmount) this month to stay on track!"
        case .medium:
            content.title = "⚠️ Savings Reminder"
            content.body = "Don't forget: \(formattedAmount) needed for \(adjusted.requirement.goalName) this month"
        case .low:
            content.title = "💡 Gentle Reminder"
            content.body = "Consider saving \(formattedAmount) for \(adjusted.requirement.goalName) when you can"
        }
        
        content.sound = adjusted.impactAnalysis.riskLevel == .high ? .defaultCritical : .default
        content.categoryIdentifier = "SMART_REMINDER"
        
        return content
    }
    
    private func createDeadlineWarningContent(_ requirement: MonthlyRequirement, type: DeadlineWarningType) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "⏰ Goal Deadline Approaching"
        
        let remaining = formatAmount(requirement.remainingAmount, currency: requirement.currency)
        
        switch type {
        case .oneMonth:
            content.body = "One month left for \(requirement.goalName)! \(remaining) remaining to reach your target."
        case .oneWeek:
            content.body = "One week left for \(requirement.goalName)! \(remaining) still needed."
        case .oneDay:
            content.body = "Final day for \(requirement.goalName)! \(remaining) remaining."
        }
        
        content.sound = .defaultCritical
        content.categoryIdentifier = "DEADLINE_WARNING"
        
        return content
    }
    
    private func createMonthlyReminderTrigger(for date: Date) -> UNCalendarNotificationTrigger {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
    
    private func createSmartReminderTrigger(for date: Date) -> UNCalendarNotificationTrigger {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
    
    private func createDeadlineWarningTrigger(for date: Date) -> UNCalendarNotificationTrigger {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
    
    private func formatAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(Int(amount))"
    }
}

// MARK: - Supporting Data Structures

/// Settings for monthly payment reminders
struct MonthlyReminderSettings {
    let dayOfMonth: Int
    let hour: Int
    let minute: Int
    let displayCurrency: String
    
    static let `default` = MonthlyReminderSettings(
        dayOfMonth: 1,
        hour: 9,
        minute: 0,
        displayCurrency: "USD"
    )
}

/// Represents a scheduled monthly reminder
struct MonthlyReminder {
    let month: Int
    let year: Int
    let scheduledDate: Date
    let totalAmount: Double
    let goalRequirements: [MonthlyRequirement]
    let displayCurrency: String
}

/// SwiftData model for storing monthly reminder history
@Model
final class StoredMonthlyReminder {
    var month: Int
    var year: Int
    var scheduledDate: Date
    var totalAmount: Double
    var goalCount: Int
    var currency: String
    var wasCompleted: Bool = false
    var completedDate: Date?
    
    init(month: Int, year: Int, scheduledDate: Date, totalAmount: Double, goalCount: Int, currency: String) {
        self.month = month
        self.year = year
        self.scheduledDate = scheduledDate
        self.totalAmount = totalAmount
        self.goalCount = goalCount
        self.currency = currency
    }
}

/// Types of deadline warnings
enum DeadlineWarningType: String, CaseIterable {
    case oneMonth = "one_month"
    case oneWeek = "one_week"
    case oneDay = "one_day"
}

private extension DateComponents {
    func createTrigger() -> UNCalendarNotificationTrigger? {
        guard let _ = year, let _ = month, let _ = day else { return nil }
        return UNCalendarNotificationTrigger(dateMatching: self, repeats: false)
    }
}