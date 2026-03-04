// Extracted preview-only declarations for NAV003 policy compliance.
// Source: MonthlyPlanningSettingsView.swift

import SwiftUI
import SwiftData

#Preview {
    let goal1 = SimpleGoal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
    let goal2 = SimpleGoal(name: "Ethereum Fund", currency: "EUR", targetAmount: 25000, deadline: Date().addingTimeInterval(86400 * 60))
    
    MonthlyPlanningSettingsView(goals: [goal1, goal2])
}
