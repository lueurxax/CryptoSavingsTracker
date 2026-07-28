import Foundation
import SwiftData

struct PersistenceMutationRetryState<Action> {
    private(set) var action: Action?
    private(set) var errorMessage: String?

    @discardableResult
    mutating func perform(
        _ action: Action,
        operation: () throws -> Void
    ) -> Bool {
        do {
            try operation()
            self.action = nil
            errorMessage = nil
            return true
        } catch {
            self.action = action
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    mutating func retry(operation: (Action) throws -> Void) -> Bool {
        guard let action else { return true }
        return perform(action) {
            try operation(action)
        }
    }

    mutating func clear() {
        action = nil
        errorMessage = nil
    }
}

struct PersistenceMutationRetryPresentationState<Action> {
    private var retryState = PersistenceMutationRetryState<Action>()
    private(set) var isPresented = false

    var action: Action? {
        retryState.action
    }

    var errorMessage: String? {
        retryState.errorMessage
    }

    @discardableResult
    mutating func perform(
        _ action: Action,
        operation: () throws -> Void
    ) -> Bool {
        let didSucceed = retryState.perform(action, operation: operation)
        isPresented = !didSucceed
        return didSucceed
    }

    /// Records SwiftUI's presentation dismissal without discarding the retry
    /// action. Only explicit cancellation or successful persistence clears it.
    mutating func presentationDismissed() {
        isPresented = false
    }

    @discardableResult
    mutating func retryAfterDismissal(
        operation: (Action) throws -> Void
    ) async -> Bool {
        isPresented = false
        await Task.yield()

        let didSucceed = retryState.retry(operation: operation)
        guard !didSucceed else {
            return true
        }

        // Let the old alert complete its dismissal before asking SwiftUI to
        // present the updated failure.
        await Task.yield()
        isPresented = true
        return false
    }

    mutating func cancel() {
        retryState.clear()
        isPresented = false
    }
}

enum PersistenceOperationTransactionError: LocalizedError {
    case nestedOperationUnsupported
    case durableModelResolutionFailed

    var errorDescription: String? {
        switch self {
        case .nestedOperationUnsupported:
            return "A nested persistence operation on the same model context is not supported."
        case .durableModelResolutionFailed:
            return "The durable model could not be resolved after cancelling its pending shadow."
        }
    }
}

/// Runs one persistence mutation with an operation-owned undo stack.
///
/// A shared `ModelContext` can contain unrelated unsaved edits. Using
/// `ModelContext.rollback()` would discard those edits, so mutations install a
/// temporary `UndoManager`, undo only changes made while the operation is
/// active, then reassert the touched relationship graph from a narrow snapshot.
@MainActor
enum PersistenceOperationTransaction {
    private static var activeContextIdentifiers: Set<ObjectIdentifier> = []

    static func perform<Result>(
        in modelContext: ModelContext,
        saveChanges: () throws -> Void,
        allowingPreexistingChangesTo allowedModels: [any PersistentModel] = [],
        mapSaveError: (Error) -> Error = { $0 },
        restoreTouchedState: () -> Void,
        mutation: () throws -> Result
    ) throws -> Result {
        do {
            try assertNoUnrelatedPendingChanges(
                in: modelContext,
                allowing: allowedModels
            )
        } catch {
            // A pending-insert deletion may have been resolved before the
            // transactional save boundary was entered. If the isolation
            // precondition then rejects an unrelated draft, restore that
            // pending target graph before returning the validation error.
            let previousUndoManager = modelContext.undoManager
            modelContext.undoManager = nil
            restoreTouchedState()
            modelContext.processPendingChanges()
            modelContext.undoManager = previousUndoManager
            throw error
        }

        let contextIdentifier = ObjectIdentifier(modelContext)
        guard activeContextIdentifiers.insert(contextIdentifier).inserted else {
            throw PersistenceOperationTransactionError.nestedOperationUnsupported
        }

        let previousUndoManager = modelContext.undoManager
        defer {
            modelContext.undoManager = previousUndoManager
            activeContextIdentifiers.remove(contextIdentifier)
        }

        let operationUndoManager = UndoManager()
        modelContext.undoManager = operationUndoManager
        var reachedSaveBoundary = false

        do {
            let result = try mutation()
            reachedSaveBoundary = true
            try saveChanges()
            return result
        } catch {
            while operationUndoManager.canUndo {
                operationUndoManager.undo()
            }

            // Snapshot restoration is part of this operation's rollback, not
            // a new user-edit transaction.
            modelContext.undoManager = nil
            restoreTouchedState()
            modelContext.processPendingChanges()

            if reachedSaveBoundary {
                throw mapSaveError(error)
            }
            throw error
        }
    }

    /// A `ModelContext.save()` persists every pending change in the context,
    /// not just the models touched by the current mutation. Reject operations
    /// that would accidentally commit another screen's draft.
    static func assertNoUnrelatedPendingChanges(
        in modelContext: ModelContext,
        allowing allowedModels: [any PersistentModel]
    ) throws {
        let allowedIDs = Set(allowedModels.map(\.persistentModelID))
        let pendingModels =
            modelContext.insertedModelsArray
            + modelContext.changedModelsArray
            + modelContext.deletedModelsArray
        guard pendingModels.allSatisfy({
            allowedIDs.contains($0.persistentModelID)
        }) else {
            throw PersistenceMutationError.validationFailed(
                "Save or discard other edits before continuing."
            )
        }
    }

    /// Cancels pending-insert shadows before an operation-owned undo manager is
    /// installed. SwiftData on iOS 26.5 can crash when a pending insert is
    /// deleted while a newly-created undo stack is active.
    ///
    /// A separate context probes the durable store first. Pending-only models
    /// are cancelled and omitted from the result. If a pending model shadows a
    /// durable row, that row is refetched in `modelContext` and returned for the
    /// ordinary transactional deletion.
    static func resolvePendingInsertDeletions<Model: PersistentModel, StableID: Hashable>(
        _ candidates: [Model],
        in modelContext: ModelContext,
        stableID: (Model) -> StableID,
        fetchByIDs: (ModelContext, [StableID]) throws -> [Model]
    ) throws -> [Model] {
        let insertedModelIDs = Set(modelContext.insertedModelsArray.map(\.persistentModelID))
        let candidateStates = candidates.map {
            (
                model: $0,
                id: stableID($0),
                isPendingInsert: insertedModelIDs.contains($0.persistentModelID)
            )
        }
        let pendingStates = candidateStates.filter { $0.isPendingInsert }
        guard !pendingStates.isEmpty else {
            return candidates
        }

        let pendingStableIDs = pendingStates.map(\.id)
        let durableProbeContext = ModelContext(modelContext.container)
        durableProbeContext.autosaveEnabled = false
        let durableProbeModels = try fetchByIDs(durableProbeContext, pendingStableIDs)
        let durableStableIDs = Set(durableProbeModels.map(stableID))

        let previousUndoManager = modelContext.undoManager
        modelContext.undoManager = nil
        defer {
            modelContext.undoManager = previousUndoManager
        }

        for state in pendingStates {
            modelContext.delete(state.model)
        }
        modelContext.processPendingChanges()

        let durableIDsToResolve = pendingStableIDs.filter { durableStableIDs.contains($0) }
        let resolvedDurableModels = durableIDsToResolve.isEmpty
            ? []
            : try fetchByIDs(modelContext, durableIDsToResolve)
        let resolvedByID = Dictionary(
            uniqueKeysWithValues: resolvedDurableModels.map { (stableID($0), $0) }
        )

        var result: [Model] = []
        result.reserveCapacity(candidates.count)
        for state in candidateStates {
            if !state.isPendingInsert {
                result.append(state.model)
            } else if durableStableIDs.contains(state.id) {
                guard let durableModel = resolvedByID[state.id] else {
                    throw PersistenceOperationTransactionError.durableModelResolutionFailed
                }
                result.append(durableModel)
            }
        }
        return result
    }

    static func discardInserted<Model: PersistentModel>(
        _ models: [Model],
        from modelContext: ModelContext
    ) {
        let insertedIDs = Set(modelContext.insertedModelsArray.map(\.persistentModelID))
        for model in models where insertedIDs.contains(model.persistentModelID) {
            modelContext.delete(model)
        }
    }
}

/// Captures only the relationship graph and scalar allocation state touched by
/// asset, allocation, or transaction mutations.
@MainActor
struct PersistenceAllocationGraphSnapshot {
    private struct AssetState {
        let asset: Asset
        let transactions: [Transaction]?
        let allocations: [AssetAllocation]?
        let allocationHistory: [AllocationHistory]?
    }

    private struct GoalState {
        let goal: Goal
        let allocations: [AssetAllocation]?
        let allocationHistory: [AllocationHistory]?
    }

    private struct TransactionState {
        let transaction: Transaction
        let asset: Asset?
    }

    private struct AllocationState {
        let allocation: AssetAllocation
        let amount: Double
        let lastModifiedDate: Date
        let asset: Asset?
        let goal: Goal?
    }

    private struct HistoryState {
        let history: AllocationHistory
        let amount: Double
        let timestamp: Date
        let createdAt: Date
        let monthLabel: String
        let assetId: UUID?
        let goalId: UUID?
        let sourceTransactionId: UUID?
        let sourcePreviousAmount: Double?
        let asset: Asset?
        let goal: Goal?
    }

    private let assetStates: [AssetState]
    private let goalStates: [GoalState]
    private let transactionStates: [TransactionState]
    private let allocationStates: [AllocationState]
    private let historyStates: [HistoryState]

    var models: [any PersistentModel] {
        assetStates.map(\.asset)
            + goalStates.map(\.goal)
            + transactionStates.map(\.transaction)
            + allocationStates.map(\.allocation)
            + historyStates.map(\.history)
    }

    init(
        assets explicitAssets: [Asset],
        goals explicitGoals: [Goal] = [],
        transactions explicitTransactions: [Transaction] = [],
        allocations explicitAllocations: [AssetAllocation] = [],
        histories explicitHistories: [AllocationHistory] = []
    ) {
        var assetsByID = Dictionary(uniqueKeysWithValues: explicitAssets.map { ($0.id, $0) })
        var goalsByID = Dictionary(uniqueKeysWithValues: explicitGoals.map { ($0.id, $0) })

        for transaction in explicitTransactions {
            if let asset = transaction.asset {
                assetsByID[asset.id] = asset
            }
        }
        for allocation in explicitAllocations {
            if let asset = allocation.asset {
                assetsByID[asset.id] = asset
            }
            if let goal = allocation.goal {
                goalsByID[goal.id] = goal
            }
        }
        for history in explicitHistories {
            if let asset = history.asset {
                assetsByID[asset.id] = asset
            }
            if let goal = history.goal {
                goalsByID[goal.id] = goal
            }
        }

        for asset in explicitAssets {
            for allocation in asset.allocations ?? [] {
                if let goal = allocation.goal {
                    goalsByID[goal.id] = goal
                }
            }
            for history in asset.allocationHistory ?? [] {
                if let goal = history.goal {
                    goalsByID[goal.id] = goal
                }
            }
        }

        for goal in explicitGoals {
            for allocation in goal.allocations ?? [] {
                if let asset = allocation.asset {
                    assetsByID[asset.id] = asset
                }
            }
            for history in goal.allocationHistory ?? [] {
                if let asset = history.asset {
                    assetsByID[asset.id] = asset
                }
            }
        }

        let assets = Array(assetsByID.values)
        let goals = Array(goalsByID.values)
        let explicitAllocationsByAssetID = Dictionary(
            grouping: explicitAllocations.compactMap { allocation in
                allocation.asset.map { ($0.id, allocation) }
            },
            by: \.0
        )
        let explicitAllocationsByGoalID = Dictionary(
            grouping: explicitAllocations.compactMap { allocation in
                allocation.goal.map { ($0.id, allocation) }
            },
            by: \.0
        )
        assetStates = assets.map {
            let supplemental = explicitAllocationsByAssetID[$0.id]?.map(\.1) ?? []
            return AssetState(
                asset: $0,
                transactions: $0.transactions,
                allocations: Self.merging($0.allocations, supplemental),
                allocationHistory: $0.allocationHistory
            )
        }
        goalStates = goals.map {
            let supplemental = explicitAllocationsByGoalID[$0.id]?.map(\.1) ?? []
            return GoalState(
                goal: $0,
                allocations: Self.merging($0.allocations, supplemental),
                allocationHistory: $0.allocationHistory
            )
        }

        var transactionsByID = Dictionary(
            uniqueKeysWithValues: explicitTransactions.map { ($0.id, $0) }
        )
        var allocationsByID: [UUID: AssetAllocation] = [:]
        var historiesByID: [UUID: AllocationHistory] = [:]
        for allocation in explicitAllocations {
            allocationsByID[allocation.id] = allocation
        }
        for history in explicitHistories {
            historiesByID[history.id] = history
        }

        for asset in assets {
            for transaction in asset.transactions ?? [] {
                transactionsByID[transaction.id] = transaction
            }
            for allocation in asset.allocations ?? [] {
                allocationsByID[allocation.id] = allocation
            }
            for history in asset.allocationHistory ?? [] {
                historiesByID[history.id] = history
            }
        }
        for goal in goals {
            for allocation in goal.allocations ?? [] {
                allocationsByID[allocation.id] = allocation
            }
            for history in goal.allocationHistory ?? [] {
                historiesByID[history.id] = history
            }
        }

        transactionStates = transactionsByID.values.map {
            TransactionState(transaction: $0, asset: $0.asset)
        }
        allocationStates = allocationsByID.values.map {
            AllocationState(
                allocation: $0,
                amount: $0.amount,
                lastModifiedDate: $0.lastModifiedDate,
                asset: $0.asset,
                goal: $0.goal
            )
        }
        historyStates = historiesByID.values.map {
            HistoryState(
                history: $0,
                amount: $0.amount,
                timestamp: $0.timestamp,
                createdAt: $0.createdAt,
                monthLabel: $0.monthLabel,
                assetId: $0.assetId,
                goalId: $0.goalId,
                sourceTransactionId: $0.sourceTransactionId,
                sourcePreviousAmount: $0.sourcePreviousAmount,
                asset: $0.asset,
                goal: $0.goal
            )
        }
    }

    private static func merging(
        _ existing: [AssetAllocation]?,
        _ supplemental: [AssetAllocation]
    ) -> [AssetAllocation]? {
        guard existing != nil || !supplemental.isEmpty else { return nil }
        var byID = Dictionary(uniqueKeysWithValues: (existing ?? []).map { ($0.id, $0) })
        for allocation in supplemental {
            byID[allocation.id] = allocation
        }
        return Array(byID.values)
    }

    func restore(in modelContext: ModelContext) {
        func needsReinsertion<Model: PersistentModel>(_ model: Model) -> Bool {
            model.modelContext == nil
                || modelContext.deletedModelsArray.contains {
                    $0.persistentModelID == model.persistentModelID
                }
        }

        // Pending-insert deletion is performed before the operation-owned undo
        // stack is installed. Reinsert those detached roots before restoring
        // the relationship graph.
        for state in assetStates where needsReinsertion(state.asset) {
            modelContext.insert(state.asset)
        }
        for state in goalStates where needsReinsertion(state.goal) {
            modelContext.insert(state.goal)
        }
        modelContext.processPendingChanges()

        for state in transactionStates where needsReinsertion(state.transaction) {
            modelContext.insert(state.transaction)
        }
        for state in allocationStates where needsReinsertion(state.allocation) {
            modelContext.insert(state.allocation)
        }
        for state in historyStates where needsReinsertion(state.history) {
            modelContext.insert(state.history)
        }
        modelContext.processPendingChanges()

        for state in transactionStates {
            state.transaction.asset = state.asset
        }
        for state in allocationStates {
            state.allocation.amount = state.amount
            state.allocation.lastModifiedDate = state.lastModifiedDate
            state.allocation.asset = state.asset
            state.allocation.goal = state.goal
        }
        for state in historyStates {
            state.history.amount = state.amount
            state.history.timestamp = state.timestamp
            state.history.createdAt = state.createdAt
            state.history.monthLabel = state.monthLabel
            state.history.assetId = state.assetId
            state.history.goalId = state.goalId
            state.history.sourceTransactionId = state.sourceTransactionId
            state.history.sourcePreviousAmount = state.sourcePreviousAmount
            state.history.asset = state.asset
            state.history.goal = state.goal
        }
        for state in assetStates {
            state.asset.transactions = state.transactions
            state.asset.allocations = state.allocations
            state.asset.allocationHistory = state.allocationHistory
        }
        for state in goalStates {
            state.goal.allocations = state.allocations
            state.goal.allocationHistory = state.allocationHistory
        }
    }
}
