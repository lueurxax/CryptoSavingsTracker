// Extracted preview-only declarations for NAV003 policy compliance.
// Source: GoalsListContainer.swift

import SwiftUI
import SwiftData

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(for: Goal.self, Asset.self, Transaction.self, AssetAllocation.self, configurations: config))
        ?? CryptoSavingsTrackerApp.sharedModelContainer

    let goal1 = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
    let goal2 = Goal(name: "Emergency Buffer", currency: "USD", targetAmount: 10000, deadline: Date().addingTimeInterval(86400 * 45))
    let btcAsset = Asset(currency: "USD")
    let stablecoinAsset = Asset(currency: "USD")
    let btcDeposit = Transaction(amount: 18500, asset: btcAsset)
    let stablecoinDeposit = Transaction(amount: 4200, asset: stablecoinAsset)
    let btcAllocation = AssetAllocation(asset: btcAsset, goal: goal1, amount: 18500)
    let stablecoinAllocation = AssetAllocation(asset: stablecoinAsset, goal: goal2, amount: 4200)

    container.mainContext.insert(goal1)
    container.mainContext.insert(goal2)
    container.mainContext.insert(btcAsset)
    container.mainContext.insert(stablecoinAsset)
    container.mainContext.insert(btcDeposit)
    container.mainContext.insert(stablecoinDeposit)
    container.mainContext.insert(btcAllocation)
    container.mainContext.insert(stablecoinAllocation)

    return GoalsListContainer(selectedView: .constant(DetailViewType.details))
        .modelContainer(container)
}
