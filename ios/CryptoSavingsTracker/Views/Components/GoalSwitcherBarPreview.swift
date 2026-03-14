// Extracted preview-only declarations for NAV003 policy compliance.
// Source: GoalSwitcherBar.swift

//
//  GoalSwitcherBar.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

#Preview {
    @Previewable @State var selectedGoal: Goal? = nil
    
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config))
        ?? CryptoSavingsTrackerApp.sharedModelContainer
    
    let goal1 = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 30))
    let goal2 = Goal(name: "Ethereum Fund", currency: "USD", targetAmount: 25000, deadline: Date().addingTimeInterval(86400 * 60))
    let goal3 = Goal(name: "Emergency Crypto", currency: "USD", targetAmount: 10000, deadline: Date().addingTimeInterval(86400 * 90))
    
    return VStack {
        GoalSwitcherBar(selectedGoal: $selectedGoal, goals: [goal1, goal2, goal3])
        Spacer()
    }
    .modelContainer(container)
    .onAppear {
        container.mainContext.insert(goal1)
        container.mainContext.insert(goal2)
        container.mainContext.insert(goal3)
        selectedGoal = goal1
    }
}
