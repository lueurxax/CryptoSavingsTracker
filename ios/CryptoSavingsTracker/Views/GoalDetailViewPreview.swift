// Extracted preview-only declarations for NAV003 policy compliance.
// Source: GoalDetailView.swift

import SwiftUI
import SwiftData
import Foundation

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(for: Goal.self, Asset.self, Transaction.self, AssetAllocation.self, configurations: config))
        ?? CryptoSavingsTrackerApp.sharedModelContainer

    let goal = Goal(
        name: "Bitcoin Reserve",
        currency: "USD",
        targetAmount: 12000.0,
        deadline: Date().addingTimeInterval(86400 * 30),
        emoji: "₿",
        description: "Build a reserve for long-term BTC accumulation."
    )
    let asset = Asset(currency: "USD")
    let initialDeposit = Transaction(amount: 2800, asset: asset, comment: "Seed funding")
    let recurringDeposit = Transaction(amount: 950, asset: asset, date: Date().addingTimeInterval(-86400 * 7), comment: "Monthly top-up")
    let allocation = AssetAllocation(asset: asset, goal: goal, amount: 3750)

    container.mainContext.insert(goal)
    container.mainContext.insert(asset)
    container.mainContext.insert(initialDeposit)
    container.mainContext.insert(recurringDeposit)
    container.mainContext.insert(allocation)

    return NavigationStack {
        GoalDetailView(goal: goal)
    }
    .modelContainer(container)
}
