import Foundation

enum GoalCompletionSettlementOrigin: String, Codable, Sendable {
    case newCompletion
    case legacyReview
}

struct GoalCompletionAllocationInput: Equatable, Identifiable, Sendable {
    let allocationID: UUID
    let assetID: UUID
    let assetCurrency: String
    let amount: Double
    let accountingMode: AssetBalanceAccountingMode
    let bestKnownBalance: Double?
    let balanceCapturedAt: Date?

    var id: UUID { allocationID }
}

struct GoalCompletionAllocationFingerprint: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let allocationID: UUID
        let assetID: UUID
        let amount: Double
        let accountingMode: AssetBalanceAccountingMode
    }

    let entries: [Entry]
}

struct GoalCompletionSettlementDecision: Equatable, Sendable {
    let allocationID: UUID
    let settlement: FinishedAllocationSettlement
}

struct GoalCompletionCurrencyAmount: Equatable, Sendable {
    let currency: String
    let amount: Double
}

struct GoalCompletionSettlementItem: Equatable, Identifiable, Sendable {
    let input: GoalCompletionAllocationInput
    let automaticSettlement: FinishedAllocationSettlement?
    let recommendedSettlement: FinishedAllocationSettlement?

    var id: UUID { input.allocationID }
}

struct GoalCompletionSettlementPlan: Equatable, Sendable {
    let goalID: UUID
    let origin: GoalCompletionSettlementOrigin
    let items: [GoalCompletionSettlementItem]
    let fingerprint: GoalCompletionAllocationFingerprint

    var unresolvedAllocationIDs: [UUID] {
        items.filter { $0.automaticSettlement == nil }.map(\.id)
    }
}

enum GoalCompletionSettlementPlanningError: Error, Equatable {
    case missingDecision(UUID)
    case duplicateDecision(UUID)
    case unknownDecision(UUID)
}

struct GoalCompletionSettlementPlanner {
    func makePlan(
        goalID: UUID,
        origin: GoalCompletionSettlementOrigin,
        allocations: [GoalCompletionAllocationInput]
    ) -> GoalCompletionSettlementPlan {
        let sorted = allocations.sorted {
            if $0.assetCurrency != $1.assetCurrency {
                return $0.assetCurrency < $1.assetCurrency
            }
            return $0.allocationID.uuidString < $1.allocationID.uuidString
        }
        let items = sorted.map { input -> GoalCompletionSettlementItem in
            let recommendation: FinishedAllocationSettlement?
            switch input.accountingMode {
            case .manual:
                recommendation = .keepAsSpent
            case .onChain:
                recommendation = .balanceAlreadyDecreased
            case .mixed:
                recommendation = nil
            }

            let automatic: FinishedAllocationSettlement?
            if origin == .legacyReview {
                automatic = nil
            } else {
                automatic = recommendation
            }
            return GoalCompletionSettlementItem(
                input: input,
                automaticSettlement: automatic,
                recommendedSettlement: recommendation
            )
        }
        let fingerprintEntries = sorted.map {
            GoalCompletionAllocationFingerprint.Entry(
                allocationID: $0.allocationID,
                assetID: $0.assetID,
                amount: $0.amount,
                accountingMode: $0.accountingMode
            )
        }
        return GoalCompletionSettlementPlan(
            goalID: goalID,
            origin: origin,
            items: items,
            fingerprint: GoalCompletionAllocationFingerprint(entries: fingerprintEntries)
        )
    }

    func resolve(
        plan: GoalCompletionSettlementPlan,
        decisions: [GoalCompletionSettlementDecision]
    ) throws -> [UUID: FinishedAllocationSettlement] {
        let validIDs = Set(plan.items.map(\.id))
        var decisionsByID: [UUID: FinishedAllocationSettlement] = [:]
        for decision in decisions {
            guard validIDs.contains(decision.allocationID) else {
                throw GoalCompletionSettlementPlanningError.unknownDecision(decision.allocationID)
            }
            guard decisionsByID[decision.allocationID] == nil else {
                throw GoalCompletionSettlementPlanningError.duplicateDecision(decision.allocationID)
            }
            decisionsByID[decision.allocationID] = decision.settlement
        }

        var result: [UUID: FinishedAllocationSettlement] = [:]
        for item in plan.items {
            if let automatic = item.automaticSettlement {
                result[item.id] = automatic
            } else if let decision = decisionsByID[item.id] {
                result[item.id] = decision
            } else {
                throw GoalCompletionSettlementPlanningError.missingDecision(item.id)
            }
        }
        return result
    }

    func releaseSummary(
        plan: GoalCompletionSettlementPlan,
        decisions: [GoalCompletionSettlementDecision]
    ) throws -> [GoalCompletionCurrencyAmount] {
        let resolved = try resolve(plan: plan, decisions: decisions)
        let grouped = plan.items.reduce(into: [String: Double]()) { totals, item in
            guard resolved[item.id] == .balanceAlreadyDecreased else { return }
            totals[item.input.assetCurrency, default: 0] += item.input.amount
        }
        return grouped.keys.sorted().map {
            GoalCompletionCurrencyAmount(currency: $0, amount: grouped[$0] ?? 0)
        }
    }
}
