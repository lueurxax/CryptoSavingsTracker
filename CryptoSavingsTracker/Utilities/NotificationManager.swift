//
//  NotificationManager.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import UserNotifications
import Foundation

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
            .filter { $0.identifier.hasPrefix("\(goal.id.uuidString)-reminder-") }
            .map { $0.identifier }
        
        if !identifiersToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
            print("Cancelled \(identifiersToRemove.count) notifications for goal: \(goal.name)")
        }
    }
}

private extension DateComponents {
    func createTrigger() -> UNCalendarNotificationTrigger? {
        guard let _ = year, let _ = month, let _ = day else { return nil }
        return UNCalendarNotificationTrigger(dateMatching: self, repeats: false)
    }
}