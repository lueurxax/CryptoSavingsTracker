//
//  MonthlyRequirement.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 09/08/2025.
//

import Foundation

/// Represents the monthly savings requirement for a goal
struct MonthlyRequirement: Identifiable, Sendable, Codable {
    let id: UUID
    let goalId: UUID
    let goalName: String
    let currency: String
    let targetAmount: Double
    let currentTotal: Double
    let remainingAmount: Double
    let monthsRemaining: Int
    let requiredMonthly: Double
    let progress: Double
    let deadline: Date
    let status: RequirementStatus
    
    init(goalId: UUID, goalName: String, currency: String, targetAmount: Double, currentTotal: Double, remainingAmount: Double, monthsRemaining: Int, requiredMonthly: Double, progress: Double, deadline: Date, status: RequirementStatus) {
        self.id = UUID()
        self.goalId = goalId
        self.goalName = goalName
        self.currency = currency
        self.targetAmount = targetAmount
        self.currentTotal = currentTotal
        self.remainingAmount = remainingAmount
        self.monthsRemaining = monthsRemaining
        self.requiredMonthly = requiredMonthly
        self.progress = progress
        self.deadline = deadline
        self.status = status
    }
    
    /// Time remaining description
    var timeRemainingDescription: String {
        if monthsRemaining <= 0 {
            return "Overdue"
        } else if monthsRemaining == 1 {
            return "1 month left"
        } else {
            return "\(monthsRemaining) months left"
        }
    }
}

// MARK: - Formatting Extensions
extension MonthlyRequirement {
    /// Formatted required monthly amount
    func formattedRequiredMonthly() -> String {
        MonthlyRequirementFormatter.formatAmount(requiredMonthly, currency: currency)
    }
    
    /// Formatted remaining amount  
    func formattedRemainingAmount() -> String {
        MonthlyRequirementFormatter.formatAmount(remainingAmount, currency: currency)
    }
}

/// Utility for formatting MonthlyRequirement amounts
struct MonthlyRequirementFormatter {
    static func formatAmount(_ amount: Double, currency: String) -> String {
        // Use a simple fallback formatting to avoid MainActor requirements
        return "\(currency) \(Int(amount.rounded()))"
    }
}

/// Status of a monthly requirement
enum RequirementStatus: String, Sendable, Codable {
    case completed = "completed"
    case onTrack = "on_track"
    case attention = "attention" 
    case critical = "critical"
    
    var displayName: String {
        switch self {
        case .completed: return "Completed"
        case .onTrack: return "On Track"
        case .attention: return "Needs Attention"
        case .critical: return "Critical"
        }
    }
    
    var systemImageName: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .onTrack: return "checkmark.circle"
        case .attention: return "exclamationmark.triangle"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }
}