//
//  PersistenceMutationServices.swift
//  CryptoSavingsTracker
//
//  Created by Codex on 16/03/2026.
//

import CryptoKit
import Foundation
import SwiftData

struct AddressedAssetPersistenceIdentity: Hashable {
    let currency: String
    let chainId: String
    let address: String
}

enum AssetPersistenceIdentityPolicy {
    static func addressedIdentity(
        currency: String,
        address: String?,
        chainId: String?
    ) -> AddressedAssetPersistenceIdentity? {
        let trimmedAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedAddress.isEmpty else { return nil }

        let trimmedChain = chainId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedChain.isEmpty else { return nil }
        let canonicalChain = canonicalChainId(trimmedChain)

        return AddressedAssetPersistenceIdentity(
            currency: canonicalProviderCurrency(
                currency,
                chainId: canonicalChain
            ),
            chainId: canonicalChain,
            address: OnChainIdentifierPolicy.normalizedAddress(
                trimmedAddress,
                forChainIdentifier: canonicalChain
            )
        )
    }

    static func addressedIdentity(for asset: Asset) -> AddressedAssetPersistenceIdentity? {
        addressedIdentity(
            currency: asset.currency,
            address: asset.address,
            chainId: asset.chainId
        )
    }

    static func canonicalChainId(_ chainId: String) -> String {
        let trimmed = chainId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uppercase = trimmed.uppercased()
        let chainService = ChainService.shared
        if let direct = chainService.getChain(by: uppercase) {
            return direct.id
        }
        if let v4Match = chainService.supportedChains.first(where: {
            chainService.getV4ChainName(for: $0.id)?
                .caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return v4Match.id
        }
        switch trimmed.lowercased() {
        case "bitcoin-mainnet": return "BTC"
        case "litecoin-mainnet": return "LTC"
        case "bch-mainnet", "bitcoin-cash-mainnet": return "BCH"
        case "doge-mainnet", "dogecoin-mainnet": return "DOGE"
        case "solana-mainnet": return "SOL"
        default: return uppercase
        }
    }

    static func canonicalProviderCurrency(
        _ currency: String,
        chainId: String?
    ) -> String {
        let normalizedCurrency = currency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let chainId else { return normalizedCurrency }
        let canonicalChain = canonicalChainId(chainId)

        // Polygon renamed its native asset from MATIC to POL, but both symbols
        // intentionally resolve to the same provider-native balance for
        // persisted compatibility. They therefore share one persistence
        // identity and cannot represent independent wallet assets.
        if canonicalChain == "MATIC",
           normalizedCurrency == "MATIC" || normalizedCurrency == "POL" {
            return "POL"
        }
        return normalizedCurrency
    }

    static func canonicalAddress(_ address: String, chainId: String) -> String {
        OnChainIdentifierPolicy.normalizedAddress(
            address.trimmingCharacters(in: .whitespacesAndNewlines),
            forChainIdentifier: canonicalChainId(chainId)
        )
    }

    @MainActor
    static func assertUniqueAddressedIdentity(
        _ identity: AddressedAssetPersistenceIdentity,
        excluding assetID: UUID? = nil,
        in modelContext: ModelContext
    ) throws {
        let assets = try modelContext.fetch(FetchDescriptor<Asset>())
        if assets.contains(where: { candidate in
            candidate.id != assetID && addressedIdentity(for: candidate) == identity
        }) {
            throw PersistenceMutationError.validationFailed(
                "This wallet and currency are already tracked. Use the existing asset instead."
            )
        }
    }
}

@MainActor
final class GoalMutationService: GoalMutationServiceProtocol {
    private let modelContext: ModelContext
    private let notificationManager: NotificationManager
    private let accessGuard: FamilyShareAccessChecking
    private let saveChanges: () throws -> Void
    private let now: () -> Date

    init(
        modelContext: ModelContext,
        notificationManager: NotificationManager? = nil,
        accessGuard: FamilyShareAccessChecking,
        saveChanges: (() throws -> Void)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.notificationManager = notificationManager ?? .shared
        self.accessGuard = accessGuard
        self.saveChanges = saveChanges ?? {
            try modelContext.save()
        }
        self.now = now
    }

    func createGoal(_ goal: Goal) async throws {
        try await persist(goal, insertIfNeeded: true)
        await notificationManager.cancelNotifications(for: goal)
        postSharedGoalDataDidChange(goalIDs: [goal.id])
    }

    func saveGoal(_ goal: Goal) async throws {
        try accessGuard.assertOwnerWritable(goal: goal)
        try await persist(goal, insertIfNeeded: true)
        await notificationManager.cancelNotifications(for: goal)
        postSharedGoalDataDidChange(goalIDs: [goal.id])
    }

    func archiveGoal(_ goal: Goal) async throws {
        try accessGuard.assertOwnerWritable(goal: goal)
        do {
            try await GoalLifecycleService(
                modelContext: modelContext,
                notificationManager: notificationManager,
                saveChanges: saveChanges
            ).deleteGoal(goal)
        } catch let error as PersistenceMutationError {
            throw error
        } catch {
            throw PersistenceMutationError.saveFailed("Unable to archive goal", underlying: error)
        }
    }

    func restoreGoal(_ goal: Goal) async throws {
        try accessGuard.assertOwnerWritable(goal: goal)
        try persistLifecycleMutation(for: goal, operation: "Unable to restore goal") {
            goal.restore()
            clearReminderState(for: goal)
        }
        await notificationManager.cancelNotifications(for: goal)
        postSharedGoalDataDidChange(goalIDs: [goal.id])
    }

    func resumeGoal(_ goal: Goal) async throws {
        try accessGuard.assertOwnerWritable(goal: goal)
        try persistLifecycleMutation(for: goal, operation: "Unable to resume goal") {
            goal.restoreToActive()
            clearReminderState(for: goal)
        }
        await notificationManager.cancelNotifications(for: goal)
        postSharedGoalDataDidChange(goalIDs: [goal.id])
    }

    private func clearReminderState(for goal: Goal) {
        goal.clearRetiredReminderState()
    }

    private func postSharedGoalDataDidChange(goalIDs: [UUID]) {
        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": goalIDs,
                "reason": "goalMutation"
            ]
        )
    }

    private func persist(_ goal: Goal, insertIfNeeded: Bool) async throws {
        let shouldInsert = insertIfNeeded && goal.modelContext == nil
        let snapshot = GoalMutationLifecycleSnapshot(goal: goal)
        try PersistenceOperationTransaction.assertNoUnrelatedPendingChanges(
            in: modelContext,
            allowing: goal.modelContext == nil ? [] : [goal]
        )

        // Goal forms can hand us a managed model that already has unsaved
        // field edits. Installing a fresh UndoManager at that point crashes
        // SwiftData on iOS 26.5 when reminder cleanup creates its first undo
        // snapshot. This mutation only owns reminder cleanup and, for create,
        // one pending insert, so a narrow snapshot is sufficient.
        let previousUndoManager = modelContext.undoManager
        modelContext.undoManager = nil
        defer {
            modelContext.undoManager = previousUndoManager
        }

        do {
            goal.lastModifiedDate = now()
            clearReminderState(for: goal)
            if shouldInsert {
                modelContext.insert(goal)
            }
            try saveChanges()
        } catch {
            if shouldInsert {
                PersistenceOperationTransaction.discardInserted([goal], from: modelContext)
                modelContext.processPendingChanges()
            }
            snapshot.restore(goal)
            throw PersistenceMutationError.saveFailed("Unable to save goal", underlying: error)
        }
    }

    private func saveContext(operation: String) throws {
        do {
            try saveChanges()
        } catch {
            throw PersistenceMutationError.saveFailed(operation, underlying: error)
        }
    }

    private func persistLifecycleMutation(
        for goal: Goal,
        operation: String,
        mutation: () -> Void
    ) throws {
        let snapshot = GoalMutationLifecycleSnapshot(goal: goal)
        try PersistenceOperationTransaction.assertNoUnrelatedPendingChanges(
            in: modelContext,
            allowing: [goal]
        )

        do {
            mutation()
            try saveContext(operation: operation)
        } catch {
            snapshot.restore(goal)
            throw error
        }
    }
}

private struct GoalMutationLifecycleSnapshot {
    private let lifecycleStatusRawValue: String
    private let lifecycleStatusChangedAt: Date?
    private let lastModifiedDate: Date
    private let reminderFrequency: String?
    private let reminderTime: Date?
    private let firstReminderDate: Date?

    init(goal: Goal) {
        lifecycleStatusRawValue = goal.lifecycleStatusRawValue
        lifecycleStatusChangedAt = goal.lifecycleStatusChangedAt
        lastModifiedDate = goal.lastModifiedDate
        reminderFrequency = goal.reminderFrequency
        reminderTime = goal.reminderTime
        firstReminderDate = goal.firstReminderDate
    }

    func restore(_ goal: Goal) {
        goal.lifecycleStatusRawValue = lifecycleStatusRawValue
        goal.lifecycleStatusChangedAt = lifecycleStatusChangedAt
        goal.lastModifiedDate = lastModifiedDate
        goal.reminderFrequency = reminderFrequency
        goal.reminderTime = reminderTime
        goal.firstReminderDate = firstReminderDate
    }
}

@MainActor
final class AssetMutationService: AssetMutationServiceProtocol {
    private let modelContext: ModelContext
    private let allocationService: AllocationService
    private let accessGuard: FamilyShareAccessChecking
    private let saveChanges: () throws -> Void

    init(
        modelContext: ModelContext,
        accessGuard: FamilyShareAccessChecking,
        saveChanges: (() throws -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.accessGuard = accessGuard
        let resolvedSaveChanges = saveChanges ?? {
            try modelContext.save()
        }
        self.saveChanges = resolvedSaveChanges
        self.allocationService = AllocationService(
            modelContext: modelContext,
            saveChanges: resolvedSaveChanges
        )
    }

    @discardableResult
    func createAsset(
        currency: String,
        address: String?,
        chainId: String?,
        goal: Goal
    ) async throws -> Asset {
        try accessGuard.assertOwnerWritable(goal: goal)
        let trimmedAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAddress = !(trimmedAddress ?? "").isEmpty
        let canonicalChainId = chainId.map(AssetPersistenceIdentityPolicy.canonicalChainId)
        let normalizedCurrency = AssetPersistenceIdentityPolicy.canonicalProviderCurrency(
            currency,
            chainId: hasAddress ? canonicalChainId : nil
        )
        let canonicalAddress: String?
        if hasAddress {
            guard let canonicalChainId, !canonicalChainId.isEmpty else {
                throw PersistenceMutationError.validationFailed(
                    "Select a supported blockchain network or leave the address blank for manual tracking."
                )
            }
            do {
                try BalanceRouteResolver.validateTrackedAsset(
                    chainId: canonicalChainId,
                    symbol: normalizedCurrency,
                    chainService: ChainService()
                )
            } catch {
                throw PersistenceMutationError.validationFailed(error.localizedDescription)
            }
            canonicalAddress = AssetPersistenceIdentityPolicy.canonicalAddress(
                trimmedAddress!,
                chainId: canonicalChainId
            )
        } else {
            canonicalAddress = nil
        }

        if let identity = AssetPersistenceIdentityPolicy.addressedIdentity(
            currency: normalizedCurrency,
            address: canonicalAddress,
            chainId: canonicalChainId
        ) {
            do {
                try AssetPersistenceIdentityPolicy.assertUniqueAddressedIdentity(
                    identity,
                    in: modelContext
                )
            } catch let error as PersistenceMutationError {
                throw error
            } catch {
                throw PersistenceMutationError.saveFailed(
                    "Unable to validate asset identity",
                    underlying: error
                )
            }
        }
        let newAsset = Asset(
            currency: normalizedCurrency,
            address: canonicalAddress,
            chainId: hasAddress ? canonicalChainId : nil
        )
        let snapshot = PersistenceAllocationGraphSnapshot(assets: [], goals: [goal])
        var createdAllocation: AssetAllocation?
        var createdHistory: AllocationHistory?
        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: snapshot.models,
            mapSaveError: {
                PersistenceMutationError.saveFailed("Unable to save asset", underlying: $0)
            },
            restoreTouchedState: {
                if let createdHistory {
                    PersistenceOperationTransaction.discardInserted([createdHistory], from: modelContext)
                }
                if let createdAllocation {
                    PersistenceOperationTransaction.discardInserted([createdAllocation], from: modelContext)
                }
                PersistenceOperationTransaction.discardInserted([newAsset], from: modelContext)
                snapshot.restore(in: modelContext)
            }
        ) {
            let allocation = AssetAllocation(asset: newAsset, goal: goal, amount: newAsset.currentAmount)
            let history = AllocationHistory(asset: newAsset, goal: goal, amount: allocation.amountValue)
            createdAllocation = allocation
            createdHistory = history

            modelContext.insert(newAsset)
            modelContext.insert(allocation)
            modelContext.insert(history)

            if !(goal.allocations ?? []).contains(where: { $0.id == allocation.id }) {
                goal.allocations = (goal.allocations ?? []) + [allocation]
            }
            if !(newAsset.allocations ?? []).contains(where: { $0.id == allocation.id }) {
                newAsset.allocations = (newAsset.allocations ?? []) + [allocation]
            }
        }

        postAssetSharedGoalDataDidChange(goalIDs: [goal.id])
        return newAsset
    }

    func allocateAllUnallocated(of asset: Asset, to goal: Goal, bestKnownBalance: Double) throws {
        try accessGuard.assertOwnerWritable(asset: asset)
        try accessGuard.assertOwnerWritable(goal: goal)
        let remaining = max(0, bestKnownBalance - asset.totalAllocatedAmount)
        guard remaining > 0.0000001 else { return }

        var newAllocations: [(goal: Goal, amount: Double)] = []
        newAllocations.reserveCapacity((asset.allocations ?? []).count + 1)

        var goalHandled = false
        for allocation in (asset.allocations ?? []) {
            guard let existingGoal = allocation.goal else { continue }
            if existingGoal.id == goal.id {
                newAllocations.append((goal: goal, amount: allocation.amountValue + remaining))
                goalHandled = true
            } else {
                newAllocations.append((goal: existingGoal, amount: allocation.amountValue))
            }
        }

        if !goalHandled {
            newAllocations.append((goal: goal, amount: remaining))
        }

        do {
            try allocationService.updateAllocations(for: asset, newAllocations: newAllocations)
        } catch {
            throw PersistenceMutationError.saveFailed("Unable to update asset allocations", underlying: error)
        }
    }

    func deleteAsset(_ asset: Asset) throws {
        try accessGuard.assertOwnerWritable(asset: asset)
        try assertAssetsAreNotProtectedByExecutionEvidence([asset])
        let goalIDs = (asset.allocations ?? []).compactMap { $0.goal?.id }
        let snapshot = PersistenceAllocationGraphSnapshot(assets: [asset])
        let assetsToDelete: [Asset]
        do {
            assetsToDelete = try resolveAssetsForDeletion([asset])
        } catch {
            snapshot.restore(in: modelContext)
            throw error
        }
        guard !assetsToDelete.isEmpty else {
            postAssetSharedGoalDataDidChange(goalIDs: goalIDs)
            return
        }

        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: snapshot.models,
            mapSaveError: {
                PersistenceMutationError.saveFailed("Unable to delete asset", underlying: $0)
            },
            restoreTouchedState: { snapshot.restore(in: modelContext) }
        ) {
            for assetToDelete in assetsToDelete {
                modelContext.delete(assetToDelete)
            }
        }
        postAssetSharedGoalDataDidChange(goalIDs: goalIDs)
    }

    func deleteAssets(_ assets: [Asset]) throws {
        for asset in assets {
            try accessGuard.assertOwnerWritable(asset: asset)
        }
        try assertAssetsAreNotProtectedByExecutionEvidence(assets)
        let goalIDs = assets.flatMap { ($0.allocations ?? []).compactMap { $0.goal?.id } }
        let snapshot = PersistenceAllocationGraphSnapshot(assets: assets)
        let assetsToDelete: [Asset]
        do {
            assetsToDelete = try resolveAssetsForDeletion(assets)
        } catch {
            snapshot.restore(in: modelContext)
            throw error
        }
        guard !assetsToDelete.isEmpty else {
            postAssetSharedGoalDataDidChange(goalIDs: goalIDs)
            return
        }

        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: snapshot.models,
            mapSaveError: {
                PersistenceMutationError.saveFailed("Unable to delete assets", underlying: $0)
            },
            restoreTouchedState: { snapshot.restore(in: modelContext) }
        ) {
            for asset in assetsToDelete {
                modelContext.delete(asset)
            }
        }
        postAssetSharedGoalDataDidChange(goalIDs: goalIDs)
    }

    private func postAssetSharedGoalDataDidChange(goalIDs: [UUID]) {
        guard !goalIDs.isEmpty else { return }
        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": goalIDs,
                "reason": "assetMutation"
            ]
        )
    }

    private func resolveAssetsForDeletion(_ assets: [Asset]) throws -> [Asset] {
        try PersistenceOperationTransaction.resolvePendingInsertDeletions(
            assets,
            in: modelContext,
            stableID: \.id
        ) { context, ids in
            let assetIDs = ids
            let descriptor = FetchDescriptor<Asset>(
                predicate: #Predicate<Asset> { candidate in
                    assetIDs.contains(candidate.id)
                }
            )
            return try context.fetch(descriptor)
        }
    }

    private func assertAssetsAreNotProtectedByExecutionEvidence(_ assets: [Asset]) throws {
        guard !assets.isEmpty else { return }
        let now = Date()
        let records = try modelContext.fetch(FetchDescriptor<MonthlyExecutionRecord>())
            .filter { record in
                record.status == .executing
                    || (
                        record.status == .closed
                            && (record.canUndoUntil.map { $0 > now } ?? false)
                    )
            }
        guard !records.isEmpty else { return }

        let protectedAssetIDs = Set(assets.map(\.id))
        let histories = try modelContext.fetch(FetchDescriptor<AllocationHistory>())
            .filter { history in
                history.assetId.map(protectedAssetIDs.contains) ?? false
            }

        for asset in assets {
            for record in records {
                let trackedGoalIDs = Set(record.goalIds)
                let referencedByCurrentAllocation = (asset.allocations ?? []).contains {
                    guard let goalID = $0.goal?.id else { return false }
                    return trackedGoalIDs.contains(goalID)
                }
                let referencedByAllocationEvidence = histories.contains { history in
                    guard history.assetId == asset.id,
                          history.monthLabel == record.monthLabel,
                          let goalID = history.goalId
                    else {
                        return false
                    }
                    return trackedGoalIDs.contains(goalID)
                }
                let referencedByCompletion = record.completedExecution?
                    .contributionSnapshots
                    .contains(where: { $0.assetId == asset.id }) ?? false

                if referencedByCurrentAllocation
                    || referencedByAllocationEvidence
                    || referencedByCompletion {
                    throw PersistenceMutationError.validationFailed(
                        "This asset is part of an active or undoable monthly execution. Finish or let the undo window expire before deleting it."
                    )
                }
            }
        }
    }

}

private struct LinkedTransactionHistoryReplayUpdate {
    let history: AllocationHistory
    let amount: Double
    let sourcePreviousAmount: Double
}

private struct LinkedTransactionDeletionPlan {
    let allocation: AssetAllocation
    let historyToDelete: AllocationHistory
    let updates: [LinkedTransactionHistoryReplayUpdate]
    let finalAllocationAmount: Double

    func apply(in modelContext: ModelContext) {
        for update in updates {
            update.history.amount = update.amount
            update.history.sourcePreviousAmount = update.sourcePreviousAmount
        }
        allocation.updateAmount(finalAllocationAmount)
        modelContext.delete(historyToDelete)
    }
}

@MainActor
final class TransactionMutationService: TransactionMutationServiceProtocol {
    private let modelContext: ModelContext
    private let accessGuard: FamilyShareAccessChecking
    private let saveChanges: () throws -> Void

    init(
        modelContext: ModelContext,
        accessGuard: FamilyShareAccessChecking,
        saveChanges: (() throws -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.accessGuard = accessGuard
        self.saveChanges = saveChanges ?? {
            try modelContext.save()
        }
    }

    @discardableResult
    func createTransaction(
        for asset: Asset,
        amount: Double,
        date: Date,
        comment: String?,
        autoAllocateGoalId: UUID?
    ) throws -> Transaction {
        try accessGuard.assertOwnerWritable(asset: asset)
        if let autoAllocateGoalId {
            try accessGuard.assertOwnerWritable(goalID: autoAllocateGoalId)
        }
        let epsilon = 0.0000001
        let preBalance = asset.currentAmount
        let preIsFullyAllocated = asset.isFullyAllocated
        let preWasDedicatedToSingleGoal = (asset.allocations ?? []).count == 1
        let singleAllocation = (asset.allocations ?? []).first

        var snapshotGoals: [Goal] = []
        if let autoAllocateGoalId {
            let predicate = #Predicate<Goal> { goal in
                goal.id == autoAllocateGoalId
            }
            snapshotGoals = (try? modelContext.fetch(FetchDescriptor<Goal>(predicate: predicate))) ?? []
        }
        let snapshot = PersistenceAllocationGraphSnapshot(assets: [asset], goals: snapshotGoals)
        var createdTransaction: Transaction?
        var insertedAllocations: [AssetAllocation] = []
        var insertedHistories: [AllocationHistory] = []
        let newTransaction = try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: snapshot.models,
            mapSaveError: {
                PersistenceMutationError.saveFailed("Unable to save transaction", underlying: $0)
            },
            restoreTouchedState: {
                PersistenceOperationTransaction.discardInserted(insertedHistories, from: modelContext)
                PersistenceOperationTransaction.discardInserted(insertedAllocations, from: modelContext)
                if let createdTransaction {
                    PersistenceOperationTransaction.discardInserted([createdTransaction], from: modelContext)
                }
                snapshot.restore(in: modelContext)
            }
        ) {
            let transaction = Transaction(amount: amount, asset: asset, date: date, comment: comment)
            createdTransaction = transaction
            asset.transactions = (asset.transactions ?? []) + [transaction]
            modelContext.insert(transaction)

            if let autoAllocateGoalId {
                let mutation = try applyContributionAllocation(
                    goalId: autoAllocateGoalId,
                    asset: asset,
                    depositAmount: amount,
                    timestamp: transaction.date,
                    sourceTransactionID: transaction.id
                )
                if let allocation = mutation.allocation {
                    insertedAllocations.append(allocation)
                }
                if let history = mutation.history {
                    insertedHistories.append(history)
                }
            } else if preIsFullyAllocated,
                      preWasDedicatedToSingleGoal,
                      let allocation = singleAllocation,
                      let goal = allocation.goal {
                let newTarget = max(0, preBalance + amount)
                if abs(newTarget - allocation.amountValue) > epsilon {
                    let previousAmount = allocation.amountValue
                    allocation.updateAmount(newTarget)
                    let history = AllocationHistory(
                        asset: asset,
                        goal: goal,
                        amount: newTarget,
                        timestamp: transaction.date,
                        sourceTransactionId: transaction.id,
                        sourcePreviousAmount: previousAmount
                    )
                    modelContext.insert(history)
                    insertedHistories.append(history)
                }
            }

            return transaction
        }

        let affectedGoalIDs = (asset.allocations ?? []).compactMap { $0.goal?.id }

        NotificationCenter.default.post(name: .goalProgressRefreshed, object: nil)
        if !affectedGoalIDs.isEmpty {
            NotificationCenter.default.post(
                name: .sharedGoalDataDidChange,
                object: nil,
                userInfo: [
                    "affectedGoalIDs": affectedGoalIDs,
                    "reason": "transactionMutation"
                ]
            )
        }

        return newTransaction
    }

    func deleteTransaction(_ transaction: Transaction) throws {
        try accessGuard.assertOwnerWritable(transaction: transaction)
        let transactionID = transaction.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { candidate in
                candidate.id == transactionID
            }
        )
        guard let managedTransaction = try modelContext.fetch(descriptor).first else {
            throw PersistenceMutationError.objectNotFound("Transaction to delete was not found.")
        }
        let asset = managedTransaction.asset
        let affectedGoalIDs = (asset?.allocations ?? []).compactMap { $0.goal?.id }
        let assetHistories: [AllocationHistory]
        let linkedDeletionPlan: LinkedTransactionDeletionPlan?
        if let asset {
            assetHistories = try modelContext
                .fetch(FetchDescriptor<AllocationHistory>())
                .filter { $0.assetId == asset.id }
            linkedDeletionPlan = try linkedAllocationDeletionPlan(
                transaction: managedTransaction,
                asset: asset,
                histories: assetHistories
            )
        } else {
            assetHistories = []
            linkedDeletionPlan = nil
        }
        let snapshot = PersistenceAllocationGraphSnapshot(
            assets: asset.map { [$0] } ?? [],
            transactions: [managedTransaction],
            histories: assetHistories
        )
        let transactionsToDelete: [Transaction]
        do {
            transactionsToDelete = try PersistenceOperationTransaction.resolvePendingInsertDeletions(
                [managedTransaction],
                in: modelContext,
                stableID: \.id
            ) { context, ids in
                let transactionIDs = ids
                let descriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate<Transaction> { candidate in
                        transactionIDs.contains(candidate.id)
                    }
                )
                return try context.fetch(descriptor)
            }
        } catch {
            snapshot.restore(in: modelContext)
            throw error
        }
        guard !transactionsToDelete.isEmpty else {
            postTransactionMutationNotifications(affectedGoalIDs: affectedGoalIDs)
            return
        }

        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: snapshot.models,
            mapSaveError: {
                PersistenceMutationError.saveFailed("Unable to delete transaction", underlying: $0)
            },
            restoreTouchedState: { snapshot.restore(in: modelContext) }
        ) {
            linkedDeletionPlan?.apply(in: modelContext)
            for transactionToDelete in transactionsToDelete {
                modelContext.delete(transactionToDelete)
            }
        }

        postTransactionMutationNotifications(affectedGoalIDs: affectedGoalIDs)
    }

    private func linkedAllocationDeletionPlan(
        transaction: Transaction,
        asset: Asset,
        histories: [AllocationHistory]
    ) throws -> LinkedTransactionDeletionPlan? {
        let epsilon = 0.0000001
        let linked = histories.filter {
            $0.sourceTransactionId == transaction.id
        }

        guard !linked.isEmpty else {
            // Legacy app versions did not link automatic history to its source
            // transaction. A same-time unlinked history for any current
            // allocation target is enough to make deletion ambiguous. Do not
            // use the volatile balance cache or the number of allocations as
            // authorization to delete only the transaction row.
            let allocationGoalIDs = Set(
                (asset.allocations ?? []).compactMap { $0.goal?.id }
            )
            if histories.contains(where: {
                $0.sourceTransactionId == nil
                    && $0.timestamp == transaction.date
                    && $0.goalId.map(allocationGoalIDs.contains) == true
            }) {
                throw PersistenceMutationError.validationFailed(
                    "This transaction has legacy auto-allocation history that cannot be reversed safely."
                )
            }
            return nil
        }

        let linkedGoalID = linked.first?.goalId
        let matchingAllocations = (asset.allocations ?? []).filter {
            $0.goal?.id == linkedGoalID
        }
        guard transaction.source == .manual,
              linked.count == 1,
              let linkedHistory = linked.first,
              matchingAllocations.count == 1,
              let allocation = matchingAllocations.first,
              let goal = allocation.goal,
              linkedHistory.goalId == goal.id
        else {
            throw PersistenceMutationError.validationFailed(
                "This transaction's auto-allocation history is ambiguous and cannot be deleted safely."
            )
        }

        let goalHistories = histories.filter { $0.goalId == goal.id }
        let transactionsByID = Dictionary(
            uniqueKeysWithValues: (asset.transactions ?? []).map { ($0.id, $0) }
        )
        let linkedTransactionIDs = Set(
            goalHistories.compactMap(\.sourceTransactionId)
        )
        guard linkedTransactionIDs.allSatisfy({
            transactionsByID[$0] != nil
        }) else {
            throw PersistenceMutationError.validationFailed(
                "This transaction's auto-allocation history is incomplete and cannot be deleted safely."
            )
        }

        func ordersBefore(
            _ lhs: AllocationHistory,
            _ rhs: AllocationHistory
        ) -> Bool {
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            if lhs.effectiveCreatedAt != rhs.effectiveCreatedAt {
                return lhs.effectiveCreatedAt < rhs.effectiveCreatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let ordered = goalHistories.sorted(by: ordersBefore)
        var oldRunningTarget: Double?
        var initialLinkedBaseline: Double?
        for history in ordered {
            if let transactionID = history.sourceTransactionId {
                guard let sourceTransaction = transactionsByID[transactionID]
                else {
                    throw PersistenceMutationError.validationFailed(
                        "This transaction's auto-allocation history is incomplete and cannot be deleted safely."
                    )
                }
                if oldRunningTarget == nil {
                    let baseline: Double
                    if let persistedBaseline = history.sourcePreviousAmount {
                        baseline = persistedBaseline
                    } else {
                        // A zero result after a withdrawal is clamped and
                        // therefore has no unique inverse.
                        guard !(history.amount <= epsilon
                                && sourceTransaction.amount < 0) else {
                            throw PersistenceMutationError.validationFailed(
                                "This transaction's allocation baseline is ambiguous."
                            )
                        }
                        baseline = history.amount - sourceTransaction.amount
                    }
                    guard baseline.isFinite, baseline >= -epsilon else {
                        throw PersistenceMutationError.validationFailed(
                            "This transaction's allocation baseline is invalid."
                        )
                    }
                    let normalizedBaseline = max(0, baseline)
                    initialLinkedBaseline = normalizedBaseline
                    oldRunningTarget = normalizedBaseline
                } else if let persistedBaseline = history.sourcePreviousAmount {
                    let baselineTolerance = max(
                        epsilon,
                        max(
                            abs(persistedBaseline),
                            abs(oldRunningTarget ?? 0)
                        ) * 0.000001
                    )
                    guard persistedBaseline.isFinite,
                          abs(persistedBaseline - (oldRunningTarget ?? 0))
                            <= baselineTolerance
                    else {
                        throw PersistenceMutationError.validationFailed(
                            "This transaction's allocation baseline is inconsistent."
                        )
                    }
                }
                let expected = max(
                    0,
                    (oldRunningTarget ?? 0) + sourceTransaction.amount
                )
                let tolerance = max(
                    epsilon,
                    max(abs(expected), abs(history.amount)) * 0.000001
                )
                guard expected.isFinite,
                      abs(expected - history.amount) <= tolerance
                else {
                    throw PersistenceMutationError.validationFailed(
                        "This transaction's auto-allocation history is inconsistent and cannot be deleted safely."
                    )
                }
                oldRunningTarget = expected
            } else {
                oldRunningTarget = max(0, history.amount)
            }
        }

        guard let oldFinalTarget = oldRunningTarget else {
            throw PersistenceMutationError.validationFailed(
                "This transaction's auto-allocation history is incomplete and cannot be deleted safely."
            )
        }
        let oldTolerance = max(
            epsilon,
            max(abs(oldFinalTarget), abs(allocation.amountValue)) * 0.000001
        )
        guard abs(oldFinalTarget - allocation.amountValue) <= oldTolerance
        else {
            throw PersistenceMutationError.validationFailed(
                "This transaction's allocation has changed and cannot be reversed safely."
            )
        }

        let remaining = ordered.filter { $0.id != linkedHistory.id }
        var replayTarget: Double?
        var updates: [LinkedTransactionHistoryReplayUpdate] = []
        updates.reserveCapacity(linkedTransactionIDs.count - 1)
        for history in remaining {
            guard let transactionID = history.sourceTransactionId else {
                replayTarget = max(0, history.amount)
                continue
            }
            guard let sourceTransaction = transactionsByID[transactionID] else {
                throw PersistenceMutationError.validationFailed(
                    "This transaction's auto-allocation history is incomplete and cannot be deleted safely."
                )
            }
            if replayTarget == nil {
                guard let initialLinkedBaseline else {
                    throw PersistenceMutationError.validationFailed(
                        "This transaction's allocation baseline is missing."
                    )
                }
                replayTarget = initialLinkedBaseline
            }
            let nextTarget = max(
                0,
                (replayTarget ?? 0) + sourceTransaction.amount
            )
            guard nextTarget.isFinite else {
                throw PersistenceMutationError.validationFailed(
                    "This transaction's allocation result is invalid."
                )
            }
            updates.append(
                LinkedTransactionHistoryReplayUpdate(
                    history: history,
                    amount: nextTarget,
                    sourcePreviousAmount: replayTarget ?? 0
                )
            )
            replayTarget = nextTarget
        }

        let finalTarget = replayTarget ?? initialLinkedBaseline ?? 0
        let isDedicatedAsset = (asset.allocations ?? []).count == 1
        if isDedicatedAsset
            && (remaining.last?.sourceTransactionId != nil || remaining.isEmpty) {
            let postDeleteBalance = asset.currentAmount - transaction.amount
            let tolerance = max(
                epsilon,
                max(abs(postDeleteBalance), abs(finalTarget)) * 0.000001
            )
            guard postDeleteBalance.isFinite,
                  abs(postDeleteBalance - finalTarget) <= tolerance
            else {
                throw PersistenceMutationError.validationFailed(
                    "The latest asset balance no longer proves this automatic allocation."
                )
            }
        }

        return LinkedTransactionDeletionPlan(
            allocation: allocation,
            historyToDelete: linkedHistory,
            updates: updates,
            finalAllocationAmount: finalTarget
        )
    }

    private func postTransactionMutationNotifications(affectedGoalIDs: [UUID]) {
        NotificationCenter.default.post(name: .goalProgressRefreshed, object: nil)
        if !affectedGoalIDs.isEmpty {
            NotificationCenter.default.post(
                name: .sharedGoalDataDidChange,
                object: nil,
                userInfo: [
                    "affectedGoalIDs": affectedGoalIDs,
                    "reason": "transactionMutation"
                ]
            )
        }
    }

    private func applyContributionAllocation(
        goalId: UUID,
        asset: Asset,
        depositAmount: Double,
        timestamp: Date,
        sourceTransactionID: UUID
    ) throws -> (allocation: AssetAllocation?, history: AllocationHistory?) {
        try accessGuard.assertOwnerWritable(asset: asset)
        try accessGuard.assertOwnerWritable(goalID: goalId)
        guard depositAmount > 0.0000001 else { return (nil, nil) }

        if let allocation = (asset.allocations ?? []).first(where: { $0.goal?.id == goalId }),
           let goal = allocation.goal {
            let previousAmount = allocation.amountValue
            let newTarget = max(0, previousAmount + depositAmount)
            allocation.updateAmount(newTarget)
            let history = AllocationHistory(
                asset: asset,
                goal: goal,
                amount: newTarget,
                timestamp: timestamp,
                sourceTransactionId: sourceTransactionID,
                sourcePreviousAmount: previousAmount
            )
            modelContext.insert(history)
            return (nil, history)
        }

        let predicate = #Predicate<Goal> { goal in
            goal.id == goalId
        }
        guard let goal = try modelContext.fetch(FetchDescriptor<Goal>(predicate: predicate)).first else {
            throw PersistenceMutationError.objectNotFound("Goal for contribution allocation was not found.")
        }

        let allocation = AssetAllocation(asset: asset, goal: goal, amount: depositAmount)
        let history = AllocationHistory(
            asset: asset,
            goal: goal,
            amount: depositAmount,
            timestamp: timestamp,
            sourceTransactionId: sourceTransactionID,
            sourcePreviousAmount: 0
        )
        modelContext.insert(allocation)
        modelContext.insert(history)
        return (allocation, history)
    }

}

@MainActor
final class PlanningMutationService: PlanningMutationServiceProtocol {
    private let modelContext: ModelContext
    private let exchangeRateService: ExchangeRateServiceProtocol
    private let accessGuard: FamilyShareAccessChecking
    private let saveChanges: () throws -> Void
    private let planDeletionFetchByIDs: (ModelContext, [UUID]) throws -> [MonthlyPlan]
    private let now: () -> Date
    private let currentTotalResult: (Goal) async -> GoalCurrentTotalResult
    private let rateSnapshotTTL: TimeInterval

    init(
        modelContext: ModelContext,
        exchangeRateService: ExchangeRateServiceProtocol,
        accessGuard: FamilyShareAccessChecking,
        saveChanges: (() throws -> Void)? = nil,
        planDeletionFetchByIDs: ((
            ModelContext,
            [UUID]
        ) throws -> [MonthlyPlan])? = nil,
        now: @escaping () -> Date = Date.init,
        currentTotalResult: @escaping (Goal) async -> GoalCurrentTotalResult = {
            goal in
            await GoalCalculationService.getCurrentTotalResult(for: goal)
        },
        rateSnapshotTTL: TimeInterval = 300
    ) {
        self.modelContext = modelContext
        self.exchangeRateService = exchangeRateService
        self.accessGuard = accessGuard
        self.saveChanges = saveChanges ?? {
            try modelContext.save()
        }
        self.planDeletionFetchByIDs = planDeletionFetchByIDs ?? { context, ids in
            let planIDs = ids
            let descriptor = FetchDescriptor<MonthlyPlan>(
                predicate: #Predicate<MonthlyPlan> { candidate in
                    planIDs.contains(candidate.id)
                }
            )
            return try context.fetch(descriptor)
        }
        self.now = now
        self.currentTotalResult = currentTotalResult
        self.rateSnapshotTTL = rateSnapshotTTL
    }

    func markPlanCompleted(_ plan: MonthlyPlan) throws {
        try accessGuard.assertOwnerWritable(plan: plan)
        let snapshot = PlanningPlanMutationSnapshot(plan: plan)
        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: [plan],
            mapSaveError: {
                PersistenceMutationError.saveFailed(
                    "Unable to mark plan completed",
                    underlying: $0
                )
            },
            restoreTouchedState: { snapshot.restore() }
        ) {
            plan.state = .completed
            plan.isSkipped = false
        }
        postSharedGoalDataDidChange(goalIDs: [plan.goalId], reason: "goalMutation")
    }

    func markPlanSkipped(_ plan: MonthlyPlan) throws {
        try accessGuard.assertOwnerWritable(plan: plan)
        let snapshot = PlanningPlanMutationSnapshot(plan: plan)
        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: [plan],
            mapSaveError: {
                PersistenceMutationError.saveFailed("Unable to skip plan", underlying: $0)
            },
            restoreTouchedState: { snapshot.restore() }
        ) {
            plan.isSkipped = true
            plan.state = .completed
        }
        postSharedGoalDataDidChange(goalIDs: [plan.goalId], reason: "goalMutation")
    }

    func deletePlan(_ plan: MonthlyPlan) throws {
        try accessGuard.assertOwnerWritable(plan: plan)
        let goalID = plan.goalId
        let candidateSnapshot = PlanningPlanMutationSnapshot(plan: plan)
        let plansToDelete: [MonthlyPlan]
        do {
            plansToDelete = try resolvePlansForDeletion([plan])
        } catch {
            candidateSnapshot.restore(in: modelContext)
            throw error
        }
        guard let planToDelete = plansToDelete.first else {
            postSharedGoalDataDidChange(goalIDs: [goalID], reason: "goalMutation")
            return
        }
        let durableSnapshot = PlanningPlanMutationSnapshot(plan: planToDelete)
        let allowedModels = (durableSnapshot.models + candidateSnapshot.models).reduce(
            into: [any PersistentModel]()
        ) { uniqueModels, model in
            guard uniqueModels.contains(where: {
                $0.persistentModelID == model.persistentModelID
            }) == false else { return }
            uniqueModels.append(model)
        }
        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: allowedModels,
            mapSaveError: {
                PersistenceMutationError.saveFailed("Unable to delete plan", underlying: $0)
            },
            restoreTouchedState: {
                durableSnapshot.restore(in: modelContext)
                if planToDelete !== plan {
                    candidateSnapshot.restore(in: modelContext)
                }
            }
        ) {
            modelContext.delete(planToDelete)
        }
        postSharedGoalDataDidChange(goalIDs: [goalID], reason: "goalMutation")
    }

    func preparePlansForExecution(_ plans: [MonthlyPlan]) throws {
        try accessGuard.assertOwnerWritable(plans: plans)
        let plansToChange = plans.filter {
            $0.state != .draft || (!$0.isSkipped && $0.effectiveAmount <= 0)
        }
        guard !plansToChange.isEmpty else { return }
        let snapshots = plansToChange.map(PlanningPlanMutationSnapshot.init)
        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: plansToChange,
            mapSaveError: {
                PersistenceMutationError.saveFailed(
                    "Unable to prepare plans for execution",
                    underlying: $0
                )
            },
            restoreTouchedState: { snapshots.forEach { $0.restore() } }
        ) {
            for plan in plansToChange where plan.state != .draft {
                plan.state = .draft
            }
            for plan in plansToChange where !plan.isSkipped && plan.effectiveAmount <= 0 {
                plan.isSkipped = true
            }
        }
        postSharedGoalDataDidChange(
            goalIDs: Set(plansToChange.map(\.goalId)),
            reason: "goalMutation"
        )
    }

    func resetPlansToDraft(_ plans: [MonthlyPlan]) throws {
        try accessGuard.assertOwnerWritable(plans: plans)
        let plansToChange = plans.filter { $0.state != .draft }
        guard !plansToChange.isEmpty else { return }
        let snapshots = plansToChange.map(PlanningPlanMutationSnapshot.init)
        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: plansToChange,
            mapSaveError: {
                PersistenceMutationError.saveFailed(
                    "Unable to reset plans to draft",
                    underlying: $0
                )
            },
            restoreTouchedState: { snapshots.forEach { $0.restore() } }
        ) {
            for plan in plansToChange {
                plan.state = .draft
            }
        }
        postSharedGoalDataDidChange(
            goalIDs: Set(plansToChange.map(\.goalId)),
            reason: "goalMutation"
        )
    }

    func applyFeasibilitySuggestion(_ suggestion: FeasibilitySuggestion, goals: [Goal]) throws -> Bool {
        try accessGuard.assertOwnerWritable(goals: goals)
        switch suggestion {
        case .increaseBudget, .editGoal:
            return false
        case .extendDeadline(let goalId, _, let months):
            guard let goal = goals.first(where: { $0.id == goalId }) else { return false }
            guard let updated = Calendar.current.date(byAdding: .month, value: months, to: goal.deadline) else {
                return false
            }
            let snapshot = PlanningGoalMutationSnapshot(goal: goal)
            try PersistenceOperationTransaction.perform(
                in: modelContext,
                saveChanges: saveChanges,
                allowingPreexistingChangesTo: [goal],
                mapSaveError: {
                    PersistenceMutationError.saveFailed(
                        "Unable to apply feasibility suggestion",
                        underlying: $0
                    )
                },
                restoreTouchedState: { snapshot.restore() }
            ) {
                goal.deadline = updated
            }
            postSharedGoalDataDidChange(goalIDs: [goal.id], reason: "goalMutation")
        case .reduceTarget(let goalId, _, let to, _):
            guard let goal = goals.first(where: { $0.id == goalId }) else { return false }
            let snapshot = PlanningGoalMutationSnapshot(goal: goal)
            try PersistenceOperationTransaction.perform(
                in: modelContext,
                saveChanges: saveChanges,
                allowingPreexistingChangesTo: [goal],
                mapSaveError: {
                    PersistenceMutationError.saveFailed(
                        "Unable to apply feasibility suggestion",
                        underlying: $0
                    )
                },
                restoreTouchedState: { snapshot.restore() }
            ) {
                goal.targetAmount = to
            }
            postSharedGoalDataDidChange(goalIDs: [goal.id], reason: "goalMutation")
        }

        return true
    }

    func applyBudgetPlan(
        _ plan: BudgetCalculatorPlan,
        currentPlans: [MonthlyPlan],
        budgetCurrency: String,
        validateBeforeCommit: @MainActor () -> Bool
    ) async throws {
        try accessGuard.assertOwnerWritable(plans: currentPlans)
        let canonicalBudgetCurrency = budgetCurrency.uppercased()
        guard plan.currency.uppercased() == canonicalBudgetCurrency else {
            throw PersistenceMutationError.validationFailed(
                "The preview currency no longer matches the selected budget currency."
            )
        }
        guard let snapshotId = plan.rateSnapshotId,
              !snapshotId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let snapshotTimestamp = plan.rateSnapshotTimestamp else {
            throw PersistenceMutationError.validationFailed(
                "The budget preview is missing its exchange-rate snapshot."
            )
        }
        let snapshotAge = now().timeIntervalSince(snapshotTimestamp)
        guard snapshotAge >= 0, snapshotAge < rateSnapshotTTL else {
            throw PersistenceMutationError.validationFailed(
                "The budget preview has expired. Refresh it before applying."
            )
        }
        let validatedSourceFingerprint = try await validateBudgetSourceState(
            plan,
            currentPlans: currentPlans
        )

        var affectedGoalIDs: Set<UUID> = []
        let contributionMap = Dictionary(
            uniqueKeysWithValues: (plan.schedule.first?.contributions ?? []).map { ($0.goalId, $0.amount) }
        )
        var convertedAmounts: [UUID: Double] = [:]
        let requiredTargetCurrencies = Set(
            currentPlans.compactMap { monthlyPlan -> String? in
                guard !monthlyPlan.isSkipped,
                      (contributionMap[monthlyPlan.goalId] ?? 0) > 0 else {
                    return nil
                }
                let targetCurrency = monthlyPlan.currency.uppercased()
                return targetCurrency == canonicalBudgetCurrency ? nil : targetCurrency
            }
        )
        var applicationRatesByTarget: [String: Double] = [:]

        for targetCurrency in requiredTargetCurrencies.sorted() {
            let pairKey = "\(canonicalBudgetCurrency)->\(targetCurrency)"
            guard let rate = plan.applicationRatesByPair[pairKey],
                  rate.isFinite,
                  rate > 0 else {
                throw PersistenceMutationError.validationFailed(
                    "The budget preview is missing exchange rates for some goals."
                )
            }
            applicationRatesByTarget[targetCurrency] = rate
        }

        for monthlyPlan in currentPlans {
            guard !monthlyPlan.isSkipped else { continue }
            let plannedAmount = contributionMap[monthlyPlan.goalId] ?? 0
            var converted = plannedAmount
            let targetCurrency = monthlyPlan.currency.uppercased()

            if plannedAmount > 0, targetCurrency != canonicalBudgetCurrency {
                guard let rate = applicationRatesByTarget[targetCurrency] else {
                    throw PersistenceMutationError.validationFailed(
                        "The budget preview is missing exchange rates for some goals."
                    )
                }
                converted = plannedAmount * rate
            }

            convertedAmounts[monthlyPlan.goalId] = plannedAmount > 0 ? converted : 0
        }

        let plansToMutate = currentPlans
            .filter { !$0.isSkipped && convertedAmounts[$0.goalId] != nil }
        let mutationSnapshots = plansToMutate.map(PlanningBudgetPlanMutationSnapshot.init)

        guard try budgetSourceFingerprint(currentPlans: currentPlans)
            == validatedSourceFingerprint
        else {
            throw budgetSourceDriftError()
        }

        try PersistenceOperationTransaction.assertNoUnrelatedPendingChanges(
            in: modelContext,
            allowing: plansToMutate
        )

        guard validateBeforeCommit() else {
            throw PersistenceMutationError.validationFailed(
                "Budget inputs changed while Apply was validating. Refresh the preview and retry."
            )
        }

        do {
            for monthlyPlan in plansToMutate {
                guard let converted = convertedAmounts[monthlyPlan.goalId] else { continue }
                monthlyPlan.setCustomAmount(converted)
                affectedGoalIDs.insert(monthlyPlan.goalId)
            }

            try saveContext(operation: "Unable to apply budget to plans")
        } catch {
            mutationSnapshots.forEach { $0.restore() }
            throw error
        }

        postSharedGoalDataDidChange(goalIDs: affectedGoalIDs, reason: "goalMutation")
    }

    private func validateBudgetSourceState(
        _ plan: BudgetCalculatorPlan,
        currentPlans: [MonthlyPlan]
    ) async throws -> PlanningBudgetSourceFingerprint {
        guard let expectedSignature = plan.sourceStateSignature,
              !expectedSignature.isEmpty else {
            throw PersistenceMutationError.validationFailed(
                "The budget preview is missing its source-state identity. Refresh it before applying."
            )
        }
        let sourceFingerprint = try budgetSourceFingerprint(
            currentPlans: currentPlans
        )

        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { goal in
                goal.lifecycleStatusRawValue == "active"
            }
        )
        let activeGoals = try modelContext.fetch(descriptor)
        let skippedGoalIDs = Set(currentPlans.filter(\.isSkipped).map(\.goalId))
        let sourceGoals = activeGoals.filter { !skippedGoalIDs.contains($0.id) }
        let sourceGoalIDs = Set(sourceGoals.map(\.id))
        let applicablePlanGoalIDs = Set(
            currentPlans.filter { !$0.isSkipped }.map(\.goalId)
        )
        guard sourceGoalIDs == applicablePlanGoalIDs else {
            throw PersistenceMutationError.validationFailed(
                "Goals changed after this budget preview was calculated. Refresh it before applying."
            )
        }

        var remainingByGoal: [UUID: Double] = [:]
        for goal in sourceGoals {
            let totalResult = await currentTotalResult(goal)
            guard totalResult.isComplete else {
                throw PersistenceMutationError.validationFailed(
                    "Current balances are unavailable. Refresh balances and retry."
                )
            }
            remainingByGoal[goal.id] = max(0, goal.targetAmount - totalResult.total)
        }

        guard try budgetSourceFingerprint(currentPlans: currentPlans)
            == sourceFingerprint
        else {
            throw budgetSourceDriftError()
        }

        let actualSignature = BudgetSnapshotIdentity.sourceStateSignature(
            goals: sourceGoals,
            remainingByGoal: remainingByGoal
        )
        guard actualSignature == expectedSignature else {
            throw PersistenceMutationError.validationFailed(
                "Goals or balances changed after this budget preview was calculated. Refresh it before applying."
            )
        }
        return sourceFingerprint
    }

    private func budgetSourceFingerprint(
        currentPlans: [MonthlyPlan]
    ) throws -> PlanningBudgetSourceFingerprint {
        modelContext.processPendingChanges()

        let currentPlanIDs = Set(currentPlans.map(\.id))
        let currentPlanGoalIDs = Set(currentPlans.map(\.goalId))
        let goals = try modelContext.fetch(FetchDescriptor<Goal>()).filter {
            $0.lifecycleStatus == .active || currentPlanGoalIDs.contains($0.id)
        }
        let relevantGoalIDs = Set(goals.map(\.id))
        let durablePlans = try modelContext.fetch(
            FetchDescriptor<MonthlyPlan>()
        ).filter { currentPlanIDs.contains($0.id) }
        let allocations = try modelContext.fetch(
            FetchDescriptor<AssetAllocation>()
        ).filter {
            guard let goalID = $0.goal?.id else { return false }
            return relevantGoalIDs.contains(goalID)
        }
        let relevantAssetIDs = Set(allocations.compactMap { $0.asset?.id })
        let assets = try modelContext.fetch(FetchDescriptor<Asset>())
            .filter { relevantAssetIDs.contains($0.id) }
        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
            .filter {
                guard let assetID = $0.asset?.id else { return false }
                return relevantAssetIDs.contains(assetID)
            }

        return PlanningBudgetSourceFingerprint(
            goals: goals.map(PlanningBudgetGoalFingerprint.init).sorted {
                $0.id.uuidString < $1.id.uuidString
            },
            plans: durablePlans.map(PlanningBudgetPlanFingerprint.init).sorted {
                $0.id.uuidString < $1.id.uuidString
            },
            assets: assets.map(PlanningBudgetAssetFingerprint.init).sorted {
                $0.id.uuidString < $1.id.uuidString
            },
            transactions: transactions
                .map(PlanningBudgetTransactionFingerprint.init)
                .sorted { $0.id.uuidString < $1.id.uuidString },
            allocations: allocations
                .map(PlanningBudgetAllocationFingerprint.init)
                .sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    private func budgetSourceDriftError() -> PersistenceMutationError {
        PersistenceMutationError.validationFailed(
            "Goals, balances, or allocations changed while the budget was being validated. Refresh it before applying."
        )
    }

    private func saveContext(operation: String) throws {
        do {
            try saveChanges()
        } catch {
            throw PersistenceMutationError.saveFailed(operation, underlying: error)
        }
    }

    private func resolvePlansForDeletion(
        _ plans: [MonthlyPlan]
    ) throws -> [MonthlyPlan] {
        try PersistenceOperationTransaction.resolvePendingInsertDeletions(
            plans,
            in: modelContext,
            stableID: \.id,
            fetchByIDs: planDeletionFetchByIDs
        )
    }

    private func postSharedGoalDataDidChange(goalIDs: Set<UUID>, reason: String) {
        guard goalIDs.isEmpty == false else { return }
        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": Array(goalIDs),
                "reason": reason
            ]
        )
    }
}

private struct PlanningBudgetSourceFingerprint: Equatable {
    let goals: [PlanningBudgetGoalFingerprint]
    let plans: [PlanningBudgetPlanFingerprint]
    let assets: [PlanningBudgetAssetFingerprint]
    let transactions: [PlanningBudgetTransactionFingerprint]
    let allocations: [PlanningBudgetAllocationFingerprint]
}

private struct PlanningBudgetGoalFingerprint: Equatable {
    let id: UUID
    let currency: String
    let targetAmountBits: UInt64
    let deadline: Date
    let lifecycleStatusRawValue: String
    let lifecycleStatusChangedAt: Date?

    init(_ goal: Goal) {
        id = goal.id
        currency = goal.currency
        targetAmountBits = goal.targetAmount.bitPattern
        deadline = goal.deadline
        lifecycleStatusRawValue = goal.lifecycleStatusRawValue
        lifecycleStatusChangedAt = goal.lifecycleStatusChangedAt
    }
}

private struct PlanningBudgetPlanFingerprint: Equatable {
    let id: UUID
    let goalID: UUID
    let monthLabel: String
    let requiredMonthlyBits: UInt64
    let remainingAmountBits: UInt64
    let monthsRemaining: Int
    let currency: String
    let statusRawValue: String
    let stateRawValue: String
    let customAmountBits: UInt64?
    let flexStateRawValue: String
    let isProtected: Bool
    let isSkipped: Bool

    init(_ plan: MonthlyPlan) {
        id = plan.id
        goalID = plan.goalId
        monthLabel = plan.monthLabel
        requiredMonthlyBits = plan.requiredMonthly.bitPattern
        remainingAmountBits = plan.remainingAmount.bitPattern
        monthsRemaining = plan.monthsRemaining
        currency = plan.currency
        statusRawValue = plan.statusRawValue
        stateRawValue = plan.stateRawValue
        customAmountBits = plan.customAmount?.bitPattern
        flexStateRawValue = plan.flexStateRawValue
        isProtected = plan.isProtected
        isSkipped = plan.isSkipped
    }
}

private struct PlanningBudgetAssetFingerprint: Equatable {
    let id: UUID
    let currency: String
    let address: String?
    let chainID: String?
    let currentAmountBits: UInt64

    init(_ asset: Asset) {
        id = asset.id
        currency = asset.currency
        address = asset.address
        chainID = asset.chainId
        currentAmountBits = asset.currentAmount.bitPattern
    }
}

private struct PlanningBudgetTransactionFingerprint: Equatable {
    let id: UUID
    let assetID: UUID?
    let amountBits: UInt64
    let date: Date
    let sourceRawValue: String
    let externalID: String?

    init(_ transaction: Transaction) {
        id = transaction.id
        assetID = transaction.asset?.id
        amountBits = transaction.amount.bitPattern
        date = transaction.date
        sourceRawValue = transaction.sourceRawValue
        externalID = transaction.externalId
    }
}

private struct PlanningBudgetAllocationFingerprint: Equatable {
    let id: UUID
    let assetID: UUID?
    let goalID: UUID?
    let amountBits: UInt64
    let createdDate: Date
    let lastModifiedDate: Date

    init(_ allocation: AssetAllocation) {
        id = allocation.id
        assetID = allocation.asset?.id
        goalID = allocation.goal?.id
        amountBits = allocation.amountValue.bitPattern
        createdDate = allocation.createdDate
        lastModifiedDate = allocation.lastModifiedDate
    }
}

private struct PlanningPlanMutationSnapshot {
    let plan: MonthlyPlan
    let executionRecord: MonthlyExecutionRecord?
    let executionRecordPlans: [MonthlyPlan]?
    let monthLabel: String
    let requiredMonthly: Double
    let remainingAmount: Double
    let monthsRemaining: Int
    let currency: String
    let statusRawValue: String
    let lastCalculated: Date
    let stateRawValue: String
    let flexStateRawValue: String
    let customAmount: Double?
    let isProtected: Bool
    let isSkipped: Bool
    let lastModifiedDate: Date

    var models: [any PersistentModel] {
        var models: [any PersistentModel] = [plan]
        if let executionRecord {
            models.append(executionRecord)
        }
        return models
    }

    init(plan: MonthlyPlan) {
        self.plan = plan
        let executionRecord = plan.executionRecord
        self.executionRecord = executionRecord
        executionRecordPlans = executionRecord?.plans
        monthLabel = plan.monthLabel
        requiredMonthly = plan.requiredMonthly
        remainingAmount = plan.remainingAmount
        monthsRemaining = plan.monthsRemaining
        currency = plan.currency
        statusRawValue = plan.statusRawValue
        lastCalculated = plan.lastCalculated
        stateRawValue = plan.stateRawValue
        flexStateRawValue = plan.flexStateRawValue
        customAmount = plan.customAmount
        isProtected = plan.isProtected
        isSkipped = plan.isSkipped
        lastModifiedDate = plan.lastModifiedDate
    }

    func restore() {
        plan.monthLabel = monthLabel
        plan.requiredMonthly = requiredMonthly
        plan.remainingAmount = remainingAmount
        plan.monthsRemaining = monthsRemaining
        plan.currency = currency
        plan.statusRawValue = statusRawValue
        plan.lastCalculated = lastCalculated
        plan.stateRawValue = stateRawValue
        plan.flexStateRawValue = flexStateRawValue
        plan.customAmount = customAmount
        plan.isProtected = isProtected
        plan.isSkipped = isSkipped
        plan.lastModifiedDate = lastModifiedDate
    }

    func restore(in modelContext: ModelContext) {
        let previousUndoManager = modelContext.undoManager
        modelContext.undoManager = nil
        defer {
            modelContext.undoManager = previousUndoManager
        }

        let wasDeleted = modelContext.deletedModelsArray.contains {
            $0.persistentModelID == plan.persistentModelID
        }
        if plan.modelContext == nil || wasDeleted {
            modelContext.insert(plan)
            modelContext.processPendingChanges()
        }
        restore()
        plan.executionRecord = executionRecord
        executionRecord?.plans = executionRecordPlans
        modelContext.processPendingChanges()
    }
}

private struct PlanningGoalMutationSnapshot {
    let goal: Goal
    let targetAmount: Double
    let deadline: Date
    let lastModifiedDate: Date

    init(goal: Goal) {
        self.goal = goal
        targetAmount = goal.targetAmount
        deadline = goal.deadline
        lastModifiedDate = goal.lastModifiedDate
    }

    func restore() {
        goal.targetAmount = targetAmount
        goal.deadline = deadline
        goal.lastModifiedDate = lastModifiedDate
    }
}

private struct PlanningBudgetPlanMutationSnapshot {
    let plan: MonthlyPlan
    let customAmount: Double?
    let lastModifiedDate: Date

    init(plan: MonthlyPlan) {
        self.plan = plan
        self.customAmount = plan.customAmount
        self.lastModifiedDate = plan.lastModifiedDate
    }

    func restore() {
        plan.customAmount = customAmount
        plan.lastModifiedDate = lastModifiedDate
    }
}

@MainActor
final class OnboardingMutationService: OnboardingMutationServiceProtocol {
    private let modelContext: ModelContext
    private let notificationManager: NotificationManager
    private let saveChanges: () throws -> Void

    init(
        modelContext: ModelContext,
        notificationManager: NotificationManager? = nil,
        saveChanges: (() throws -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.notificationManager = notificationManager ?? .shared
        self.saveChanges = saveChanges ?? {
            try modelContext.save()
        }
    }

    func createGoalFromTemplate(
        _ template: GoalTemplate,
        userProfile: UserProfile,
        selectedAssetCurrencies: Set<String>
    ) async throws {
        #if DEBUG
        if UITestFlags.consumeSimulatedGoalSaveFailureIfNeeded() {
            throw PersistenceMutationError.saveFailed(
                "Unable to create onboarding goal",
                underlying: NSError(
                    domain: "UITestFlags",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Simulated onboarding goal save failure"]
                )
            )
        }
        #endif

        let operationGoalID = Self.deterministicOnboardingGoalID(for: template)
        let existingGoalDescriptor = FetchDescriptor<Goal>(
            predicate: #Predicate<Goal> { candidate in
                candidate.id == operationGoalID
            }
        )
        if let existingGoal = try modelContext.fetch(existingGoalDescriptor).first {
            let expected = template.createGoal()
            guard existingGoal.name == expected.name,
                  existingGoal.currency.uppercased() == expected.currency.uppercased(),
                  abs(existingGoal.targetAmount - expected.targetAmount) <= 0.000_000_1
            else {
                throw PersistenceMutationError.validationFailed(
                    "The saved onboarding operation conflicts with another goal."
                )
            }
            await finishSuccessfulMutation(for: existingGoal)
            return
        }

        let goalData = template.createGoal()
        let goal = Goal(
            name: goalData.name,
            currency: goalData.currency,
            targetAmount: goalData.targetAmount,
            deadline: goalData.deadline,
            startDate: Date()
        )
        goal.id = operationGoalID
        var insertedAssets: [Asset] = []
        var insertedAllocations: [AssetAllocation] = []
        try PersistenceOperationTransaction.perform(
            in: modelContext,
            saveChanges: saveChanges,
            allowingPreexistingChangesTo: [],
            mapSaveError: {
                PersistenceMutationError.saveFailed("Unable to create onboarding goal", underlying: $0)
            },
            restoreTouchedState: {
                PersistenceOperationTransaction.discardInserted(
                    insertedAllocations,
                    from: modelContext
                )
                PersistenceOperationTransaction.discardInserted(
                    insertedAssets,
                    from: modelContext
                )
                PersistenceOperationTransaction.discardInserted([goal], from: modelContext)
            }
        ) {
            goal.clearRetiredReminderState()
            modelContext.insert(goal)

            let normalizedSelection = Set(
                selectedAssetCurrencies.map { $0.uppercased() }
            )
            for recommendation in template.generateAssets()
            where normalizedSelection.contains(recommendation.currency.uppercased()) {
                let asset = Asset(currency: recommendation.currency)
                let allocation = AssetAllocation(asset: asset, goal: goal, amount: asset.currentAmount)
                modelContext.insert(asset)
                modelContext.insert(allocation)
                insertedAssets.append(asset)
                insertedAllocations.append(allocation)
            }
        }
        await finishSuccessfulMutation(for: goal)
    }

    private func finishSuccessfulMutation(for goal: Goal) async {
        await notificationManager.cancelNotifications(for: goal)
        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": [goal.id],
                "reason": "goalMutation"
            ]
        )
    }

    private static func deterministicOnboardingGoalID(for template: GoalTemplate) -> UUID {
        let payload = [
            "onboarding-goal-v1",
            template.type.rawValue,
            template.name,
            template.currency.uppercased(),
            String(template.defaultAmount.bitPattern, radix: 16),
            String(template.defaultTimeframe)
        ].joined(separator: "|")
        var bytes = Array(SHA256.hash(data: Data(payload.utf8)).prefix(16))
        // RFC 4122 variant with a version-5 marker. The payload uses SHA-256,
        // but the UUID bits communicate that this is a name-derived identity.
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
