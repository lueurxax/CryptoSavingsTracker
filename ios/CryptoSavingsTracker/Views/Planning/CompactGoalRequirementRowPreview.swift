// Extracted preview-only declarations for NAV003 policy compliance.
// Source: CompactGoalRequirementRow.swift

import SwiftUI

#Preview("Compact Goal Row") {
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

    CompactGoalRequirementRow(
        requirement: requirement,
        flexState: .flexible,
        adjustedAmount: nil,
        showBudgetIndicator: false,
        onToggleProtection: {},
        onToggleSkip: {},
        onSetCustomAmount: { _ in }
    )
    .padding()
    .background(.regularMaterial)
}

#Preview("Compact Goal Row Dynamic Type") {
    let requirement = MonthlyRequirement(
        goalId: UUID(),
        goalName: "Emergency Tuition Goal",
        currency: "EUR",
        targetAmount: 12000,
        currentTotal: 2800,
        remainingAmount: 9200,
        monthsRemaining: 2,
        requiredMonthly: 4600,
        progress: 0.23,
        deadline: Calendar.current.date(byAdding: .month, value: 2, to: Date())!,
        status: .attention
    )

    CompactGoalRequirementRow(
        requirement: requirement,
        flexState: .protected,
        adjustedAmount: 4300,
        showBudgetIndicator: true,
        onToggleProtection: {},
        onToggleSkip: {},
        onSetCustomAmount: { _ in }
    )
    .padding()
    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
    .background(.regularMaterial)
}
