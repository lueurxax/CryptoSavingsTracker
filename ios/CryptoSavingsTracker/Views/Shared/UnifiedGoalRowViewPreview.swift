// Extracted preview-only declarations for NAV003 policy compliance.
// Source: UnifiedGoalRowView.swift

//
//  UnifiedGoalRowView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 10/08/2025.
//
//  Purpose: Single, configurable goal row component that works across all platforms
//  Replaces both GoalRowView (iOS) and GoalSidebarRow (macOS) with style-based configuration

import SwiftUI
import SwiftData

#Preview("Detailed Style (iOS)") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config))
        ?? CryptoSavingsTrackerApp.sharedModelContainer
    
    let goal = Goal(
        name: "Emergency Fund",
        currency: "USD",
        targetAmount: 5000,
        deadline: Date().addingTimeInterval(86400 * 90),
        emoji: "🛡️"
    )
    goal.goalDescription = "Build a safety net for unexpected expenses"
    container.mainContext.insert(goal)
    
    return List {
        UnifiedGoalRowView.iOS(goal: goal)
    }
    .modelContainer(container)
}

#Preview("Compact Style (macOS)") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config))
        ?? CryptoSavingsTrackerApp.sharedModelContainer
    
    let goal = Goal(
        name: "Bitcoin Savings",
        currency: "BTC",
        targetAmount: 1.5,
        deadline: Date().addingTimeInterval(86400 * 180),
        emoji: "₿"
    )
    container.mainContext.insert(goal)
    
    return List {
        UnifiedGoalRowView.macOS(goal: goal)
    }
    .modelContainer(container)
}

#Preview("Minimal Style") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config))
        ?? CryptoSavingsTrackerApp.sharedModelContainer
    
    let goal = Goal(
        name: "Vacation Fund",
        currency: "EUR",
        targetAmount: 3000,
        deadline: Date().addingTimeInterval(86400 * 60),
        emoji: "✈️"
    )
    container.mainContext.insert(goal)
    
    return VStack {
        UnifiedGoalRowView.minimal(goal: goal)
            .padding()
    }
    .modelContainer(container)
}
