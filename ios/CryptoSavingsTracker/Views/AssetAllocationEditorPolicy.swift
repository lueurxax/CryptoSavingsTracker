import Foundation

enum FinishedAllocationEditorState: Equatable {
    case pendingReview
    case reservedAsSpent
}

enum AssetAllocationEditorWarning: Equatable {
    case none
    case reviewFinishedAllocations
    case reduceActiveAllocations
    case reservedAllocationDataConflict
}

struct AssetAllocationEditorEntryID: Hashable {
    let goalID: UUID
    let allocationID: UUID
}

struct AssetAllocationEditorEntry: Equatable, Identifiable {
    let allocationID: UUID
    let assetID: UUID
    let goalID: UUID
    let goalName: String
    let status: GoalLifecycleStatus
    let amount: Double
    let finishedState: FinishedAllocationEditorState?

    init(
        allocationID: UUID,
        assetID: UUID,
        goalID: UUID,
        goalName: String,
        status: GoalLifecycleStatus,
        amount: Double,
        finishedState: FinishedAllocationEditorState? = nil
    ) {
        self.allocationID = allocationID
        self.assetID = assetID
        self.goalID = goalID
        self.goalName = goalName
        self.status = status
        self.amount = amount
        self.finishedState = finishedState
    }

    var id: AssetAllocationEditorEntryID {
        AssetAllocationEditorEntryID(goalID: goalID, allocationID: allocationID)
    }
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
    let activeChartPercentage: Double
    let pendingReviewChartPercentage: Double
    let finishedReservedChartPercentage: Double
    let unallocatedChartPercentage: Double
}

enum AssetAllocationEditorPolicy {
    static let allocationEpsilon = 0.000000001

    static func shouldPresentAllocation(amount: Double) -> Bool {
        amount > allocationEpsilon
    }

    static func finishedState(
        allocationID: UUID,
        goalID: UUID,
        assetID: UUID,
        amount: Double,
        goalStatus: GoalLifecycleStatus,
        hasCompletionSnapshotData: Bool,
        snapshot: GoalCompletionSnapshot?
    ) -> FinishedAllocationEditorState? {
        guard goalStatus == .finished else { return nil }
        guard hasCompletionSnapshotData else { return .pendingReview }
        guard let snapshot, snapshot.goalID == goalID else { return nil }
        guard snapshot.entries.contains(where: {
            $0.allocationID == allocationID
                && $0.assetID == assetID
                && $0.settlement == .keepAsSpent
                && abs($0.amount - amount) <= allocationEpsilon
        }) else { return nil }
        return .reservedAsSpent
    }

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
        let chartDenominator = max(normalizedBalance, totalAllocated)
        let unallocated = max(0, normalizedBalance - totalAllocated)

        guard chartDenominator > 0 else {
            return AssetAllocationEditorBreakdown(
                activeAllocatedAmount: 0,
                pendingReviewAmount: 0,
                finishedReservedAmount: 0,
                unallocatedAmount: 0,
                activePercentage: 0,
                pendingReviewPercentage: 0,
                finishedReservedPercentage: 0,
                unallocatedPercentage: 1,
                activeChartPercentage: 0,
                pendingReviewChartPercentage: 0,
                finishedReservedChartPercentage: 0,
                unallocatedChartPercentage: 1
            )
        }

        let displayDenominator = normalizedBalance > allocationEpsilon
            ? normalizedBalance
            : chartDenominator

        return AssetAllocationEditorBreakdown(
            activeAllocatedAmount: activeAllocated,
            pendingReviewAmount: pendingReview,
            finishedReservedAmount: finishedReserved,
            unallocatedAmount: unallocated,
            activePercentage: activeAllocated / displayDenominator,
            pendingReviewPercentage: pendingReview / displayDenominator,
            finishedReservedPercentage: finishedReserved / displayDenominator,
            unallocatedPercentage: unallocated / displayDenominator,
            activeChartPercentage: activeAllocated / chartDenominator,
            pendingReviewChartPercentage: pendingReview / chartDenominator,
            finishedReservedChartPercentage: finishedReserved / chartDenominator,
            unallocatedChartPercentage: unallocated / chartDenominator
        )
    }

    static func warning(
        balance: Double,
        entries: [AssetAllocationEditorEntry]
    ) -> AssetAllocationEditorWarning {
        let normalizedBalance = max(0, balance)
        let normalizedEntries = entries.map { max(0, $0.amount) }
        guard normalizedEntries.reduce(0, +) > normalizedBalance + allocationEpsilon else {
            return .none
        }
        let reservedAmount = entries
            .filter { $0.status == .finished && $0.finishedState == .reservedAsSpent }
            .reduce(0) { $0 + max(0, $1.amount) }
        if reservedAmount > normalizedBalance + allocationEpsilon {
            return .reservedAllocationDataConflict
        }

        let activeAmount = entries
            .filter { $0.status == .active }
            .reduce(0) { $0 + max(0, $1.amount) }
        if activeAmount > allocationEpsilon,
           reservedAmount + activeAmount > normalizedBalance + allocationEpsilon {
            return .reduceActiveAllocations
        }

        let pendingReviewAmount = entries
            .filter { $0.status == .finished && $0.finishedState == .pendingReview }
            .reduce(0) { $0 + max(0, $1.amount) }
        if pendingReviewAmount > allocationEpsilon {
            return .reviewFinishedAllocations
        }
        return .reservedAllocationDataConflict
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
