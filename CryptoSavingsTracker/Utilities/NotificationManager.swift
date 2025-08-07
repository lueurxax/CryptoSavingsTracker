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
        
        // Get current total for accurate suggested deposit calculation
        let currentTotal = await goal.getCurrentTotal()
        let remainingAmount = max(goal.targetAmount - currentTotal, 0)
        let remainingDatesCount = goal.remainingDates.count
        
        guard remainingDatesCount > 0 else { return }
        
        let suggestedDepositAmount = remainingAmount / Double(remainingDatesCount)
        
        // Schedule new reminders
        for date in goal.remainingDates {
            let content = UNMutableNotificationContent()
            content.title = "Reminder: \(goal.name)"
            content.body = "Add \(String(format: "%.2f", suggestedDepositAmount)) \(goal.currency) by today."
            content.sound = .default
            
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: date)
            let identifier = "\(goal.id.uuidString)-reminder-\(dateString)"
            
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            
            do {
                try await center.add(request)
            } catch {
                // Notification scheduling failed for date
            }
        }
    }
    
    func cancelNotifications(for goal: Goal) async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        
        let identifiersToRemove = pendingRequests
            .filter { $0.identifier.hasPrefix("\(goal.id.uuidString)-reminder-") }
            .map { $0.identifier }
        
        center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
    }
}

private extension DateComponents {
    func createTrigger() -> UNCalendarNotificationTrigger? {
        guard let _ = year, let _ = month, let _ = day else { return nil }
        return UNCalendarNotificationTrigger(dateMatching: self, repeats: false)
    }
}