import Foundation

enum FinishedAllocationEditorState: Equatable {
    case pendingReview
    case reservedAsSpent
}

enum AssetAllocationEditorWarning: Equatable {
    case none
    case reviewFinishedAllocations
    case reduceActiveAllocations
}

struct AssetAllocationEditorEntry: Equatable, Identifiable {
    let goalID: UUID
    let goalName: String
    let status: GoalLifecycleStatus
    let amount: Double
    let finishedState: FinishedAllocationEditorState?

    init(
        goalID: UUID,
        goalName: String,
        status: GoalLifecycleStatus,
        amount: Double,
        finishedState: FinishedAllocationEditorState? = nil
    ) {
        self.goalID = goalID
        self.goalName = goalName
        self.status = status
        self.amount = amount
        self.finishedState = finishedState
    }

    var id: UUID { goalID }
}

struct AssetAllocationEditorBreakdown: Equatable {
    let activeAllocatedAmount: Double
    let pendingReviewAmount: Double
    let finishedReservedAmount: Double
    let unallocatedAmount: Double
    let activePercentage: Double
    let pendingReviewPercentage: Double
    let finishedReservedPercentage: Double
    let unallocatedPercentage: Double
}

enum AssetAllocationEditorPolicy {
    static func breakdown(
        balance: Double,
        entries: [AssetAllocationEditorEntry]
    ) -> AssetAllocationEditorBreakdown {
        let normalizedBalance = max(0, balance)
        let activeAllocated = entries
            .filter { $0.status == .active }
            .reduce(0) { $0 + max(0, $1.amount) }
        let pendingReview = entries
            .filter { $0.status == .finished && $0.finishedState == .pendingReview }
            .reduce(0) { $0 + max(0, $1.amount) }
        let finishedReserved = entries
            .filter { $0.status == .finished && $0.finishedState == .reservedAsSpent }
            .reduce(0) { $0 + max(0, $1.amount) }
        let totalAllocated = activeAllocated + pendingReview + finishedReserved
        let totalForPresentation = max(normalizedBalance, totalAllocated)
        let unallocated = max(0, normalizedBalance - totalAllocated)

        guard totalForPresentation > 0 else {
            return AssetAllocationEditorBreakdown(
                activeAllocatedAmount: 0,
                pendingReviewAmount: 0,
                finishedReservedAmount: 0,
                unallocatedAmount: 0,
                activePercentage: 0,
                pendingReviewPercentage: 0,
                finishedReservedPercentage: 0,
                unallocatedPercentage: 1
            )
        }

        return AssetAllocationEditorBreakdown(
            activeAllocatedAmount: activeAllocated,
            pendingReviewAmount: pendingReview,
            finishedReservedAmount: finishedReserved,
            unallocatedAmount: unallocated,
            activePercentage: activeAllocated / totalForPresentation,
            pendingReviewPercentage: pendingReview / totalForPresentation,
            finishedReservedPercentage: finishedReserved / totalForPresentation,
            unallocatedPercentage: unallocated / totalForPresentation
        )
    }

    static func warning(
        balance: Double,
        entries: [AssetAllocationEditorEntry]
    ) -> AssetAllocationEditorWarning {
        let normalizedBalance = max(0, balance)
        let normalizedEntries = entries.map { max(0, $0.amount) }
        guard normalizedEntries.reduce(0, +) > normalizedBalance + 0.000001 else {
            return .none
        }
        if entries.contains(where: {
            $0.status == .finished
                && $0.finishedState == .pendingReview
                && $0.amount > 0.0000001
        }) {
            return .reviewFinishedAllocations
        }
        return .reduceActiveAllocations
    }

    static func amountsForSave(
        activeGoalIDs: [UUID],
        draft: [UUID: Double],
        existingEntries: [AssetAllocationEditorEntry]
    ) -> [UUID: Double] {
        var result: [UUID: Double] = [:]

        for goalID in activeGoalIDs {
            result[goalID] = max(0, draft[goalID] ?? 0)
        }

        for entry in existingEntries where entry.status == .finished {
            result[entry.goalID] = max(0, entry.amount)
        }

        return result
    }

    static func clearingActiveAllocations(
        in draft: [UUID: Double],
        activeGoalIDs: [UUID]
    ) -> [UUID: Double] {
        var result = draft
        for goalID in activeGoalIDs {
            result.removeValue(forKey: goalID)
        }
        return result
    }
}
