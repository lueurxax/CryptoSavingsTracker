# Source-Aware Finished Allocation Settlement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Settle finished-goal allocations exactly once according to manual, on-chain, or mixed balance accounting while preserving immutable completion history and giving legacy records a safe one-time review.

**Architecture:** Add a versioned Codable completion snapshot to `Goal`, keep balance-source classification and settlement planning pure, and apply one or many approved settlement plans through a single SwiftData save with rollback on failure. Route every iOS Finish entry point through one reusable coordinator/sheet, then reuse the same service for whole-goal legacy review from the asset allocation editor.

**Tech Stack:** Swift 5+, SwiftUI, Observation, SwiftData, XCTest, Swift Testing, XCUITest, Xcode `xcodebuild`

**Spec:** `docs/superpowers/specs/2026-08-29-source-aware-finished-allocation-settlement-design.md`

## Global Constraints

- Initial implementation is iOS-only; the settlement vocabulary and snapshot payload remain platform-neutral.
- `manual` means there is no pair of non-empty wallet address and chain identifier.
- `onChain` means valid wallet tracking and no manual transactions.
- `mixed` means valid wallet tracking and at least one manual transaction; transaction existence, not net manual balance, is authoritative.
- New manual allocations automatically use `keepAsSpent`; new on-chain allocations automatically use `balanceAlreadyDecreased`; new mixed allocations require a choice.
- Legacy finished allocations without a completion snapshot are never released automatically and `Later` performs no mutation.
- A completion snapshot is immutable and settlement is final; do not add correction, reopening, or restoration UI.
- Snapshot creation, allocation release/retention, zero-value history, lifecycle transition, and active-execution removal must be one SwiftData save.
- Wallet refresh and exchange-rate failures must not block finishing or legacy review.
- Preserve all unrelated dirty work. Before editing an existing file, inspect `git diff -- <path>`; never restore or overwrite changes outside this plan.
- Commit only exact task paths with `git commit --only`; the worktree already contains unrelated staged and unstaged changes.
- Do not change `AllocationService.swift`; its save-per-asset behavior is intentionally bypassed by the new atomic settlement service and the file already has unrelated edits.
- All commands below run from `ios/` unless the step explicitly starts with `cd ..`.
- Do not disable, skip, or comment out a failing test.

---

### Task 1: Persist the Immutable Completion Snapshot

**Files:**
- Create: `ios/CryptoSavingsTracker/Models/GoalCompletionSnapshot.swift`
- Modify: `ios/CryptoSavingsTracker/Models/Goal.swift`
- Create: `ios/CryptoSavingsTrackerTests/GoalCompletionSnapshotTests.swift`

**Interfaces:**
- Consumes: existing `Goal.id`, `Goal.name`, `Goal.currency`, `Goal.targetAmount`, and lifecycle timestamps.
- Produces: `AssetBalanceAccountingMode`, `FinishedAllocationSettlement`, `GoalCompletionBalanceTiming`, `GoalCompletionSnapshot.Entry`, `GoalCompletionSnapshotCodec.encode(_:)`, `GoalCompletionSnapshotCodec.decode(_:)`, and `Goal.completionSnapshotData: Data?`.

- [ ] **Step 1: Write the failing snapshot codec tests**

Create `CryptoSavingsTrackerTests/GoalCompletionSnapshotTests.swift` with these cases:

```swift
import Foundation
import Testing
@testable import CryptoSavingsTracker

struct GoalCompletionSnapshotTests {
    @Test("snapshot version 1 round-trips every settlement field")
    func versionOneRoundTrip() throws {
        let completedAt = Date(timeIntervalSince1970: 1_000)
        let createdAt = Date(timeIntervalSince1970: 1_005)
        let entry = GoalCompletionSnapshot.Entry(
            allocationID: UUID(),
            assetID: UUID(),
            assetCurrency: "USDT",
            amount: 35,
            accountingMode: .onChain,
            settlement: .balanceAlreadyDecreased,
            bestKnownBalance: 5_873.6673,
            balanceCapturedAt: createdAt,
            balanceTiming: .completionTime
        )
        let snapshot = GoalCompletionSnapshot(
            id: UUID(),
            schemaVersion: 1,
            goalID: UUID(),
            goalName: "Marriage",
            goalCurrency: "EUR",
            goalTargetAmount: 7_000,
            goalCompletedAt: completedAt,
            snapshotCreatedAt: createdAt,
            entries: [entry]
        )

        let decoded = try GoalCompletionSnapshotCodec.decode(
            GoalCompletionSnapshotCodec.encode(snapshot)
        )

        #expect(decoded == snapshot)
    }

    @Test("unsupported snapshot schema is rejected")
    func unsupportedSchemaIsRejected() throws {
        let snapshot = GoalCompletionSnapshot(
            id: UUID(),
            schemaVersion: 2,
            goalID: UUID(),
            goalName: "Future",
            goalCurrency: "USD",
            goalTargetAmount: 1,
            goalCompletedAt: .distantPast,
            snapshotCreatedAt: .distantPast,
            entries: []
        )

        #expect(throws: GoalCompletionSnapshotCodecError.unsupportedSchemaVersion(2)) {
            try GoalCompletionSnapshotCodec.decode(JSONEncoder().encode(snapshot))
        }
    }

    @Test("legacy review balance is labeled as review-time evidence")
    func legacyBalanceTimingSurvivesRoundTrip() throws {
        let entry = GoalCompletionSnapshot.Entry(
            allocationID: UUID(),
            assetID: UUID(),
            assetCurrency: "BTC",
            amount: 0.1,
            accountingMode: .mixed,
            settlement: .keepAsSpent,
            bestKnownBalance: 0.2,
            balanceCapturedAt: Date(timeIntervalSince1970: 2_000),
            balanceTiming: .reviewTime
        )
        #expect(entry.balanceTiming == .reviewTime)
    }
}
```

- [ ] **Step 2: Run the tests and verify the new types are missing**

Run:

```bash
xcodebuild -scheme CryptoSavingsTrackerTests -destination 'platform=macOS' test \
  -only-testing:CryptoSavingsTrackerTests/GoalCompletionSnapshotTests \
  -derivedDataPath ./DerivedDataCodex \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM=''
```

Expected: FAIL with unresolved identifiers such as `GoalCompletionSnapshot` and `GoalCompletionSnapshotCodec`.

- [ ] **Step 3: Add the snapshot domain types and strict codec**

Create `GoalCompletionSnapshot.swift` with these declarations and exact raw values:

```swift
import Foundation

enum AssetBalanceAccountingMode: String, Codable, Sendable, CaseIterable {
    case manual
    case onChain
    case mixed
}

enum FinishedAllocationSettlement: String, Codable, Sendable, CaseIterable {
    case keepAsSpent
    case balanceAlreadyDecreased
}

enum GoalCompletionBalanceTiming: String, Codable, Sendable {
    case completionTime
    case reviewTime
}

struct GoalCompletionSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    struct Entry: Codable, Equatable, Identifiable, Sendable {
        let allocationID: UUID
        let assetID: UUID
        let assetCurrency: String
        let amount: Double
        let accountingMode: AssetBalanceAccountingMode
        let settlement: FinishedAllocationSettlement
        let bestKnownBalance: Double?
        let balanceCapturedAt: Date?
        let balanceTiming: GoalCompletionBalanceTiming

        var id: UUID { allocationID }
    }

    let id: UUID
    let schemaVersion: Int
    let goalID: UUID
    let goalName: String
    let goalCurrency: String
    let goalTargetAmount: Double
    let goalCompletedAt: Date
    let snapshotCreatedAt: Date
    let entries: [Entry]
}

enum GoalCompletionSnapshotCodecError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}

enum GoalCompletionSnapshotCodec {
    static func encode(_ snapshot: GoalCompletionSnapshot) throws -> Data {
        try JSONEncoder().encode(snapshot)
    }

    static func decode(_ data: Data) throws -> GoalCompletionSnapshot {
        let snapshot = try JSONDecoder().decode(GoalCompletionSnapshot.self, from: data)
        guard snapshot.schemaVersion == GoalCompletionSnapshot.currentSchemaVersion else {
            throw GoalCompletionSnapshotCodecError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }
        return snapshot
    }
}
```

Add the following stored and computed properties next to the lifecycle fields in `Goal.swift`:

```swift
var completionSnapshotData: Data?

var completionSnapshot: GoalCompletionSnapshot? {
    guard let completionSnapshotData else { return nil }
    return try? GoalCompletionSnapshotCodec.decode(completionSnapshotData)
}
```

Keep the persisted property optional so existing local and CloudKit records remain valid.

- [ ] **Step 4: Run the focused tests and a SwiftData persistence smoke test**

Add this test to the same test file before running:

```swift
import SwiftData

@MainActor
@Test("goal stores an optional completion snapshot")
func goalStoresOptionalSnapshot() throws {
    let container = try TestContainer.create()
    let context = ModelContext(container)
    let goal = TestDataFactory.createSampleGoal(name: "Persisted")
    context.insert(goal)
    try context.save()
    #expect(goal.completionSnapshotData == nil)

    let snapshot = GoalCompletionSnapshot(
        id: UUID(), schemaVersion: 1, goalID: goal.id, goalName: goal.name,
        goalCurrency: goal.currency, goalTargetAmount: goal.targetAmount,
        goalCompletedAt: .now, snapshotCreatedAt: .now, entries: []
    )
    goal.completionSnapshotData = try GoalCompletionSnapshotCodec.encode(snapshot)
    try context.save()
    #expect(goal.completionSnapshot == snapshot)
}
```

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit only the snapshot files**

```bash
git add CryptoSavingsTracker/Models/GoalCompletionSnapshot.swift \
  CryptoSavingsTracker/Models/Goal.swift \
  CryptoSavingsTrackerTests/GoalCompletionSnapshotTests.swift
git commit --only CryptoSavingsTracker/Models/GoalCompletionSnapshot.swift \
  CryptoSavingsTracker/Models/Goal.swift \
  CryptoSavingsTrackerTests/GoalCompletionSnapshotTests.swift \
  -m "feat: persist goal completion snapshots"
git show --stat --oneline HEAD
```

Expected: the commit contains exactly three files.

---

### Task 2: Classify Manual, On-Chain, and Mixed Assets

**Files:**
- Create: `ios/CryptoSavingsTracker/Services/AssetBalanceAccountingModeResolver.swift`
- Create: `ios/CryptoSavingsTrackerTests/AssetBalanceAccountingModeResolverTests.swift`

**Interfaces:**
- Consumes: `Asset.address`, `Asset.chainId`, and `Transaction.source`.
- Produces: `AssetBalanceAccountingEvidence`, `AssetBalanceAccountingModeResolver.resolve(_:)`, and `AssetBalanceAccountingModeResolver.resolve(asset:)`.

- [ ] **Step 1: Write the resolver matrix tests**

Create `AssetBalanceAccountingModeResolverTests.swift`:

```swift
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct AssetBalanceAccountingModeResolverTests {
    @Test(arguments: [
        (nil as String?, nil as String?),
        ("" as String?, "ethereum" as String?),
        ("0xabc" as String?, "" as String?)
    ])
    func missingWalletPairIsManual(address: String?, chainID: String?) {
        let evidence = AssetBalanceAccountingEvidence(
            hasTrackedWallet: address?.isEmpty == false && chainID?.isEmpty == false,
            hasManualTransactions: false
        )
        #expect(AssetBalanceAccountingModeResolver.resolve(evidence) == .manual)
    }

    @Test("tracked wallet without manual transactions is on-chain even without a cached balance")
    func trackedWalletIsOnChain() {
        let asset = Asset(
            currency: "USDT",
            address: "0x\(UUID().uuidString)",
            chainId: "ethereum"
        )
        #expect(AssetBalanceAccountingModeResolver.resolve(asset: asset) == .onChain)
    }

    @Test("any manual transaction makes a tracked wallet mixed")
    func trackedWalletWithManualHistoryIsMixed() {
        let asset = Asset(currency: "USDT", address: "0xabc", chainId: "ethereum")
        asset.transactions = [Transaction(amount: 1, asset: asset, source: .manual)]
        #expect(AssetBalanceAccountingModeResolver.resolve(asset: asset) == .mixed)
    }

    @Test("zero net manual history remains mixed")
    func zeroNetManualHistoryIsMixed() {
        let asset = Asset(currency: "USDT", address: "0xabc", chainId: "ethereum")
        asset.transactions = [
            Transaction(amount: 1, asset: asset, source: .manual),
            Transaction(amount: -1, asset: asset, source: .manual)
        ]
        #expect(asset.manualBalance == 0)
        #expect(AssetBalanceAccountingModeResolver.resolve(asset: asset) == .mixed)
    }
}
```

- [ ] **Step 2: Run the resolver tests and verify failure**

Run the Task 1 test command with `-only-testing:CryptoSavingsTrackerTests/AssetBalanceAccountingModeResolverTests`.

Expected: FAIL because the resolver and evidence types do not exist.

- [ ] **Step 3: Implement the pure resolver and model adapter**

Create `AssetBalanceAccountingModeResolver.swift`:

```swift
import Foundation

struct AssetBalanceAccountingEvidence: Equatable, Sendable {
    let hasTrackedWallet: Bool
    let hasManualTransactions: Bool
}

enum AssetBalanceAccountingModeResolver {
    static func resolve(_ evidence: AssetBalanceAccountingEvidence) -> AssetBalanceAccountingMode {
        guard evidence.hasTrackedWallet else { return .manual }
        return evidence.hasManualTransactions ? .mixed : .onChain
    }

    @MainActor
    static func resolve(asset: Asset) -> AssetBalanceAccountingMode {
        let hasTrackedWallet = asset.address?.isEmpty == false && asset.chainId?.isEmpty == false
        let hasManualTransactions = (asset.transactions ?? []).contains { $0.source == .manual }
        return resolve(
            AssetBalanceAccountingEvidence(
                hasTrackedWallet: hasTrackedWallet,
                hasManualTransactions: hasManualTransactions
            )
        )
    }
}
```

Do not read cached balance, freshness, Tatum state, or exchange rates in this resolver.

- [ ] **Step 4: Run the resolver and snapshot suites**

Run:

```bash
xcodebuild -scheme CryptoSavingsTrackerTests -destination 'platform=macOS' test \
  -only-testing:CryptoSavingsTrackerTests/AssetBalanceAccountingModeResolverTests \
  -only-testing:CryptoSavingsTrackerTests/GoalCompletionSnapshotTests \
  -derivedDataPath ./DerivedDataCodex \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM=''
```

Expected: PASS.

- [ ] **Step 5: Commit the resolver**

```bash
git add CryptoSavingsTracker/Services/AssetBalanceAccountingModeResolver.swift \
  CryptoSavingsTrackerTests/AssetBalanceAccountingModeResolverTests.swift
git commit --only CryptoSavingsTracker/Services/AssetBalanceAccountingModeResolver.swift \
  CryptoSavingsTrackerTests/AssetBalanceAccountingModeResolverTests.swift \
  -m "feat: classify asset balance accounting modes"
git show --stat --oneline HEAD
```

---

### Task 3: Plan Automatic and User-Decided Settlements

**Files:**
- Create: `ios/CryptoSavingsTracker/Services/GoalCompletionSettlementPlanner.swift`
- Create: `ios/CryptoSavingsTrackerTests/GoalCompletionSettlementPlannerTests.swift`

**Interfaces:**
- Consumes: `AssetBalanceAccountingMode` from Task 1.
- Produces: `GoalCompletionSettlementOrigin`, `GoalCompletionAllocationInput`, `GoalCompletionAllocationFingerprint`, `GoalCompletionSettlementItem`, `GoalCompletionSettlementPlan`, `GoalCompletionSettlementDecision`, `GoalCompletionCurrencyAmount`, `GoalCompletionSettlementPlanner.makePlan(goalID:origin:allocations:)`, and `GoalCompletionSettlementPlanner.resolve(plan:decisions:)`.

- [ ] **Step 1: Write planner tests for new and legacy behavior**

Create `GoalCompletionSettlementPlannerTests.swift` with helpers that build inputs, then assert this matrix:

```swift
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
        #expect(plan.items.first { $0.input.accountingMode == .onChain }?.recommendedSettlement == .balanceAlreadyDecreased)
        #expect(plan.items.first { $0.input.accountingMode == .mixed }?.recommendedSettlement == nil)
    }

    @Test("release summary is grouped by asset currency")
    func releaseSummaryGroupsCurrencies() throws {
        let first = input(currency: "USDT", amount: 20, mode: .mixed)
        let second = input(currency: "USDT", amount: 15, mode: .mixed)
        let btc = input(currency: "BTC", amount: 0.1, mode: .mixed)
        let plan = planner.makePlan(goalID: UUID(), origin: .newCompletion, allocations: [first, second, btc])
        let decisions = [first, second, btc].map {
            GoalCompletionSettlementDecision(allocationID: $0.allocationID, settlement: .balanceAlreadyDecreased)
        }
        #expect(try planner.releaseSummary(plan: plan, decisions: decisions) == [
            GoalCompletionCurrencyAmount(currency: "BTC", amount: 0.1),
            GoalCompletionCurrencyAmount(currency: "USDT", amount: 35)
        ])
    }

    private func input(
        currency: String,
        amount: Double,
        mode: AssetBalanceAccountingMode
    ) -> GoalCompletionAllocationInput {
        GoalCompletionAllocationInput(
            allocationID: UUID(), assetID: UUID(), assetCurrency: currency,
            amount: amount, accountingMode: mode, bestKnownBalance: nil,
            balanceCapturedAt: nil
        )
    }
}
```

- [ ] **Step 2: Run the planner tests and verify failure**

Run the Task 1 test command with `-only-testing:CryptoSavingsTrackerTests/GoalCompletionSettlementPlannerTests`.

Expected: FAIL with unresolved planner types.

- [ ] **Step 3: Implement deterministic planning and resolution**

Use these exact rules in `GoalCompletionSettlementPlanner.swift`, beginning with `import Foundation`:

```swift
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
            case .manual: recommendation = .keepAsSpent
            case .onChain: recommendation = .balanceAlreadyDecreased
            case .mixed: recommendation = nil
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
```

The sort and fingerprint intentionally exclude best-known balances, because cache refreshes are display evidence and must not invalidate an otherwise unchanged settlement plan.

- [ ] **Step 4: Run planner, resolver, and codec tests**

Run all three focused suites from Tasks 1-3 in one `xcodebuild` command.

Expected: PASS.

- [ ] **Step 5: Commit the planner**

```bash
git add CryptoSavingsTracker/Services/GoalCompletionSettlementPlanner.swift \
  CryptoSavingsTrackerTests/GoalCompletionSettlementPlannerTests.swift
git commit --only CryptoSavingsTracker/Services/GoalCompletionSettlementPlanner.swift \
  CryptoSavingsTrackerTests/GoalCompletionSettlementPlannerTests.swift \
  -m "feat: plan finished allocation settlements"
git show --stat --oneline HEAD
```

---

### Task 4: Apply Settlements Atomically

**Files:**
- Create: `ios/CryptoSavingsTracker/Services/GoalCompletionSettlementService.swift`
- Modify: `ios/CryptoSavingsTracker/Services/GoalLifecycleService.swift`
- Create: `ios/CryptoSavingsTrackerTests/GoalCompletionSettlementServiceTests.swift`
- Modify: `ios/CryptoSavingsTrackerTests/GoalLifecycleServiceTests.swift`

**Interfaces:**
- Consumes: Task 3 plans/decisions, `ModelContext`, `AllocationHistory`, `ExecutionTrackingService`, and `NotificationManager`.
- Produces: `GoalCompletionSettlementCommand`, `GoalCompletionSettlementService.prepareNewCompletion(for:)`, `prepareLegacyReview(for:)`, `apply(_:at:)`, `applyBatch(_:at:)`, `GoalLifecycleService.prepareFinishGoal(_:)`, and throwing `GoalLifecycleService.finishGoal(_:plan:decisions:at:)`.

- [ ] **Step 1: Write settlement service tests before production code**

Create `GoalCompletionSettlementServiceTests.swift`. Build fixtures with `TestContainer`, direct `AssetAllocation` relationships, and explicit manual transactions/wallet metadata. Cover these named tests:

```swift
@Test("manual completion snapshots and retains allocation")
@Test("on-chain completion releases allocation and writes one zero history row")
@Test("mixed completion applies the explicit choice")
@Test("legacy review requires choices for every allocation across the goal")
@Test("batch legacy review saves all reviewed goals once")
@Test("allocation change after planning rejects without mutation")
@Test("second apply returns the existing snapshot without duplicate history")
@Test("save failure rolls lifecycle snapshot allocations history and execution tracking back")
```

Use an injected persistence seam in the batch test:

```swift
var saveCount = 0
let service = GoalCompletionSettlementService(
    modelContext: context,
    notificationManager: notificationManager,
    save: {
        saveCount += 1
        try context.save()
    },
    rollback: { context.rollback() }
)
```

Use a failing seam in the rollback test:

```swift
enum ForcedSaveFailure: Error { case expected }
let service = GoalCompletionSettlementService(
    modelContext: context,
    notificationManager: notificationManager,
    save: { throw ForcedSaveFailure.expected },
    rollback: { context.rollback() }
)
```

Record baseline `AllocationHistory` count before applying, because fixture allocation creation may already create history.

- [ ] **Step 2: Run the service tests and verify failure**

Run the Task 1 test command with `-only-testing:CryptoSavingsTrackerTests/GoalCompletionSettlementServiceTests`.

Expected: FAIL because `GoalCompletionSettlementService` and `GoalCompletionSettlementCommand` do not exist.

- [ ] **Step 3: Implement preparation without network access**

In `GoalCompletionSettlementService.swift`, define:

```swift
struct GoalCompletionSettlementCommand: Sendable {
    let plan: GoalCompletionSettlementPlan
    let decisions: [GoalCompletionSettlementDecision]
}

enum GoalCompletionSettlementError: Error, Equatable {
    case invalidGoalState(UUID)
    case alreadySettled(UUID)
    case goalNotFound(UUID)
    case missingAsset(UUID)
    case allocationsChanged(UUID)
    case duplicateGoal(UUID)
}

extension GoalCompletionSettlementError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidGoalState:
            return "This goal can no longer be finished from its current state."
        case .alreadySettled:
            return "This goal has already been settled."
        case .goalNotFound:
            return "This goal is no longer available."
        case .missingAsset:
            return "One of the allocated assets is no longer available."
        case .allocationsChanged:
            return "Allocations changed while this review was open. Review the updated amounts."
        case .duplicateGoal:
            return "The same goal was included in this settlement more than once."
        }
    }
}

typealias GoalCompletionSave = @MainActor () throws -> Void
typealias GoalCompletionRollback = @MainActor () -> Void

@MainActor
protocol GoalCompletionSettlementServicing {
    func prepareNewCompletion(for goal: Goal) throws -> GoalCompletionSettlementPlan
    func prepareLegacyReview(for goal: Goal) throws -> GoalCompletionSettlementPlan
    func apply(
        _ command: GoalCompletionSettlementCommand,
        at timestamp: Date = Date()
    ) async throws -> GoalCompletionSnapshot
    func applyBatch(
        _ commands: [GoalCompletionSettlementCommand],
        at timestamp: Date = Date()
    ) async throws -> [GoalCompletionSnapshot]
}
```

Make `GoalCompletionSettlementService` conform to this protocol. Its initializer is exactly `init(modelContext: ModelContext, notificationManager: NotificationManager = .shared, save: GoalCompletionSave? = nil, rollback: GoalCompletionRollback? = nil)`. Default `save` calls `modelContext.save()` and default `rollback` calls `modelContext.rollback()`.

`prepareNewCompletion(for:)` accepts only `.active` goals without snapshot data. `prepareLegacyReview(for:)` accepts only `.finished` goals without snapshot data. Both convert every positive current `AssetAllocation` into `GoalCompletionAllocationInput` using the resolver. Do not fetch a wallet or exchange rate.

Use this evidence rule instead of treating an unavailable wallet cache as a real zero balance:

```swift
private func bestKnownBalanceEvidence(
    for asset: Asset,
    mode: AssetBalanceAccountingMode
) -> (balance: Double?, capturedAt: Date?) {
    guard mode != .manual else { return (asset.manualBalance, Date()) }
    guard
        let chainID = asset.chainId,
        let address = asset.address,
        !chainID.isEmpty,
        !address.isEmpty
    else { return (nil, nil) }
    let key = BalanceCacheManager.balanceCacheKey(
        chainId: chainID,
        address: address,
        symbol: asset.currency
    )
    guard let cachedOnChain = BalanceCacheManager.shared.getFallbackBalance(for: key) else {
        return (nil, nil)
    }
    return (
        asset.manualBalance + cachedOnChain,
        BalanceCacheManager.shared.getLastBalanceUpdate(for: key)
    )
}
```

Copy both tuple fields into `GoalCompletionAllocationInput`. A stale cache remains valid best-known evidence and does not block settlement. The fingerprint still excludes this optional evidence.

- [ ] **Step 4: Implement one-save batch mutation with rollback**

Implement `applyBatch` in this order:

1. Reject duplicate goal IDs.
2. Decode and return an existing snapshot for already-settled commands without mutating it.
3. Re-run preparation for every unresolved command and compare fingerprints before changing any model.
4. Resolve all decisions before changing any model.
5. Build every snapshot before changing any model.
6. Attach snapshot data, retain keep-as-spent rows, delete release rows, and insert one zero `AllocationHistory` per released row.
7. For new completion only, call `goal.markFinished(at:)`.
8. Remove each newly finished goal ID from the active `MonthlyExecutionRecord.trackedGoalIds` without calling `save`.
9. Call `goal.clearRetiredReminderState()` within the same commit.
10. Call the injected `save` closure exactly once.
11. On any error after mutation starts, call `rollback` and rethrow.
12. After save succeeds, cancel external notifications best-effort and publish `.goalDeleted`, `.goalUpdated`, and `.sharedGoalDataDidChange`.

Publish the shared-data notification with `object: nil` and `userInfo: ["affectedGoalIDs": goalIDs, "reason": "assetMutation"]` so the existing Family Sharing projection observer receives the same contract as allocation mutations. Do not publish any of these notifications on rollback or an idempotent no-op.

When deleting an allocation, perform all three actions before save:

```swift
asset.allocations?.removeAll { $0.id == allocation.id }
goal.allocations?.removeAll { $0.id == allocation.id }
modelContext.insert(
    AllocationHistory(asset: asset, goal: goal, amount: 0, timestamp: timestamp)
)
modelContext.delete(allocation)
```

For new snapshots use `goalCompletedAt == snapshotCreatedAt == timestamp` and `.completionTime`. For legacy snapshots use `goal.lifecycleStatusChangedAt ?? timestamp` as `goalCompletedAt`, `timestamp` as `snapshotCreatedAt`, and `.reviewTime`. Never label the review-time balance as completion-time evidence.

`apply(_ command:)` delegates to `applyBatch([command])` and returns the single snapshot. If the snapshot already exists, return its decoded value and do not save, post, or append history.

- [ ] **Step 5: Replace the old non-throwing Finish API**

In `GoalLifecycleService.swift`, remove the old `finishGoal(_ goal:at:)` body and expose:

```swift
func prepareFinishGoal(_ goal: Goal) throws -> GoalCompletionSettlementPlan {
    try GoalCompletionSettlementService(modelContext: modelContext).prepareNewCompletion(for: goal)
}

func finishGoal(
    _ goal: Goal,
    plan: GoalCompletionSettlementPlan,
    decisions: [GoalCompletionSettlementDecision],
    at timestamp: Date = Date()
) async throws -> GoalCompletionSnapshot {
    try await GoalCompletionSettlementService(
        modelContext: modelContext,
        notificationManager: notificationManager
    ).apply(
        GoalCompletionSettlementCommand(plan: plan, decisions: decisions),
        at: timestamp
    )
}
```

Keep cancel/delete semantics unchanged in this task. Update `GoalLifecycleServiceTests.finishGoalClearsReminderFields` to prepare and apply a plan with `try await`; also assert a snapshot exists and reminder cancellation occurs after the successful save.

To keep the app target compilable until Task 5 updates all three view call sites, retain this temporary safe wrapper in Task 4:

```swift
func finishGoal(_ goal: Goal, at timestamp: Date = Date()) async {
    do {
        let plan = try prepareFinishGoal(goal)
        guard plan.unresolvedAllocationIDs.isEmpty else { return }
        _ = try await finishGoal(goal, plan: plan, decisions: [], at: timestamp)
    } catch {
        AppLog.error("Could not finish goal: \(error)", category: .swiftData)
    }
}
```

It never mutates a mixed goal. Delete this wrapper in Task 5 after the last direct view call is replaced.

- [ ] **Step 6: Run settlement and lifecycle suites**

Run:

```bash
xcodebuild -scheme CryptoSavingsTrackerTests -destination 'platform=macOS' test \
  -only-testing:CryptoSavingsTrackerTests/GoalCompletionSettlementServiceTests \
  -only-testing:CryptoSavingsTrackerTests/GoalLifecycleServiceTests \
  -only-testing:CryptoSavingsTrackerTests/AllocationHistoryTests \
  -derivedDataPath ./DerivedDataCodex \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM=''
```

Expected: PASS, including one-save, rollback, idempotency, and history assertions.

- [ ] **Step 7: Commit the atomic service**

```bash
git add CryptoSavingsTracker/Services/GoalCompletionSettlementService.swift \
  CryptoSavingsTracker/Services/GoalLifecycleService.swift \
  CryptoSavingsTrackerTests/GoalCompletionSettlementServiceTests.swift \
  CryptoSavingsTrackerTests/GoalLifecycleServiceTests.swift
git commit --only CryptoSavingsTracker/Services/GoalCompletionSettlementService.swift \
  CryptoSavingsTracker/Services/GoalLifecycleService.swift \
  CryptoSavingsTrackerTests/GoalCompletionSettlementServiceTests.swift \
  CryptoSavingsTrackerTests/GoalLifecycleServiceTests.swift \
  -m "feat: settle finished allocations atomically"
git show --stat --oneline HEAD
```

---

### Task 5: Route Every Finish Entry Through One Coordinator

**Files:**
- Create: `ios/CryptoSavingsTracker/ViewModels/GoalCompletionFlowCoordinator.swift`
- Create: `ios/CryptoSavingsTracker/Views/GoalCompletionSettlementSheet.swift`
- Create: `ios/CryptoSavingsTracker/Views/GoalCompletionFlowModifier.swift`
- Modify: `ios/CryptoSavingsTracker/Views/GoalDetailView.swift`
- Modify: `ios/CryptoSavingsTracker/Views/GoalsListView.swift`
- Modify: `ios/CryptoSavingsTracker/Views/Goals/GoalsListContainer.swift`
- Create: `ios/CryptoSavingsTrackerTests/GoalCompletionFlowCoordinatorTests.swift`

**Interfaces:**
- Consumes: Task 4 lifecycle preparation/application APIs.
- Produces: `GoalCompletionFlowCoordinator.start(goal:prepare:apply:)`, `choose(allocationID:settlement:)`, `apply(using:)`, and `View.goalCompletionFlow(request:onFinished:)`.

- [ ] **Step 1: Write coordinator state-machine tests**

Create tests with injected prepare/apply closures for these transitions:

```swift
@Test("automatic plan applies without presenting a sheet")
@Test("mixed plan presents and disables Apply until every decision exists")
@Test("apply error keeps the goal active and exposes a retryable message")
@Test("changed allocations error clears the stale plan before re-preparing")
```

Use this public state contract:

```swift
enum GoalCompletionFlowPhase: Equatable {
    case idle
    case deciding
    case applying
    case failed(String)
}

@MainActor
protocol GoalCompletionFlowCoordinating: AnyObject {
    var phase: GoalCompletionFlowPhase { get }
    var goal: Goal? { get }
    var plan: GoalCompletionSettlementPlan? { get }
    var decisions: [UUID: FinishedAllocationSettlement] { get }
    var isDecisionSheetPresented: Bool { get }
    var canApply: Bool { get }

    func start(
        goal: Goal,
        prepare: GoalCompletionPrepare,
        apply: GoalCompletionApply
    ) async
    func choose(allocationID: UUID, settlement: FinishedAllocationSettlement)
    func apply(using apply: GoalCompletionApply) async
    func cancel()
}
```

- [ ] **Step 2: Run coordinator tests and verify failure**

Run the Task 1 test command with `-only-testing:CryptoSavingsTrackerTests/GoalCompletionFlowCoordinatorTests`.

Expected: FAIL because the coordinator is missing.

- [ ] **Step 3: Implement the coordinator with injectable closures**

Define closure types so tests do not need a real `ModelContext`:

```swift
typealias GoalCompletionPrepare = @MainActor (Goal) throws -> GoalCompletionSettlementPlan
typealias GoalCompletionApply = @MainActor (
    Goal,
    GoalCompletionSettlementPlan,
    [GoalCompletionSettlementDecision]
) async throws -> GoalCompletionSnapshot
```

Make `GoalCompletionFlowCoordinator` an `@Observable` final class conforming to `GoalCompletionFlowCoordinating`. `start` prepares the plan. If unresolved IDs are empty, it immediately calls Apply. Otherwise it enters `.deciding`. `choose` records one choice by allocation ID. `canApply` is true only when the plan's unresolved ID set equals the decisions key set. An allocation-change error clears the stale plan and re-runs preparation; other errors enter `.failed(error.localizedDescription)` without mutating the goal.

- [ ] **Step 4: Build the reusable decision sheet and modifier**

`GoalCompletionSettlementSheet` must:

- Show only unresolved mixed entries as controls for new completion.
- Present `Balance already decreased` and `Keep as spent` as the two choices.
- Show automatic manual/on-chain items as read-only summary rows when the goal also has mixed entries.
- Show release summaries grouped by currency using `planner.releaseSummary`.
- Disable Apply until `coordinator.canApply` is true.
- Use accessibility IDs `goalCompletionSettlementSheet`, `settlementChoice-<allocation UUID>`, and `applyGoalCompletionSettlement`.

`GoalCompletionFlowModifier` owns the coordinator and observes a `Binding<Goal?>`. It builds a `GoalLifecycleService` from the environment `modelContext`, calls the coordinator when the binding receives a goal, presents the sheet, shows a retryable error alert, clears the binding on success/cancel, and invokes `onFinished` only after persistence succeeds.

- [ ] **Step 5: Replace all three direct Finish calls and update copy**

In each host add:

```swift
@State private var goalPendingCompletion: Goal?
```

Change Finish buttons to:

```swift
Button("Finish Goal") {
    goalPendingCompletion = goal
}
```

Attach the modifier once to each host root:

```swift
.goalCompletionFlow(request: $goalPendingCompletion) { finishedGoal in
    NotificationCenter.default.post(name: .goalProgressRefreshed, object: finishedGoal)
}
```

In `GoalDetailView`, move `navigationTelemetryTracker.flowCompleted(journeyID: NavigationJourney.destructiveDeleteConfirmation, result: "finish_goal")` into this success closure. Replace the old dialog explanation with: `Finish records how this goal was funded. Wallet-tracked balances are released automatically; mixed balances may need one choice.`

Verify no direct call remains:

```bash
rg -n "finishGoal\(" CryptoSavingsTracker/Views
```

Expected: only the reusable coordinator/modifier integration, with no direct `GoalLifecycleService(modelContext: modelContext).finishGoal(goal)` call sites.

Delete the temporary no-decision `finishGoal(_ goal:at:)` wrapper added in Task 4. The throwing plan-and-decisions overload remains the only lifecycle mutation API.

- [ ] **Step 6: Run coordinator and lifecycle tests, then compile iOS**

Run the focused coordinator, settlement service, and lifecycle suites. Then run:

```bash
xcodebuild -scheme CryptoSavingsTracker -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ./DerivedDataCodex build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM=''
```

Expected: tests PASS and build ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit the unified finish flow**

```bash
git add CryptoSavingsTracker/ViewModels/GoalCompletionFlowCoordinator.swift \
  CryptoSavingsTracker/Views/GoalCompletionSettlementSheet.swift \
  CryptoSavingsTracker/Views/GoalCompletionFlowModifier.swift \
  CryptoSavingsTracker/Views/GoalDetailView.swift \
  CryptoSavingsTracker/Views/GoalsListView.swift \
  CryptoSavingsTracker/Views/Goals/GoalsListContainer.swift \
  CryptoSavingsTrackerTests/GoalCompletionFlowCoordinatorTests.swift
git commit --only CryptoSavingsTracker/ViewModels/GoalCompletionFlowCoordinator.swift \
  CryptoSavingsTracker/Views/GoalCompletionSettlementSheet.swift \
  CryptoSavingsTracker/Views/GoalCompletionFlowModifier.swift \
  CryptoSavingsTracker/Views/GoalDetailView.swift \
  CryptoSavingsTracker/Views/GoalsListView.swift \
  CryptoSavingsTracker/Views/Goals/GoalsListContainer.swift \
  CryptoSavingsTrackerTests/GoalCompletionFlowCoordinatorTests.swift \
  -m "feat: add source-aware goal completion flow"
git show --stat --oneline HEAD
```

---

### Task 6: Present Finished Funding From the Snapshot

**Files:**
- Create: `ios/CryptoSavingsTracker/Views/FinishedGoalFundingSection.swift`
- Modify: `ios/CryptoSavingsTracker/Views/GoalDetailView.swift`
- Create: `ios/CryptoSavingsTrackerTests/FinishedGoalFundingPresentationTests.swift`

**Interfaces:**
- Consumes: `Goal.completionSnapshot` and immutable snapshot entries.
- Produces: `FinishedGoalFundingContent`, `FinishedGoalFundingPresentation`, `FinishedGoalFundingPresentation.make(snapshot:)`, and `FinishedGoalFundingSection`.

- [ ] **Step 1: Write pure presentation tests**

Cover these exact outputs:

```swift
@Test("released allocation remains visible as balance already decreased")
@Test("retained allocation is labeled reserved as spent")
@Test("legacy finished goal without snapshot is labeled pending review")
@Test("presentation uses snapshot amount instead of current asset balance")
```

The row contract is:

```swift
struct FinishedGoalFundingPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: UUID
        let assetCurrency: String
        let amount: Double
        let settlementTitle: String
    }
    let completedAt: Date
    let rows: [Row]

    static func make(snapshot: GoalCompletionSnapshot) -> Self {
        Self(
            completedAt: snapshot.goalCompletedAt,
            rows: snapshot.entries.map {
                Row(
                    id: $0.allocationID,
                    assetCurrency: $0.assetCurrency,
                    amount: $0.amount,
                    settlementTitle: $0.settlement == .keepAsSpent
                        ? "Reserved as spent"
                        : "Balance already decreased"
                )
            }
        )
    }
}

enum FinishedGoalFundingContent: Equatable {
    case pendingReview
    case snapshot(FinishedGoalFundingPresentation)
}
```

Expected titles are exactly `Reserved as spent` and `Balance already decreased`.

- [ ] **Step 2: Run the presentation tests and verify failure**

Run the Task 1 command with `-only-testing:CryptoSavingsTrackerTests/FinishedGoalFundingPresentationTests`.

Expected: FAIL because the presentation type is missing.

- [ ] **Step 3: Implement the snapshot-backed section**

Create `FinishedGoalFundingSection.swift` with the presentation mapper above and a SwiftUI section that accepts `FinishedGoalFundingContent`. The view renders raw `amount` plus `assetCurrency`, the settlement title, and completion date. It never reads `Asset.currentAmount`, exchange rates, current allocations, or wallet freshness.

For finished goals in `GoalDetailView`:

- Replace the live `Current`, `Suggested deposit`, and `Refresh balances` rows with `Status: Finished` and the snapshot completion date.
- Replace the live Assets section with `FinishedGoalFundingSection` when a snapshot decodes.
- When snapshot data is absent, show `Funding history pending review` and direct the user to review the relevant asset allocation; do not manufacture a completion-time balance.
- Leave active-goal summary and asset behavior unchanged.

- [ ] **Step 4: Run presentation tests and compile iOS**

Run the presentation and snapshot tests, then the iOS build command from Task 5.

Expected: PASS and `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit historical presentation**

```bash
git add CryptoSavingsTracker/Views/FinishedGoalFundingSection.swift \
  CryptoSavingsTracker/Views/GoalDetailView.swift \
  CryptoSavingsTrackerTests/FinishedGoalFundingPresentationTests.swift
git commit --only CryptoSavingsTracker/Views/FinishedGoalFundingSection.swift \
  CryptoSavingsTracker/Views/GoalDetailView.swift \
  CryptoSavingsTrackerTests/FinishedGoalFundingPresentationTests.swift \
  -m "feat: show immutable finished goal funding"
git show --stat --oneline HEAD
```

---

### Task 7: Add Whole-Goal Legacy Review to the Allocation Editor

**Files:**
- Modify: `ios/CryptoSavingsTracker/Views/AssetAllocationEditorPolicy.swift`
- Modify: `ios/CryptoSavingsTracker/Views/AssetSharingView.swift`
- Modify: `ios/CryptoSavingsTracker/Views/Components/SimplePieChart.swift`
- Modify: `ios/CryptoSavingsTracker/Views/AssetSharingViewPreview.swift`
- Create: `ios/CryptoSavingsTracker/ViewModels/LegacyFinishedAllocationReviewCoordinator.swift`
- Create: `ios/CryptoSavingsTracker/Views/LegacyFinishedAllocationReviewSheet.swift`
- Modify: `ios/CryptoSavingsTrackerTests/AssetAllocationEditorPolicyTests.swift`
- Create: `ios/CryptoSavingsTrackerTests/LegacyFinishedAllocationReviewCoordinatorTests.swift`

**Interfaces:**
- Consumes: Task 4 batch apply and snapshot state.
- Produces: `FinishedAllocationEditorState`, `AssetAllocationEditorWarning`, pending/reserved breakdown fields, `LegacyFinishedAllocationReviewCoordinator.load(goals:prepare:)`, `choose(goalID:allocationID:settlement:)`, `apply(using:)`, and `LegacyFinishedAllocationReviewSheet`.

- [ ] **Step 1: Expand editor policy tests before changing UI**

Update `AssetAllocationEditorEntry` fixtures to distinguish:

```swift
enum FinishedAllocationEditorState: Equatable {
    case pendingReview
    case reservedAsSpent
}

enum AssetAllocationEditorWarning: Equatable {
    case none
    case reviewFinishedAllocations
    case reduceActiveAllocations
}
```

Add tests asserting:

```swift
XCTAssertEqual(breakdown.pendingReviewAmount, 4_456, accuracy: 0.0000001)
XCTAssertEqual(breakdown.finishedReservedAmount, 686, accuracy: 0.0000001)
XCTAssertEqual(breakdown.unallocatedAmount, 36.6673, accuracy: 0.0000001)
```

Also assert Save preserves both pending and reserved finished rows unchanged, Clear removes only active IDs, and the warning policy returns `.reviewFinishedAllocations` when pending legacy rows cause the displayed shortfall.

- [ ] **Step 2: Write coordinator tests for safe legacy review**

Create tests for:

```swift
@Test("loading from one asset prepares every allocation of the affected goal")
@Test("Later clears presentation without calling apply")
@Test("Apply is disabled until every legacy allocation has a choice")
@Test("Apply sends all reviewed goals in one batch command")
@Test("successful final review cannot be reopened because snapshots now exist")
```

Use this decision key and injected function contract:

```swift
struct LegacyFinishedAllocationDecisionKey: Hashable, Sendable {
    let goalID: UUID
    let allocationID: UUID
}

typealias LegacyReviewPrepare = @MainActor (Goal) throws -> GoalCompletionSettlementPlan
typealias LegacyReviewApply = @MainActor (
    [GoalCompletionSettlementCommand]
) async throws -> [GoalCompletionSnapshot]

@MainActor
protocol LegacyFinishedAllocationReviewCoordinating: AnyObject {
    var plansByGoalID: [UUID: GoalCompletionSettlementPlan] { get }
    var decisions: [LegacyFinishedAllocationDecisionKey: FinishedAllocationSettlement] { get }
    var isPresented: Bool { get }
    var errorMessage: String? { get }
    var canApply: Bool { get }

    func load(goals: [Goal], prepare: LegacyReviewPrepare) throws
    func choose(
        goalID: UUID,
        allocationID: UUID,
        settlement: FinishedAllocationSettlement
    )
    func later()
    func apply(using applyBatch: LegacyReviewApply) async throws
}
```

Make `LegacyFinishedAllocationReviewCoordinator` an `@Observable` final class conforming to this protocol. It stores plans by goal ID and decisions by `LegacyFinishedAllocationDecisionKey`. It must invoke the injected batch apply closure once for the entire sheet.

- [ ] **Step 3: Run policy and coordinator tests and verify failure**

Run both focused suites.

Expected: FAIL because the new breakdown fields, warning state, and legacy coordinator are absent.

- [ ] **Step 4: Implement pending-versus-reserved editor policy**

Add `finishedState: FinishedAllocationEditorState?` to `AssetAllocationEditorEntry`. Split `AssetAllocationEditorBreakdown` into active, pending review, reserved as spent, and unallocated amounts/percentages. Preserve every finished entry in `amountsForSave` regardless of finished state.

Map a finished allocation in `AssetSharingView` as follows:

```swift
let finishedState: FinishedAllocationEditorState?
if goal.lifecycleStatus != .finished {
    finishedState = nil
} else if goal.completionSnapshotData == nil {
    finishedState = .pendingReview
} else if goal.completionSnapshot?.entries.contains(where: {
    $0.assetID == asset.id && $0.settlement == .keepAsSpent
}) == true {
    finishedState = .reservedAsSpent
} else {
    finishedState = nil
}
```

Do not offer review when a snapshot already exists. A settled-and-released row should not exist in current allocations; if corrupted data produces one, show a non-actionable save error instead of reopening settlement.

- [ ] **Step 5: Implement whole-goal review and bottom sections**

`LegacyFinishedAllocationReviewCoordinator.load` receives the pending goals discovered from the current asset, but calls `prepareLegacyReview(for:)` on each goal so every allocation across every asset appears in the sheet. Choices start empty. Show accounting-mode recommendations without preselecting them. `Later` dismisses and clears local decisions only.

`LegacyFinishedAllocationReviewSheet` groups rows by goal and asset currency, shows the two settlement choices, groups the release summary by currency, and uses accessibility IDs `legacyFinishedAllocationReviewSheet`, `legacySettlementChoice-<allocation UUID>`, `applyLegacyFinishedAllocationReview`, and `laterLegacyFinishedAllocationReview`.

In `AssetSharingView`, keep both sections at the bottom in this order:

1. `Pending review` with the affected total and `Review finished allocations` CTA.
2. `Reserved as spent` with immutable read-only rows.

If over-allocation includes pending review amounts, replace `Please reduce allocations` with `Finished allocations need review before the available balance can be calculated correctly.` Leave the active-allocation warning for cases without pending legacy rows.

Update `SimplePieChart` to accept separate `pendingReviewPercentage` and `finishedReservedPercentage`. Update previews to cover active-only, pending-review, and reserved-as-spent states using realistic values from the reported `5,873.6673 USDT` example.

- [ ] **Step 6: Run editor/review suites and all settlement unit tests**

Run:

```bash
xcodebuild -scheme CryptoSavingsTrackerTests -destination 'platform=macOS' test \
  -only-testing:CryptoSavingsTrackerTests/AssetAllocationEditorPolicyTests \
  -only-testing:CryptoSavingsTrackerTests/LegacyFinishedAllocationReviewCoordinatorTests \
  -only-testing:CryptoSavingsTrackerTests/GoalCompletionSettlementServiceTests \
  -only-testing:CryptoSavingsTrackerTests/GoalCompletionSettlementPlannerTests \
  -derivedDataPath ./DerivedDataCodex \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM=''
```

Expected: PASS.

- [ ] **Step 7: Compile iOS and inspect the three preview states**

Run the iOS build command from Task 5. In Xcode previews, verify pending review appears above reserved as spent, long goal names wrap, and no amount is clipped at Dynamic Type accessibility sizes.

Expected: `** BUILD SUCCEEDED **` and all preview content remains readable.

- [ ] **Step 8: Commit the legacy review and the accepted prerequisite editor changes**

```bash
git add CryptoSavingsTracker/Views/AssetAllocationEditorPolicy.swift \
  CryptoSavingsTracker/Views/AssetSharingView.swift \
  CryptoSavingsTracker/Views/Components/SimplePieChart.swift \
  CryptoSavingsTracker/Views/AssetSharingViewPreview.swift \
  CryptoSavingsTracker/ViewModels/LegacyFinishedAllocationReviewCoordinator.swift \
  CryptoSavingsTracker/Views/LegacyFinishedAllocationReviewSheet.swift \
  CryptoSavingsTrackerTests/AssetAllocationEditorPolicyTests.swift \
  CryptoSavingsTrackerTests/LegacyFinishedAllocationReviewCoordinatorTests.swift
git commit --only CryptoSavingsTracker/Views/AssetAllocationEditorPolicy.swift \
  CryptoSavingsTracker/Views/AssetSharingView.swift \
  CryptoSavingsTracker/Views/Components/SimplePieChart.swift \
  CryptoSavingsTracker/Views/AssetSharingViewPreview.swift \
  CryptoSavingsTracker/ViewModels/LegacyFinishedAllocationReviewCoordinator.swift \
  CryptoSavingsTracker/Views/LegacyFinishedAllocationReviewSheet.swift \
  CryptoSavingsTrackerTests/AssetAllocationEditorPolicyTests.swift \
  CryptoSavingsTrackerTests/LegacyFinishedAllocationReviewCoordinatorTests.swift \
  -m "feat: review legacy finished allocations"
git show --stat --oneline HEAD
```

This commit intentionally includes the previously accepted read-only finished-allocation editor work already present in these paths; verify the diff before committing so no unrelated changes are absorbed.

---

### Task 8: Add End-to-End Coverage, Migration Gate, and Durable Documentation

**Files:**
- Modify: `ios/CryptoSavingsTracker/Utilities/UITestFlags.swift`
- Modify: `ios/CryptoSavingsTracker/CryptoSavingsTrackerApp.swift`
- Create: `ios/CryptoSavingsTrackerUITests/GoalCompletionSettlementUITests.swift`
- Modify: `docs/CONTRIBUTION_TRACKING_REDESIGN.md`

**Interfaces:**
- Consumes: all production behavior from Tasks 1-7.
- Produces: deterministic `UITEST_SEED_FINISHED_SETTLEMENTS` scenarios and final platform-neutral lifecycle documentation.

- [ ] **Step 1: Add a deterministic UI-test seed flag and fixture**

Add this flag only under `#if DEBUG`:

```swift
static var shouldSeedFinishedSettlements: Bool {
    args.contains("UITEST_SEED_FINISHED_SETTLEMENTS")
}
```

Extend `runUITestSeedIfNeeded` to invoke `seedUITestFinishedSettlements(context:)` when the property is true. The fixture must create:

- `Manual Finish Goal`: manual USD asset and positive manual transaction.
- `On-chain Finish Goal`: wallet-configured USDT asset, no manual transaction.
- `Mixed Finish Goal`: wallet-configured USDT asset with one manual transaction.
- `Legacy Finished Goal`: finished without snapshot, allocated to both USDT and BTC.
- `Legacy Review Host`: active and sharing the legacy USDT asset so UI tests can open its allocation editor.

Insert allocations directly into the in-memory UI-test context so a missing cached wallet balance does not invalidate fixture creation. Save once after the complete graph is built.

- [ ] **Step 2: Write XCUITests for automatic, mixed, and legacy flows**

Create `GoalCompletionSettlementUITests.swift` with launch arguments:

```swift
app.launchArguments = [
    "UITEST_RESET_DATA",
    "UITEST_UI_FLOW",
    "UITEST_SEED_FINISHED_SETTLEMENTS",
    "-ApplePersistenceIgnoreState",
    "YES"
]
```

Implement helpers that open `goalRow-<name>`, tap `Goal actions`, choose `Delete Goal`, then choose `Finish Goal` from the confirmation dialog. Assert:

- Manual and on-chain goals disappear from the active list without `goalCompletionSettlementSheet` appearing.
- Mixed goal shows the sheet, Apply is disabled before selection, release summary shows `USDT`, and applying removes the active row.
- Open `Legacy Review Host`, expand `assetRow-USDT`, tap `manageAllocationButton`, verify `Pending review`, tap `Review finished allocations`, and assert both `USDT` and `BTC` appear.
- Tap `Later`, reopen, and verify the pending state remains.
- Choose every row, Apply Review, and verify the pending section disappears while retained choices appear under `Reserved as spent`.

- [ ] **Step 3: Run the focused UI tests**

Run:

```bash
set -o pipefail
xcodebuild -scheme CryptoSavingsTrackerUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' \
  -only-testing:CryptoSavingsTrackerUITests/GoalCompletionSettlementUITests test \
  -derivedDataPath ./DerivedDataCodex 2>&1 | tail -n 120
```

Expected: all settlement UI tests PASS. If the named simulator is unavailable, run `xcodebuild -scheme CryptoSavingsTrackerUITests -showdestinations`, select an installed iPhone simulator, and record the exact replacement destination in the test evidence; do not change the test logic.

- [ ] **Step 4: Verify lightweight upgrade on a pre-feature store**

Use a dedicated simulator and do not uninstall between builds:

1. Build and install commit `40ec5f6c` in a temporary worktree.
2. Launch it normally, create one active goal and one finished goal with allocations, then terminate the app.
3. Build and install the implementation branch over the same bundle identifier.
4. Launch without reset arguments.
5. Verify the old active goal opens, the old finished goal has `completionSnapshotData == nil`, and its allocation is shown as `Pending review` rather than released.
6. Apply review and relaunch once more; verify the snapshot-backed state survives.

Expected: no store reset, no container initialization failure, no automatic release, and the reviewed snapshot persists. Keep the temporary worktree and simulator data outside commits.

- [ ] **Step 5: Update the lifecycle and edge-case documentation**

In `docs/CONTRIBUTION_TRACKING_REDESIGN.md`, replace the universal Finish row with:

| Action | Allocations | Goal Record | Use Case |
|---|---|---|---|
| **Finish** | Manual retained as spent; on-chain released; mixed chosen once | Immutable completion snapshot | Goal achieved without double-counting |

Add subsections defining the three accounting modes, legacy review safety, raw-quantity snapshot authority, one-save atomicity, and the rule that Android must follow the same contract when implemented. Remove statements that all finished allocations are universally preserved.

- [ ] **Step 6: Run final regression gates**

Run all focused settlement suites plus existing allocation/lifecycle containment tests:

```bash
xcodebuild -scheme CryptoSavingsTrackerTests -destination 'platform=macOS' test \
  -only-testing:CryptoSavingsTrackerTests/GoalCompletionSnapshotTests \
  -only-testing:CryptoSavingsTrackerTests/AssetBalanceAccountingModeResolverTests \
  -only-testing:CryptoSavingsTrackerTests/GoalCompletionSettlementPlannerTests \
  -only-testing:CryptoSavingsTrackerTests/GoalCompletionSettlementServiceTests \
  -only-testing:CryptoSavingsTrackerTests/GoalCompletionFlowCoordinatorTests \
  -only-testing:CryptoSavingsTrackerTests/FinishedGoalFundingPresentationTests \
  -only-testing:CryptoSavingsTrackerTests/AssetAllocationEditorPolicyTests \
  -only-testing:CryptoSavingsTrackerTests/LegacyFinishedAllocationReviewCoordinatorTests \
  -only-testing:CryptoSavingsTrackerTests/GoalLifecycleServiceTests \
  -only-testing:CryptoSavingsTrackerTests/AllocationHistoryTests \
  -only-testing:CryptoSavingsTrackerTests/MVPContainmentContractTests \
  -derivedDataPath ./DerivedDataCodex \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM=''
```

Then run the iOS build from Task 5 and the UI test command from Step 3.

Expected: all tests PASS and iOS build succeeds. Report unrelated baseline failures separately; do not repair unrelated dirty files as part of this feature.

- [ ] **Step 7: Check only feature paths for whitespace and incomplete markers**

```bash
git diff --check -- CryptoSavingsTracker/Models/GoalCompletionSnapshot.swift \
  CryptoSavingsTracker/Models/Goal.swift \
  CryptoSavingsTracker/Services/AssetBalanceAccountingModeResolver.swift \
  CryptoSavingsTracker/Services/GoalCompletionSettlementPlanner.swift \
  CryptoSavingsTracker/Services/GoalCompletionSettlementService.swift \
  CryptoSavingsTracker/Services/GoalLifecycleService.swift \
  CryptoSavingsTracker/ViewModels/GoalCompletionFlowCoordinator.swift \
  CryptoSavingsTracker/ViewModels/LegacyFinishedAllocationReviewCoordinator.swift \
  CryptoSavingsTracker/Views/GoalCompletionSettlementSheet.swift \
  CryptoSavingsTracker/Views/GoalCompletionFlowModifier.swift \
  CryptoSavingsTracker/Views/LegacyFinishedAllocationReviewSheet.swift \
  CryptoSavingsTracker/Views/FinishedGoalFundingSection.swift \
  CryptoSavingsTracker/Views/AssetAllocationEditorPolicy.swift \
  CryptoSavingsTracker/Views/AssetSharingView.swift \
  CryptoSavingsTracker/Views/Components/SimplePieChart.swift \
  CryptoSavingsTracker/Views/GoalDetailView.swift \
  CryptoSavingsTracker/Views/GoalsListView.swift \
  CryptoSavingsTracker/Views/Goals/GoalsListContainer.swift \
  CryptoSavingsTrackerTests CryptoSavingsTrackerUITests
```

Expected: no output.

- [ ] **Step 8: Commit tests and documentation only**

```bash
git add CryptoSavingsTracker/Utilities/UITestFlags.swift \
  CryptoSavingsTracker/CryptoSavingsTrackerApp.swift \
  CryptoSavingsTrackerUITests/GoalCompletionSettlementUITests.swift \
  ../docs/CONTRIBUTION_TRACKING_REDESIGN.md
git commit --only CryptoSavingsTracker/Utilities/UITestFlags.swift \
  CryptoSavingsTracker/CryptoSavingsTrackerApp.swift \
  CryptoSavingsTrackerUITests/GoalCompletionSettlementUITests.swift \
  ../docs/CONTRIBUTION_TRACKING_REDESIGN.md \
  -m "test: verify finished allocation settlement flows"
git show --stat --oneline HEAD
```

Expected: exactly the seed flag, app seed fixture, UI test, and durable documentation are committed.

---

## Completion Checklist

- [ ] Every newly finished goal has one version-1 completion snapshot before allocations change.
- [ ] Manual, on-chain, and mixed classification matches the configured balance source and manual transaction history.
- [ ] Manual and on-chain cases finish without an unnecessary sheet; mixed cannot finish without all choices.
- [ ] Legacy records remain untouched until explicit Apply Review, and Later is mutation-free.
- [ ] Opening review from one asset includes all current allocations of every affected goal.
- [ ] One batch save covers snapshot, release/retain changes, zero history, lifecycle, and active execution removal.
- [ ] Save failure rolls the in-memory graph back and publishes no lifecycle notifications.
- [ ] Re-applying a settled command produces no duplicate release or history.
- [ ] Finished detail reads raw funding from the immutable snapshot, not current wallet balances.
- [ ] Allocation editor separates Pending review, Reserved as spent, active allocations, and true unallocated balance.
- [ ] Existing stores open without reset and legacy allocations are not auto-released.
- [ ] No correction/reopen UI was introduced.
- [ ] Android behavior was not changed, and the documentation preserves the shared platform contract.
