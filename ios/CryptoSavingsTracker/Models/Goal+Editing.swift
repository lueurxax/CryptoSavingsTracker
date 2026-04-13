//
//  Goal+Editing.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import Foundation
import SwiftData

enum GoalValidationField: String, CaseIterable, Hashable {
    case name
    case targetAmount
    case deadline
    case startDate
}

// MARK: - Goal Editing Extensions
extension Goal {
    // Lifecycle helpers (soft-delete / cancel / finish)
    var isArchived: Bool {
        lifecycleStatus == .deleted
    }

    func archive() {
        softDelete()
    }

    func restore() {
        restoreToActive()
    }

    func softDelete(at timestamp: Date = Date()) {
        lifecycleStatus = .deleted
        lifecycleStatusChangedAt = timestamp
        lastModifiedDate = timestamp
    }

    func markCancelled(at timestamp: Date = Date()) {
        lifecycleStatus = .cancelled
        lifecycleStatusChangedAt = timestamp
        lastModifiedDate = timestamp
    }

    func markFinished(at timestamp: Date = Date()) {
        lifecycleStatus = .finished
        lifecycleStatusChangedAt = timestamp
        lastModifiedDate = timestamp
    }

    func restoreToActive(at timestamp: Date = Date()) {
        lifecycleStatus = .active
        lifecycleStatusChangedAt = timestamp
        lastModifiedDate = timestamp
    }

    func clearRetiredReminderState() {
        reminderFrequency = nil
        reminderTime = nil
        firstReminderDate = nil
    }
    
    // Change detection
    func hasChanges(from snapshot: GoalSnapshot) -> Bool {
        return name != snapshot.name ||
               targetAmount != snapshot.targetAmount ||
               deadline != snapshot.deadline ||
               startDate != snapshot.startDate ||
               reminderFrequency != snapshot.reminderFrequency ||
               reminderTime != snapshot.reminderTime ||
               emoji != snapshot.emoji ||
               goalDescription != snapshot.goalDescription ||
               link != snapshot.link
    }
    
    func createSnapshot() -> GoalSnapshot {
        GoalSnapshot(from: self)
    }
    
    // Validation
    func validate() -> [String] {
        let fieldErrors = validationErrorsByField()
        return GoalValidationField.allCases.compactMap { fieldErrors[$0] }
    }

    func validationErrorsByField(referenceDate: Date = Date()) -> [GoalValidationField: String] {
        var errors: [GoalValidationField: String] = [:]

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.name] = "Goal name is required"
        }

        if targetAmount <= 0 {
            errors[.targetAmount] = "Target amount must be greater than zero"
        }

        if deadline <= referenceDate {
            errors[.deadline] = "Deadline must be in the future"
        } else {
            let daysRemaining = Calendar.current.dateComponents([.day], from: referenceDate, to: deadline).day ?? 0
            if daysRemaining < 7 {
                errors[.deadline] = "Deadline should be at least 7 days from now"
            }
        }

        if startDate > deadline {
            errors[.startDate] = "Start date must be before deadline"
        }

        return errors
    }
    
    // Impact calculations
    func calculateImpact(from snapshot: GoalSnapshot) -> GoalImpact {
        let oldProgress = calculateProgress(targetAmount: snapshot.targetAmount, currentTotal: currentTotal)
        let newProgress = progress
        
        let oldDailyTarget = calculateDailyTarget(
            targetAmount: snapshot.targetAmount,
            currentTotal: currentTotal,
            deadline: snapshot.deadline
        )
        let newDailyTarget = suggestedDailyDeposit
        
        let oldDaysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: snapshot.deadline).day ?? 0
        let newDaysRemaining = daysRemaining
        
        return GoalImpact(
            oldProgress: oldProgress,
            newProgress: newProgress,
            oldDailyTarget: oldDailyTarget,
            newDailyTarget: newDailyTarget,
            oldDaysRemaining: oldDaysRemaining,
            newDaysRemaining: newDaysRemaining,
            oldTargetAmount: snapshot.targetAmount,
            newTargetAmount: targetAmount,
            significantChange: Swift.abs(newProgress - oldProgress) > 0.1 || Swift.abs(newDailyTarget - oldDailyTarget) > 50
        )
    }
    
    private func calculateProgress(targetAmount: Double, currentTotal: Double) -> Double {
        guard targetAmount > 0 else { return 0 }
        return min(currentTotal / targetAmount, 1.0)
    }
    
    private func calculateDailyTarget(targetAmount: Double, currentTotal: Double, deadline: Date) -> Double {
        let remaining = max(0, targetAmount - currentTotal)
        let days = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
        guard days > 0 else { return remaining }
        return remaining / Double(days)
    }
}

// MARK: - Goal Snapshot
struct GoalSnapshot: Codable {
    let id: UUID
    let name: String
    let targetAmount: Double
    let deadline: Date
    let startDate: Date
    let currency: String
    let reminderFrequency: String?
    let reminderTime: Date?
    let emoji: String?
    let goalDescription: String?
    let link: String?
    let capturedAt: Date
    
    init(from goal: Goal) {
        self.id = goal.id
        self.name = goal.name
        self.targetAmount = goal.targetAmount
        self.deadline = goal.deadline
        self.startDate = goal.startDate
        self.currency = goal.currency
        self.reminderFrequency = goal.reminderFrequency
        self.reminderTime = goal.reminderTime
        self.emoji = goal.emoji
        self.goalDescription = goal.goalDescription
        self.link = goal.link
        self.capturedAt = Date()
    }
}

// MARK: - Goal Impact
struct GoalImpact {
    let oldProgress: Double
    let newProgress: Double
    let oldDailyTarget: Double
    let newDailyTarget: Double
    let oldDaysRemaining: Int
    let newDaysRemaining: Int
    let oldTargetAmount: Double
    let newTargetAmount: Double
    let significantChange: Bool
    
    var progressChange: Double {
        newProgress - oldProgress
    }
    
    var dailyTargetChange: Double {
        newDailyTarget - oldDailyTarget
    }
    
    var targetAmountChange: Double {
        newTargetAmount - oldTargetAmount
    }
    
    var daysRemainingChange: Int {
        newDaysRemaining - oldDaysRemaining
    }
    
    var isPositiveChange: Bool {
        // Positive if progress increased or daily target decreased
        progressChange > 0 || dailyTargetChange < 0
    }
}
