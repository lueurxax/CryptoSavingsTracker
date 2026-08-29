// Preview-only fixtures for AssetSharingView.

import SwiftData
import SwiftUI

#Preview("Pending review") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(
        for: Goal.self,
        Asset.self,
        Transaction.self,
        AssetAllocation.self,
        configurations: config
    )) ?? CryptoSavingsTrackerApp.previewModelContainer

    let marriage = Goal(
        name: "Seroglazov marriage and extended family celebration",
        currency: "EUR",
        targetAmount: 7_000,
        deadline: Date().addingTimeInterval(86_400 * 90)
    )
    let pending = Goal(
        name: "Previous finished wallet-funded goal awaiting one-time review",
        currency: "EUR",
        targetAmount: 4_456,
        deadline: Date().addingTimeInterval(-86_400)
    )
    pending.lifecycleStatus = .finished
    let reserved = Goal(
        name: "Previous manually tracked purchase",
        currency: "EUR",
        targetAmount: 686,
        deadline: Date().addingTimeInterval(-86_400 * 30)
    )
    reserved.lifecycleStatus = .finished

    let asset = Asset(currency: "USDT")
    let deposit = Transaction(amount: 5_873.6673, asset: asset)
    let marriageAllocation = AssetAllocation(asset: asset, goal: marriage, amount: 695)
    let pendingAllocation = AssetAllocation(asset: asset, goal: pending, amount: 4_456)
    let reservedAllocation = AssetAllocation(asset: asset, goal: reserved, amount: 686)

    let settledAt = Date().addingTimeInterval(-86_400 * 30)
    reserved.completionSnapshotData = try? GoalCompletionSnapshotCodec.encode(
        GoalCompletionSnapshot(
            id: UUID(),
            schemaVersion: GoalCompletionSnapshot.currentSchemaVersion,
            goalID: reserved.id,
            goalName: reserved.name,
            goalCurrency: reserved.currency,
            goalTargetAmount: reserved.targetAmount,
            goalCompletedAt: settledAt,
            snapshotCreatedAt: settledAt,
            entries: [
                GoalCompletionSnapshot.Entry(
                    allocationID: reservedAllocation.id,
                    assetID: asset.id,
                    assetCurrency: asset.currency,
                    amount: reservedAllocation.amountValue,
                    accountingMode: .manual,
                    settlement: .keepAsSpent,
                    bestKnownBalance: 5_873.6673,
                    balanceCapturedAt: settledAt,
                    balanceTiming: .completionTime
                )
            ]
        )
    )

    asset.transactions = [deposit]
    asset.allocations = [marriageAllocation, pendingAllocation, reservedAllocation]
    marriage.allocations = [marriageAllocation]
    pending.allocations = [pendingAllocation]
    reserved.allocations = [reservedAllocation]

    container.mainContext.insert(marriage)
    container.mainContext.insert(pending)
    container.mainContext.insert(reserved)
    container.mainContext.insert(asset)
    container.mainContext.insert(deposit)
    container.mainContext.insert(marriageAllocation)
    container.mainContext.insert(pendingAllocation)
    container.mainContext.insert(reservedAllocation)

    return AssetSharingView(asset: asset, currentGoalId: marriage.id)
        .modelContainer(container)
}

#Preview("Active allocations only") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(
        for: Goal.self,
        Asset.self,
        Transaction.self,
        AssetAllocation.self,
        configurations: config
    )) ?? CryptoSavingsTrackerApp.previewModelContainer

    let goal = Goal(
        name: "Emergency fund",
        currency: "USD",
        targetAmount: 10_000,
        deadline: Date().addingTimeInterval(86_400 * 120)
    )
    let asset = Asset(currency: "USDT")
    let deposit = Transaction(amount: 5_873.6673, asset: asset)
    let allocation = AssetAllocation(asset: asset, goal: goal, amount: 1_410)

    asset.transactions = [deposit]
    asset.allocations = [allocation]
    goal.allocations = [allocation]

    container.mainContext.insert(goal)
    container.mainContext.insert(asset)
    container.mainContext.insert(deposit)
    container.mainContext.insert(allocation)

    return AssetSharingView(asset: asset, currentGoalId: goal.id)
        .modelContainer(container)
}

#Preview("Reserved as spent") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = (try? ModelContainer(
        for: Goal.self,
        Asset.self,
        Transaction.self,
        AssetAllocation.self,
        configurations: config
    )) ?? CryptoSavingsTrackerApp.previewModelContainer

    let active = Goal(
        name: "Emergency fund",
        currency: "USD",
        targetAmount: 10_000,
        deadline: Date().addingTimeInterval(86_400 * 120)
    )
    let finished = Goal(
        name: "A very long finished goal name that remains readable at accessibility sizes",
        currency: "USD",
        targetAmount: 4_427,
        deadline: Date().addingTimeInterval(-86_400)
    )
    finished.lifecycleStatus = .finished

    let asset = Asset(currency: "USDT")
    let deposit = Transaction(amount: 5_873.6673, asset: asset)
    let activeAllocation = AssetAllocation(asset: asset, goal: active, amount: 1_410)
    let finishedAllocation = AssetAllocation(asset: asset, goal: finished, amount: 4_427)
    let settledAt = Date().addingTimeInterval(-86_400)
    finished.completionSnapshotData = try? GoalCompletionSnapshotCodec.encode(
        GoalCompletionSnapshot(
            id: UUID(),
            schemaVersion: GoalCompletionSnapshot.currentSchemaVersion,
            goalID: finished.id,
            goalName: finished.name,
            goalCurrency: finished.currency,
            goalTargetAmount: finished.targetAmount,
            goalCompletedAt: settledAt,
            snapshotCreatedAt: settledAt,
            entries: [
                GoalCompletionSnapshot.Entry(
                    allocationID: finishedAllocation.id,
                    assetID: asset.id,
                    assetCurrency: asset.currency,
                    amount: finishedAllocation.amountValue,
                    accountingMode: .manual,
                    settlement: .keepAsSpent,
                    bestKnownBalance: 5_873.6673,
                    balanceCapturedAt: settledAt,
                    balanceTiming: .completionTime
                )
            ]
        )
    )

    asset.transactions = [deposit]
    asset.allocations = [activeAllocation, finishedAllocation]
    active.allocations = [activeAllocation]
    finished.allocations = [finishedAllocation]

    container.mainContext.insert(active)
    container.mainContext.insert(finished)
    container.mainContext.insert(asset)
    container.mainContext.insert(deposit)
    container.mainContext.insert(activeAllocation)
    container.mainContext.insert(finishedAllocation)

    return AssetSharingView(asset: asset, currentGoalId: active.id)
        .modelContainer(container)
}
