// Extracted preview-only declarations for NAV003 policy compliance.
// Source: SharedAssetIndicator.swift

import SwiftUI
import SwiftData

struct SharedAssetIndicator_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = (try? ModelContainer(
            for: Goal.self,
            Asset.self,
            Transaction.self,
            AssetAllocation.self,
            configurations: config
        )) ?? CryptoSavingsTrackerApp.sharedModelContainer

        let goal = Goal(
            name: "Test Goal",
            currency: "USD",
            targetAmount: 10000,
            deadline: Date().addingTimeInterval(86400 * 30)
        )
        let asset = Asset(currency: "BTC")

        container.mainContext.insert(goal)
        container.mainContext.insert(asset)

        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 0.5)
        container.mainContext.insert(allocation)

        return VStack {
            SharedAssetIndicator(asset: asset, currentGoal: goal)
            AssetListItemView(asset: asset, goal: goal)
        }
        .padding()
        .modelContainer(container)
    }
}
