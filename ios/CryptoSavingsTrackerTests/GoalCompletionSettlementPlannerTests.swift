import Foundation
import Testing
@testable import CryptoSavingsTracker

struct GoalCompletionSettlementPlannerTests {
    private let planner = GoalCompletionSettlementPlanner()

    @Test("new completion automates manual and on-chain entries")
    func automaticNewCompletion() throws {
        let manual = input(currency: "USD", amount: 10, mode: .manual)
        let onChain = input(currency: "USDT", amount: 20, mode: .onChain)
        let plan = planner.makePlan(goalID: UUID(), origin: .newCompletion, allocations: [manual, onChain])

        #expect(plan.unresolvedAllocationIDs.isEmpty)
        let resolved = try planner.resolve(plan: plan, decisions: [])
        #expect(resolved[manual.allocationID] == .keepAsSpent)
        #expect(resolved[onChain.allocationID] == .balanceAlreadyDecreased)
    }

    @Test("new mixed entry requires a decision")
    func mixedRequiresDecision() throws {
        let mixed = input(currency: "USDT", amount: 35, mode: .mixed)
        let plan = planner.makePlan(goalID: UUID(), origin: .newCompletion, allocations: [mixed])

        #expect(plan.unresolvedAllocationIDs == [mixed.allocationID])
        #expect(throws: GoalCompletionSettlementPlanningError.missingDecision(mixed.allocationID)) {
            try planner.resolve(plan: plan, decisions: [])
        }
    }

    @Test("legacy review requires an explicit decision for every accounting mode")
    func legacyRequiresEveryDecision() {
        let entries = [
            input(currency: "USD", amount: 10, mode: .manual),
            input(currency: "USDT", amount: 20, mode: .onChain),
            input(currency: "BTC", amount: 0.1, mode: .mixed)
        ]
        let plan = planner.makePlan(goalID: UUID(), origin: .legacyReview, allocations: entries)

        #expect(Set(plan.unresolvedAllocationIDs) == Set(entries.map(\.allocationID)))
        #expect(plan.items.first { $0.input.accountingMode == .manual }?.recommendedSettlement == .keepAsSpent)
        #expect(
            plan.items.first { $0.input.accountingMode == .onChain }?.recommendedSettlement
                == .balanceAlreadyDecreased
        )
        #expect(plan.items.first { $0.input.accountingMode == .mixed }?.recommendedSettlement == nil)
    }

    @Test("release summary is grouped by asset currency")
    func releaseSummaryGroupsCurrencies() throws {
        let first = input(currency: "USDT", amount: 20, mode: .mixed)
        let second = input(currency: "usdt", amount: 15, mode: .mixed)
        let btc = input(currency: "BTC", amount: 0.1, mode: .mixed)
        let plan = planner.makePlan(goalID: UUID(), origin: .newCompletion, allocations: [first, second, btc])
        let decisions = [first, second, btc].map {
            GoalCompletionSettlementDecision(
                allocationID: $0.allocationID,
                settlement: .balanceAlreadyDecreased
            )
        }

        #expect(try planner.releaseSummary(plan: plan, decisions: decisions) == [
            GoalCompletionCurrencyAmount(currency: "BTC", amount: 0.1),
            GoalCompletionCurrencyAmount(currency: "USDT", amount: 35)
        ])
    }

    @Test("plan order and fingerprint ignore cache-only balance evidence")
    func deterministicFingerprint() {
        let btcAllocationID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let usdtAllocationID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let btcAssetID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let usdtAssetID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let goalID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let cachedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let btc = input(
            allocationID: btcAllocationID,
            assetID: btcAssetID,
            currency: "BTC",
            amount: 0.1,
            mode: .onChain,
            bestKnownBalance: 1,
            balanceCapturedAt: cachedAt
        )
        let usdt = input(
            allocationID: usdtAllocationID,
            assetID: usdtAssetID,
            currency: "USDT",
            amount: 20,
            mode: .manual,
            bestKnownBalance: 40,
            balanceCapturedAt: cachedAt
        )
        let refreshedBTC = input(
            allocationID: btcAllocationID,
            assetID: btcAssetID,
            currency: "BTC",
            amount: 0.1,
            mode: .onChain,
            bestKnownBalance: 2,
            balanceCapturedAt: cachedAt.addingTimeInterval(60)
        )
        let refreshedUSDT = input(
            allocationID: usdtAllocationID,
            assetID: usdtAssetID,
            currency: "USDT",
            amount: 20,
            mode: .manual,
            bestKnownBalance: 80,
            balanceCapturedAt: cachedAt.addingTimeInterval(60)
        )

        let initial = planner.makePlan(
            goalID: goalID,
            origin: .newCompletion,
            allocations: [usdt, btc]
        )
        let refreshed = planner.makePlan(
            goalID: goalID,
            origin: .newCompletion,
            allocations: [refreshedBTC, refreshedUSDT]
        )

        #expect(initial.items.map(\.id) == [btcAllocationID, usdtAllocationID])
        #expect(initial.fingerprint == refreshed.fingerprint)
        #expect(initial.fingerprint == GoalCompletionAllocationFingerprint(entries: [
            GoalCompletionAllocationFingerprint.Entry(
                allocationID: btcAllocationID,
                assetID: btcAssetID,
                assetCurrency: "BTC",
                amount: 0.1,
                accountingMode: .onChain
            ),
            GoalCompletionAllocationFingerprint.Entry(
                allocationID: usdtAllocationID,
                assetID: usdtAssetID,
                assetCurrency: "USDT",
                amount: 20,
                accountingMode: .manual
            )
        ]))
    }

    @Test("currency normalization ignores case but detects meaningful currency changes")
    func currencyNormalizationIsCaseInsensitiveButMeaningful() {
        let allocationID = UUID()
        let assetID = UUID()
        let goalID = UUID()
        let initial = planner.makePlan(
            goalID: goalID,
            origin: .newCompletion,
            allocations: [
                input(
                    allocationID: allocationID,
                    assetID: assetID,
                    currency: "USDT",
                    amount: 20,
                    mode: .onChain
                )
            ]
        )
        let caseOnly = planner.makePlan(
            goalID: goalID,
            origin: .newCompletion,
            allocations: [
                input(
                    allocationID: allocationID,
                    assetID: assetID,
                    currency: "usdt",
                    amount: 20,
                    mode: .onChain
                )
            ]
        )
        let changed = planner.makePlan(
            goalID: goalID,
            origin: .newCompletion,
            allocations: [
                input(
                    allocationID: allocationID,
                    assetID: assetID,
                    currency: "EUR",
                    amount: 20,
                    mode: .onChain
                )
            ]
        )

        #expect(initial.fingerprint == caseOnly.fingerprint)
        #expect(initial.fingerprint != changed.fingerprint)
        #expect(initial.fingerprint.entries.first?.assetCurrency == "USDT")
    }

    @Test("resolver rejects unknown and duplicate decisions")
    func rejectsInvalidDecisions() throws {
        let mixed = input(currency: "USDT", amount: 35, mode: .mixed)
        let plan = planner.makePlan(goalID: UUID(), origin: .newCompletion, allocations: [mixed])
        let decision = GoalCompletionSettlementDecision(
            allocationID: mixed.allocationID,
            settlement: .keepAsSpent
        )
        let unknownID = UUID()

        #expect(throws: GoalCompletionSettlementPlanningError.unknownDecision(unknownID)) {
            try planner.resolve(
                plan: plan,
                decisions: [
                    GoalCompletionSettlementDecision(
                        allocationID: unknownID,
                        settlement: .balanceAlreadyDecreased
                    )
                ]
            )
        }
        #expect(throws: GoalCompletionSettlementPlanningError.duplicateDecision(mixed.allocationID)) {
            try planner.resolve(plan: plan, decisions: [decision, decision])
        }
    }

    private func input(
        allocationID: UUID = UUID(),
        assetID: UUID = UUID(),
        currency: String,
        amount: Double,
        mode: AssetBalanceAccountingMode,
        bestKnownBalance: Double? = nil,
        balanceCapturedAt: Date? = nil
    ) -> GoalCompletionAllocationInput {
        GoalCompletionAllocationInput(
            allocationID: allocationID,
            assetID: assetID,
            assetCurrency: currency,
            amount: amount,
            accountingMode: mode,
            bestKnownBalance: bestKnownBalance,
            balanceCapturedAt: balanceCapturedAt
        )
    }
}
