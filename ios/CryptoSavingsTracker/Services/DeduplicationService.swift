//
//  DeduplicationService.swift
//  CryptoSavingsTracker
//
//  Application-level deduplication for CloudKit sync conflicts.
//  Since @Attribute(.unique) is not supported with CloudKit, duplicates
//  can appear when the same logical record is created on multiple devices.
//

import Foundation
import SwiftData
import os

enum DeduplicationError: LocalizedError {
    case unsafeAllocationMerge(
        assetID: UUID,
        requested: Double,
        available: Double
    )
    case conflictingExecutionEvidence(
        monthLabel: String,
        recordIDs: [UUID]
    )
    case conflictingTransactionAllocationProvenance(
        externalID: String,
        transactionIDs: [UUID],
        linkedTransactionIDs: [UUID]
    )

    var errorDescription: String? {
        switch self {
        case .unsafeAllocationMerge(_, let requested, let available):
            return "Deduplication would allocate \(requested) from an asset with only \(available) available."
        case .conflictingExecutionEvidence(let monthLabel, let recordIDs):
            return "Execution \(monthLabel) has conflicting durable evidence in records "
                + recordIDs.map(\.uuidString).sorted().joined(separator: ", ")
                + ". Automatic deduplication stopped without changing the store."
        case .conflictingTransactionAllocationProvenance(
            let externalID,
            let transactionIDs,
            let linkedTransactionIDs
        ):
            let records = transactionIDs.map(\.uuidString).sorted().joined(
                separator: ", "
            )
            let linkedRecords = linkedTransactionIDs.map(\.uuidString).sorted()
                .joined(separator: ", ")
            return "Transaction \(externalID) has conflicting duplicate financial data "
                + "or allocation-history provenance across records \(records). "
                + "Linked allocation sources: \(linkedRecords). "
                + "Automatic deduplication stopped without changing the store."
        }
    }
}

private struct TransactionDeduplicationKey: Hashable {
    let assetID: UUID?
    let externalID: String

    var sortKey: String {
        "\(assetID?.uuidString ?? "")|\(externalID)"
    }
}

private struct TransactionAllocationFingerprint: Hashable {
    let amountBits: UInt64
    let date: Date
    let sourceRawValue: String

    init(_ transaction: Transaction) {
        amountBits = transaction.amount.bitPattern
        date = transaction.date
        sourceRawValue = transaction.sourceRawValue
    }
}

private struct TransactionDeduplicationPlan {
    let survivor: Transaction
    let duplicates: [Transaction]
    let historiesToRekey: [AllocationHistory]
}

@MainActor
final class DeduplicationService {

    private let logger = Logger(subsystem: "xax.CryptoSavingsTracker", category: "deduplication")

    // MARK: - Full Deduplication

    func runFullDeduplication(in context: ModelContext) async throws {
        logger.info("Starting full deduplication pass")
        // CloudKit monitoring calls this service from the shared main context,
        // which can also contain unsaved UI drafts. Perform the repair against
        // the same durable store in an operation-owned context so neither
        // save nor rollback can commit or discard caller-owned changes.
        let operationContext = ModelContext(context.container)
        operationContext.autosaveEnabled = false

        do {
            var totalRemoved = 0

            totalRemoved += try deduplicateGoals(in: operationContext)
            totalRemoved += try deduplicateMonthlyPlans(in: operationContext)
            totalRemoved += try deduplicateExecutionRecords(in: operationContext)
            totalRemoved += try deduplicateCompletedExecutions(in: operationContext)
            totalRemoved += try deduplicateAssets(in: operationContext)
            totalRemoved += try deduplicateAssetAllocations(in: operationContext)
            totalRemoved += try deduplicateTransactions(in: operationContext)
            totalRemoved += try deduplicateAllocationHistory(in: operationContext)

            if totalRemoved > 0 {
                try operationContext.save()
                postSharedGoalRepairIfNeeded(in: operationContext)
                logger.info("Deduplication complete: removed \(totalRemoved) duplicate(s)")
            } else {
                logger.info("Deduplication complete: no duplicates found")
            }
        } catch {
            // This rollback is limited to the operation-owned context. The
            // caller's pending edits remain intact.
            operationContext.rollback()
            throw error
        }
    }

    // MARK: - Per-Entity Deduplication

    /// Deduplicate Goal by (name, currency, startDate-day). Keep the most recently modified.
    /// startDate anchors the goal's creation moment, distinguishing re-created goals
    /// with the same name and currency but different creation dates.
    /// This matches the logical key used by GoalRepository.deduplicateInMemory.
    @discardableResult
    func deduplicateGoals(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Goal>(
            sortBy: [SortDescriptor(\.lastModifiedDate, order: .reverse)]
        )
        let goals = try context.fetch(descriptor)

        // Build groups keyed by logical identity
        var groups: [String: [Goal]] = [:]
        for goal in goals {
            let key = GoalRepository.goalLogicalKey(goal)
            groups[key, default: []].append(goal)
        }

        // Prefetch UUID-keyed entities that reference goals by ID (not relationship)
        let allPlans = try context.fetch(FetchDescriptor<MonthlyPlan>())
        let allExecRecords = try context.fetch(FetchDescriptor<MonthlyExecutionRecord>())

        var removed = 0
        for (_, group) in groups where group.count > 1 {
            // group is already sorted most-recently-modified first (from fetch)
            let survivor = group[0]
            let duplicateIDs = Set(group.dropFirst().map(\.id))
            for duplicate in group.dropFirst() {
                // Merge relationship-based references
                for allocation in (duplicate.allocations ?? []) {
                    allocation.goal = survivor
                }
                for history in (duplicate.allocationHistory ?? []) {
                    history.goal = survivor
                    history.goalId = survivor.id
                }

                // Rewrite UUID-based references: MonthlyPlan.goalId
                for plan in allPlans where plan.goalId == duplicate.id {
                    plan.goalId = survivor.id
                }

                // Rewrite UUID-based references: MonthlyExecutionRecord.trackedGoalIds
                for record in allExecRecords {
                    let ids = record.goalIds
                    if ids.contains(duplicate.id) {
                        var updated = ids.filter { !duplicateIDs.contains($0) }
                        if !updated.contains(survivor.id) {
                            updated.append(survivor.id)
                        }
                        if let encoded = try? JSONEncoder().encode(updated) {
                            record.trackedGoalIds = encoded
                        }
                    }
                }

                context.delete(duplicate)
                removed += 1
            }
        }

        if removed > 0 {
            logger.debug("Goal: removed \(removed) duplicate(s)")
        }
        return removed
    }

    /// Deduplicate Transaction by externalId (for on-chain transactions).
    /// Manual transactions without externalId are never considered duplicates.
    @discardableResult
    func deduplicateTransactions(in context: ModelContext) throws -> Int {
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        var groups: [TransactionDeduplicationKey: [Transaction]] = [:]
        for transaction in transactions {
            guard let externalID = transaction.externalId,
                  !externalID.isEmpty
            else {
                continue
            }
            let key = TransactionDeduplicationKey(
                assetID: transaction.asset?.id,
                externalID: externalID
            )
            groups[key, default: []].append(transaction)
        }

        var plans: [TransactionDeduplicationPlan] = []
        for (key, group) in groups
            .filter({ $0.value.count > 1 })
            .sorted(by: { $0.key.sortKey < $1.key.sortKey })
        {
            let ordered = group.sorted { lhs, rhs in
                if lhs.date != rhs.date {
                    return lhs.date > rhs.date
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            guard let survivor = ordered.first else { continue }
            let transactionIDs = Set(ordered.map(\.id))
            let linkedHistories = histories.filter { history in
                guard let sourceTransactionID = history.sourceTransactionId
                else {
                    return false
                }
                return transactionIDs.contains(sourceTransactionID)
            }
            let linkedTransactionIDs = Set(
                linkedHistories.compactMap(\.sourceTransactionId)
            )

            guard linkedTransactionIDs.count <= 1 else {
                throw DeduplicationError
                    .conflictingTransactionAllocationProvenance(
                        externalID: key.externalID,
                        transactionIDs: Array(transactionIDs),
                        linkedTransactionIDs: Array(linkedTransactionIDs)
                    )
            }
            if !linkedHistories.isEmpty {
                let financialFingerprints = Set(
                    ordered.map(TransactionAllocationFingerprint.init)
                )
                guard financialFingerprints.count == 1 else {
                    throw DeduplicationError
                        .conflictingTransactionAllocationProvenance(
                            externalID: key.externalID,
                            transactionIDs: Array(transactionIDs),
                            linkedTransactionIDs: Array(linkedTransactionIDs)
                        )
                }
            }

            plans.append(
                TransactionDeduplicationPlan(
                    survivor: survivor,
                    duplicates: Array(ordered.dropFirst()),
                    historiesToRekey: linkedHistories.filter {
                        $0.sourceTransactionId != survivor.id
                    }
                )
            )
        }

        // Every group is validated before this point. Apply the complete plan
        // only after no conflicting financial/provenance evidence remains.
        for plan in plans {
            for history in plan.historiesToRekey {
                history.sourceTransactionId = plan.survivor.id
            }
            for duplicate in plan.duplicates {
                context.delete(duplicate)
            }
        }

        let removed = plans.reduce(0) { $0 + $1.duplicates.count }
        if removed > 0 {
            logger.debug("Transaction: removed \(removed) duplicate(s)")
        }
        return removed
    }

    private func postSharedGoalRepairIfNeeded(in context: ModelContext) {
        let goalIDs = (try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { goal in
            goal.lifecycleStatusRawValue == "active"
        })))?.map(\.id) ?? []
        guard goalIDs.isEmpty == false else { return }
        NotificationCenter.default.post(
            name: .sharedGoalDataDidChange,
            object: nil,
            userInfo: [
                "affectedGoalIDs": goalIDs,
                "reason": "importOrRepair"
            ]
        )
    }

    /// Deduplicate MonthlyPlan by (monthLabel, goalId). Keep the most recently modified.
    @discardableResult
    func deduplicateMonthlyPlans(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<MonthlyPlan>(
            sortBy: [SortDescriptor(\.lastModifiedDate, order: .reverse)]
        )
        let plans = try context.fetch(descriptor)

        var seen = Set<String>()
        var removed = 0

        for plan in plans {
            let key = "\(plan.monthLabel)|\(plan.goalId)"
            if seen.contains(key) {
                context.delete(plan)
                removed += 1
            } else {
                seen.insert(key)
            }
        }

        if removed > 0 {
            logger.debug("MonthlyPlan: removed \(removed) duplicate(s)")
        }
        return removed
    }

    /// Deduplicate only provably redundant MonthlyExecutionRecords.
    ///
    /// A newer empty CloudKit draft must never replace an executing/closed
    /// record that owns immutable snapshots or completion history. Multiple
    /// evidence-bearing records are ambiguous and require an explicit repair,
    /// so the full deduplication transaction fails closed.
    @discardableResult
    func deduplicateExecutionRecords(in context: ModelContext) throws -> Int {
        let records = try context.fetch(FetchDescriptor<MonthlyExecutionRecord>())
        let groups = Dictionary(grouping: records, by: \.monthLabel)
        var recordsToDelete: [MonthlyExecutionRecord] = []

        // Build the complete repair plan before mutating the context so direct
        // callers also get fail-closed behavior, not just runFullDeduplication.
        for (monthLabel, group) in groups where group.count > 1 {
            let evidenceBearing = group.filter { !isEvidenceFreeDraft($0) }

            if evidenceBearing.count > 1 {
                throw DeduplicationError.conflictingExecutionEvidence(
                    monthLabel: monthLabel,
                    recordIDs: evidenceBearing.map(\.id)
                )
            }

            if let authoritative = evidenceBearing.first {
                recordsToDelete.append(contentsOf: group.filter {
                    $0.id != authoritative.id && isEvidenceFreeDraft($0)
                })
                continue
            }

            let fingerprints = Set(group.map(evidenceFreeFingerprint))
            guard fingerprints.count == 1 else {
                throw DeduplicationError.conflictingExecutionEvidence(
                    monthLabel: monthLabel,
                    recordIDs: group.map(\.id)
                )
            }

            let sorted = group.sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt > rhs.createdAt
            }
            recordsToDelete.append(contentsOf: sorted.dropFirst())
        }

        for record in recordsToDelete {
            context.delete(record)
        }

        if !recordsToDelete.isEmpty {
            logger.debug(
                "MonthlyExecutionRecord: removed \(recordsToDelete.count) evidence-free duplicate(s)"
            )
        }
        return recordsToDelete.count
    }

    /// CompletedExecution is append-only lifecycle evidence. A month can have
    /// multiple legitimate snapshots after completion, undo, and re-completion,
    /// so monthLabel is not a deduplication identity.
    @discardableResult
    func deduplicateCompletedExecutions(in context: ModelContext) throws -> Int {
        _ = try context.fetch(FetchDescriptor<CompletedExecution>())
        return 0
    }

    /// Deduplicate Asset by (currency, chainId, address). Keep the one with more transactions.
    /// Merges transactions and allocations from duplicates into the survivor.
    @discardableResult
    func deduplicateAssets(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Asset>()
        let assets = try context.fetch(descriptor)

        // Group by logical key
        var groups: [AddressedAssetPersistenceIdentity: [Asset]] = [:]
        for asset in assets {
            // Addressless rows are independent user accounts. They have no
            // provider identity and must never be coalesced by currency alone.
            guard let identity = AssetPersistenceIdentityPolicy.addressedIdentity(for: asset) else {
                continue
            }
            groups[identity, default: []].append(asset)
        }

        var removed = 0

        for (_, group) in groups where group.count > 1 {
            // Keep the asset with the most transactions
            let sorted = group.sorted { ($0.transactions ?? []).count > ($1.transactions ?? []).count }
            let survivor = sorted[0]
            let duplicates = sorted.dropFirst()

            for duplicate in duplicates {
                // Migrate transactions to survivor
                for transaction in (duplicate.transactions ?? []) {
                    transaction.asset = survivor
                }
                // Migrate allocations to survivor
                for allocation in (duplicate.allocations ?? []) {
                    allocation.asset = survivor
                }
                // Migrate allocation history to survivor
                for history in (duplicate.allocationHistory ?? []) {
                    history.asset = survivor
                    history.assetId = survivor.id
                }
                // Materialize inverse-relationship moves before applying the
                // duplicate asset's cascade delete.
                context.processPendingChanges()
                context.delete(duplicate)
                removed += 1
            }
        }

        if removed > 0 {
            logger.debug("Asset: removed \(removed) duplicate(s)")
        }
        return removed
    }

    /// Deduplicate AssetAllocation by (asset.id, goal.id). Allocation records
    /// from distinct duplicate assets are additive; dropping all but the max
    /// silently loses financial state.
    @discardableResult
    func deduplicateAssetAllocations(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<AssetAllocation>()
        let allocations = try context.fetch(descriptor)

        var groups: [String: [AssetAllocation]] = [:]
        for allocation in allocations {
            guard let assetId = allocation.asset?.id,
                  let goalId = allocation.goal?.id else { continue }
            let key = "\(assetId)|\(goalId)"
            groups[key, default: []].append(allocation)
        }

        let duplicateGroups = groups.values.filter { $0.count > 1 }

        // Preflight the complete post-merge allocation total per asset before
        // touching any record. If the available balance cannot cover it, the
        // only safe repair is to stop and preserve every original record.
        let affectedAssetIDs = Set(
            duplicateGroups.compactMap { $0.first?.asset?.id }
        )
        var assetsByID: [UUID: Asset] = [:]
        for allocation in allocations {
            if let asset = allocation.asset {
                assetsByID[asset.id] = asset
            }
        }
        for assetID in affectedAssetIDs {
            let plannedTotal = groups
                .filter { $0.key.hasPrefix("\(assetID)|") }
                .values
                .flatMap { $0 }
                .reduce(0) { $0 + max(0, $1.amountValue) }
            guard let asset = assetsByID[assetID] else { continue }
            let available = max(0, asset.currentAmount)
            if plannedTotal > available + 0.000_000_1 {
                throw DeduplicationError.unsafeAllocationMerge(
                    assetID: assetID,
                    requested: plannedTotal,
                    available: available
                )
            }
        }

        var removed = 0
        for group in duplicateGroups {
            let sorted = group.sorted { lhs, rhs in
                if lhs.createdDate == rhs.createdDate {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdDate < rhs.createdDate
            }
            let survivor = sorted[0]
            let mergedAmount = sorted.reduce(0) { $0 + max(0, $1.amountValue) }
            survivor.updateAmount(mergedAmount)
            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
                removed += 1
            }
        }

        if removed > 0 {
            logger.debug("AssetAllocation: removed \(removed) duplicate(s)")
        }
        return removed
    }

    /// Deduplicate AllocationHistory by (assetId, goalId, timestamp, createdAt). Keep one.
    @discardableResult
    func deduplicateAllocationHistory(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<AllocationHistory>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let records = try context.fetch(descriptor)

        var seen = Set<String>()
        var removed = 0

        for record in records {
            let assetId = record.asset?.id.uuidString ?? (record.assetId?.uuidString ?? "nil")
            let goalId = record.goal?.id.uuidString ?? (record.goalId?.uuidString ?? "nil")
            let ts = String(record.timestamp.timeIntervalSince1970)
            let ca = String(record.createdAt.timeIntervalSince1970)
            let key = "\(assetId)|\(goalId)|\(ts)|\(ca)"

            if seen.contains(key) {
                context.delete(record)
                removed += 1
            } else {
                seen.insert(key)
            }
        }

        if removed > 0 {
            logger.debug("AllocationHistory: removed \(removed) duplicate(s)")
        }
        return removed
    }

    private func isEvidenceFreeDraft(
        _ record: MonthlyExecutionRecord
    ) -> Bool {
        record.statusRawValue == MonthlyExecutionRecord.ExecutionStatus.draft.rawValue
            && record.startedAt == nil
            && record.completedAt == nil
            && record.canUndoUntil == nil
            && record.snapshot == nil
            && record.completedExecution == nil
            && (record.completionEvents ?? []).isEmpty
            && (record.plans ?? []).isEmpty
    }

    private func evidenceFreeFingerprint(
        _ record: MonthlyExecutionRecord
    ) -> EvidenceFreeExecutionFingerprint {
        EvidenceFreeExecutionFingerprint(
            monthLabel: record.monthLabel,
            trackedGoalIds: record.trackedGoalIds
        )
    }
}

private struct EvidenceFreeExecutionFingerprint: Hashable {
    let monthLabel: String
    let trackedGoalIds: Data
}
