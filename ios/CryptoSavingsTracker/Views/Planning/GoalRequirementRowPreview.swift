// Extracted preview-only declarations for NAV003 policy compliance.
// Source: GoalRequirementRow.swift

import SwiftUI

#Preview("Normal Goal") {
    let requirement = MonthlyRequirement(
        goalId: UUID(),
        goalName: "Bitcoin Savings",
        currency: "USD",
        targetAmount: 10000,
        currentTotal: 3500,
        remainingAmount: 6500,
        monthsRemaining: 8,
        requiredMonthly: 812.50,
        progress: 0.35,
        deadline: Calendar.current.date(byAdding: .month, value: 8, to: Date())!,
        status: .onTrack
    )
    
    VStack(spacing: 16) {
        GoalRequirementRow(
            requirement: requirement,
            flexState: .flexible,
            adjustedAmount: nil,
            onToggleProtection: {},
            onToggleSkip: {}
        )
        
        GoalRequirementRow(
            requirement: requirement,
            flexState: .protected,
            adjustedAmount: 600.0, // Adjusted down
            onToggleProtection: {},
            onToggleSkip: {}
        )
    }
    .padding()
    .background(.regularMaterial)
}

#Preview("Critical Goal") {
    let requirement = MonthlyRequirement(
        goalId: UUID(),
        goalName: "Emergency Fund",
        currency: "EUR",
        targetAmount: 15000,
        currentTotal: 2000,
        remainingAmount: 13000,
        monthsRemaining: 1,
        requiredMonthly: 13000,
        progress: 0.13,
        deadline: Calendar.current.date(byAdding: .month, value: 1, to: Date())!,
        status: .critical
    )
    
    GoalRequirementRow(
        requirement: requirement,
        flexState: .flexible,
        adjustedAmount: nil,
        onToggleProtection: {},
        onToggleSkip: {}
    )
    .padding()
    .background(.regularMaterial)
}
