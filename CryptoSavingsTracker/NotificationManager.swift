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
    
    func initialize() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    func scheduleNotifications(for goal: Goal) {
        let center = UNUserNotificationCenter.current()
        
        let deadlineIdentifier = "goal-deadline-\(goal.id.uuidString)"
        let reminderIdentifier = "goal-reminder-\(goal.id.uuidString)"
        
        center.removePendingNotificationRequests(withIdentifiers: [deadlineIdentifier, reminderIdentifier])
        
        let deadlineContent = UNMutableNotificationContent()
        deadlineContent.title = "Goal Deadline Reached"
        deadlineContent.body = "Your goal \"\(goal.name)\" deadline is today!"
        deadlineContent.sound = .default
        
        if let deadlineTrigger = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: goal.deadline).createTrigger() {
            let deadlineRequest = UNNotificationRequest(identifier: deadlineIdentifier, content: deadlineContent, trigger: deadlineTrigger)
            center.add(deadlineRequest)
        }
        
        let reminderDate = Calendar.current.date(byAdding: .day, value: -3, to: goal.deadline)
        if let reminderDate = reminderDate, reminderDate > Date() {
            let reminderContent = UNMutableNotificationContent()
            reminderContent.title = "Goal Reminder"
            reminderContent.body = "Your goal \"\(goal.name)\" deadline is in 3 days!"
            reminderContent.sound = .default
            
            if let reminderTrigger = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate).createTrigger() {
                let reminderRequest = UNNotificationRequest(identifier: reminderIdentifier, content: reminderContent, trigger: reminderTrigger)
                center.add(reminderRequest)
            }
        }
    }
    
    func cancelNotifications(for goal: Goal) {
        let center = UNUserNotificationCenter.current()
        let identifiers = [
            "goal-deadline-\(goal.id.uuidString)",
            "goal-reminder-\(goal.id.uuidString)"
        ]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

private extension DateComponents {
    func createTrigger() -> UNCalendarNotificationTrigger? {
        guard let year = year, let month = month, let day = day else { return nil }
        return UNCalendarNotificationTrigger(dateMatching: self, repeats: false)
    }
}