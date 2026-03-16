// Extracted preview-only declarations for NAV003 policy compliance.
// Source: DashboardComponents.swift

import SwiftUI
import SwiftData

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(for: Goal.self, Asset.self, Transaction.self, AssetAllocation.self, configurations: config))
        ?? CryptoSavingsTrackerApp.previewModelContainer

    let goal = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
    let asset = Asset(currency: "USD")
    let deposits = [
        Transaction(amount: 12000, asset: asset, date: Date().addingTimeInterval(-86400 * 20), comment: "Initial deposit"),
        Transaction(amount: 2400, asset: asset, date: Date().addingTimeInterval(-86400 * 10), comment: "Top-up"),
        Transaction(amount: 1800, asset: asset, date: Date().addingTimeInterval(-86400 * 3), comment: "DCA buy")
    ]
    let allocation = AssetAllocation(asset: asset, goal: goal, amount: 16200)

    container.mainContext.insert(goal)
    container.mainContext.insert(asset)
    deposits.forEach { container.mainContext.insert($0) }
    container.mainContext.insert(allocation)

    return GoalDashboardView(goal: goal)
        .modelContainer(container)
}
