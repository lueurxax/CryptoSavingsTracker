//
//  AutomationScheduler.swift
//  CryptoSavingsTracker
//
//  Created for v2.1 - Monthly Planning Execution Automation
//  Manages automated transitions for monthly execution tracking
//

import Foundation
import SwiftData
import UserNotifications

/// Service responsible for scheduling and executing automated monthly planning transitions
@MainActor
final class AutomationScheduler {

    // MARK: - Properties

    private let settings: MonthlyPlanningSettings
    private let notificationManager: NotificationManager
    private let executionTrackingService: ExecutionTrackingService

    // MARK: - Initialization

    init(settings: MonthlyPlanningSettings? = nil,
         notificationManager: NotificationManager? = nil,
         modelContext: ModelContext) {
        self.settings = settings ?? .shared
        self.notificationManager = notificationManager ?? .shared
        self.executionTrackingService = ExecutionTrackingService(modelContext: modelContext)
    }

    // MARK: - Public Methods

    /// Check if any automated transitions should occur and execute them
    func checkAndExecuteAutomation() async throws {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day], from: now)

        guard let day = components.day else { return }

        // Check for auto-start on 1st of month
        if day == 1 && settings.autoStartEnabled {
            try await attemptAutoStart()
        }

        // Check for auto-complete on last day of month
        if isLastDayOfMonth(now) && settings.autoCompleteEnabled {
            try await attemptAutoComplete()
        }
    }

    /// Schedule notifications for upcoming automated transitions
    func scheduleAutomationNotifications() async throws {
        guard await notificationManager.requestPermission() else {
            print("Notification permission not granted, skipping automation notifications")
            return
        }

        // Cancel existing automation notifications
        let identifiers = ["monthly-auto-start", "monthly-auto-complete"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)

        // Schedule auto-start notification (if enabled)
        if settings.autoStartEnabled {
            try await scheduleAutoStartNotification()
        }

        // Schedule auto-complete notification (if enabled)
        if settings.autoCompleteEnabled {
            try await scheduleAutoCompleteNotification()
        }
    }

    // MARK: - Private Methods - Auto Start

    private func attemptAutoStart() async throws {
        let monthLabel = currentMonthLabel()

        // Check if already started
        let existingRecord = try executionTrackingService.getRecord(for: monthLabel)
        if let record = existingRecord, record.status != .draft {
            print("Month \(monthLabel) already started, skipping auto-start")
            return
        }

        // Fetch all plans and active goals
        let planDescriptor = FetchDescriptor<MonthlyPlan>()
        let plans = try executionTrackingService.modelContext.fetch(planDescriptor)

        if plans.isEmpty {
            print("No plans available, skipping auto-start")
            return
        }

        // Fetch all goals
        let goalDescriptor = FetchDescriptor<Goal>()
        let goals = try executionTrackingService.modelContext.fetch(goalDescriptor)

        // Start tracking
        let record = try executionTrackingService.startTracking(
            for: monthLabel,
            from: plans,
            goals: goals
        )

        // Set grace period
        if settings.undoGracePeriodHours > 0 {
            let gracePeriod = TimeInterval(settings.undoGracePeriodHours * 3600)
            record.canUndoUntil = Date().addingTimeInterval(gracePeriod)
        }

        print("Auto-started tracking for \(monthLabel) with \(settings.undoGracePeriodHours)h grace period")

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .monthlyExecutionAutoStarted,
            object: record
        )
    }

    private func scheduleAutoStartNotification() async throws {
        let calendar = Calendar.current
        let now = Date()

        // Get first day of next month
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: now),
              let firstOfNextMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)) else {
            return
        }

        // Schedule notification for 8:00 AM on first of month
        var components = calendar.dateComponents([.year, .month, .day], from: firstOfNextMonth)
        components.hour = 8
        components.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "Monthly Planning Started"
        content.body = "Your monthly savings plan has been automatically started. Open the app to review."
        content.sound = .default
        content.categoryIdentifier = "MONTHLY_AUTO_START"

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "monthly-auto-start",
            content: content,
            trigger: trigger
        )

        try await UNUserNotificationCenter.current().add(request)
        print("Scheduled auto-start notification for \(components)")
    }

    // MARK: - Private Methods - Auto Complete

    private func attemptAutoComplete() async throws {
        let monthLabel = currentMonthLabel()

        // Check if there's an active execution
        let existingRecord = try executionTrackingService.getRecord(for: monthLabel)
        guard let record = existingRecord, record.status == .executing else {
            print("No active execution for \(monthLabel), skipping auto-complete")
            return
        }

        // Mark month as complete
        try await executionTrackingService.markComplete(record)

        // Set grace period
        if settings.undoGracePeriodHours > 0 {
            let gracePeriod = TimeInterval(settings.undoGracePeriodHours * 3600)
            record.canUndoUntil = Date().addingTimeInterval(gracePeriod)
        }

        print("Auto-completed month \(monthLabel) with \(settings.undoGracePeriodHours)h grace period")

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .monthlyExecutionAutoCompleted,
            object: record
        )
    }

    private func scheduleAutoCompleteNotification() async throws {
        let calendar = Calendar.current
        let now = Date()

        // Get last day of current month
        guard let endOfMonth = calendar.date(byAdding: .month, value: 1, to: now),
              let firstOfNextMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: endOfMonth)),
              let lastOfCurrentMonth = calendar.date(byAdding: .day, value: -1, to: firstOfNextMonth) else {
            return
        }

        // Schedule notification for 8:00 PM on last day of month
        var components = calendar.dateComponents([.year, .month, .day], from: lastOfCurrentMonth)
        components.hour = 20
        components.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "Monthly Planning Completed"
        content.body = "Your monthly savings plan has been automatically completed. Open the app to review your progress."
        content.sound = .default
        content.categoryIdentifier = "MONTHLY_AUTO_COMPLETE"

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "monthly-auto-complete",
            content: content,
            trigger: trigger
        )

        try await UNUserNotificationCenter.current().add(request)
        print("Scheduled auto-complete notification for \(components)")
    }

    // MARK: - Helper Methods

    private func currentMonthLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    private func isLastDayOfMonth(_ date: Date) -> Bool {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) else {
            return false
        }

        let todayMonth = calendar.component(.month, from: date)
        let tomorrowMonth = calendar.component(.month, from: tomorrow)

        return todayMonth != tomorrowMonth
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let monthlyExecutionAutoStarted = Notification.Name("monthlyExecutionAutoStarted")
    static let monthlyExecutionAutoCompleted = Notification.Name("monthlyExecutionAutoCompleted")
    static let monthlyExecutionCompleted = Notification.Name("monthlyExecutionCompleted")
}
