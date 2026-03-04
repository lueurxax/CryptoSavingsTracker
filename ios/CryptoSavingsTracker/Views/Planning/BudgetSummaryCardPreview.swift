// Extracted preview-only declarations for NAV003 policy compliance.
// Source: BudgetSummaryCard.swift

//
//  BudgetSummaryCard.swift
//  CryptoSavingsTracker
//
//  Unified budget health widgets for monthly planning.
//

import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

#Preview("1 No Budget") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .noBudget, budgetAmount: nil, budgetCurrency: "USD",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .noBudget, budgetCurrency: "USD", onPrimaryAction: {})
    }.padding()
}

#Preview("2 Healthy") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .healthy, budgetAmount: 5000, budgetCurrency: "USD",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .healthy, budgetCurrency: "USD", onPrimaryAction: {})
    }.padding()
}

#Preview("3 Not Applied") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .notApplied, budgetAmount: 2500, budgetCurrency: "EUR",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .notApplied, budgetCurrency: "EUR", onPrimaryAction: {})
    }.padding()
}

#Preview("4 Needs Recalculation") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .needsRecalculation, budgetAmount: 3000, budgetCurrency: "USD",
            minimumRequired: 3200, nextConstrainedGoal: "Vacation Fund",
            nextDeadline: Calendar.current.date(byAdding: .month, value: 4, to: Date()),
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .needsRecalculation, budgetCurrency: "USD", onPrimaryAction: {})
    }.padding()
}

#Preview("5 At Risk") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .atRisk(shortfall: 4399, goalsAtRisk: 18),
            budgetAmount: 5000, budgetCurrency: "USD",
            minimumRequired: 9399, nextConstrainedGoal: "Emergency Fund",
            nextDeadline: Calendar.current.date(byAdding: .month, value: 2, to: Date()),
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .atRisk(shortfall: 4399, goalsAtRisk: 18), budgetCurrency: "USD", onPrimaryAction: {})
    }.padding()
}

#Preview("6 Severe Risk") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .severeRisk(shortfall: 12500, goalsAtRisk: 8),
            budgetAmount: 3000, budgetCurrency: "USD",
            minimumRequired: 15500, nextConstrainedGoal: "Bitcoin DCA",
            nextDeadline: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .severeRisk(shortfall: 12500, goalsAtRisk: 8), budgetCurrency: "USD", onPrimaryAction: {})
    }.padding()
}

#Preview("7 Stale FX") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .staleFX(lastUpdated: Date().addingTimeInterval(-7200), affectedCurrencies: ["BTC", "ETH"]),
            budgetAmount: 4000, budgetCurrency: "USD",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: "Converted from BTC/ETH holdings at current rates.",
            onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .staleFX(lastUpdated: Date().addingTimeInterval(-7200), affectedCurrencies: ["BTC", "ETH"]), budgetCurrency: "USD", onPrimaryAction: {})
    }.padding()
}

// MARK: - Dark Mode Previews

#Preview("Dark: No Budget") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .noBudget, budgetAmount: nil, budgetCurrency: "USD",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .noBudget, budgetCurrency: "USD", onPrimaryAction: {})
    }.padding().preferredColorScheme(.dark)
}

#Preview("Dark: Healthy") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .healthy, budgetAmount: 5000, budgetCurrency: "USD",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .healthy, budgetCurrency: "USD", onPrimaryAction: {})
    }.padding().preferredColorScheme(.dark)
}

#Preview("Dark: Not Applied") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .notApplied, budgetAmount: 2500, budgetCurrency: "EUR",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .notApplied, budgetCurrency: "EUR", onPrimaryAction: {})
    }.padding().preferredColorScheme(.dark)
}

#Preview("Dark: Needs Recalculation") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .needsRecalculation, budgetAmount: 3000, budgetCurrency: "USD",
            minimumRequired: 3200, nextConstrainedGoal: "Vacation Fund",
            nextDeadline: Calendar.current.date(byAdding: .month, value: 4, to: Date()),
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .needsRecalculation, budgetCurrency: "USD", onPrimaryAction: {})
    }.padding().preferredColorScheme(.dark)
}

#Preview("Dark: At Risk") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .atRisk(shortfall: 4399, goalsAtRisk: 18),
            budgetAmount: 5000, budgetCurrency: "USD",
            minimumRequired: 9399, nextConstrainedGoal: "Emergency Fund",
            nextDeadline: Calendar.current.date(byAdding: .month, value: 2, to: Date()),
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .atRisk(shortfall: 4399, goalsAtRisk: 18), budgetCurrency: "USD", onPrimaryAction: {})
    }.padding().preferredColorScheme(.dark)
}

#Preview("Dark: Severe Risk") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .severeRisk(shortfall: 12500, goalsAtRisk: 8),
            budgetAmount: 3000, budgetCurrency: "USD",
            minimumRequired: 15500, nextConstrainedGoal: "Bitcoin DCA",
            nextDeadline: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            conversionContext: nil, onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .severeRisk(shortfall: 12500, goalsAtRisk: 8), budgetCurrency: "USD", onPrimaryAction: {})
    }.padding().preferredColorScheme(.dark)
}

#Preview("Dark: Stale FX") {
    VStack(spacing: 16) {
        BudgetHealthCard(
            state: .staleFX(lastUpdated: Date().addingTimeInterval(-7200), affectedCurrencies: ["BTC", "ETH"]),
            budgetAmount: 4000, budgetCurrency: "USD",
            minimumRequired: nil, nextConstrainedGoal: nil, nextDeadline: nil,
            conversionContext: "Converted from BTC/ETH holdings at current rates.",
            onPrimaryAction: {}, onEdit: {}
        )
        BudgetHealthCollapsedStrip(state: .staleFX(lastUpdated: Date().addingTimeInterval(-7200), affectedCurrencies: ["BTC", "ETH"]), budgetCurrency: "USD", onPrimaryAction: {})
    }.padding().preferredColorScheme(.dark)
}
