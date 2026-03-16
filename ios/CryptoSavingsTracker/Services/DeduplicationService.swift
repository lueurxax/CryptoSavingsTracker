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

@MainActor
final class DeduplicationService {

    private let logger = Logger(subsystem: "xax.CryptoSavingsTracker", category: "deduplication")

    // MARK: - Full Deduplication

    func runFullDeduplication(in context: ModelContext) async throws {
        logger.info("Starting full deduplication pass")
        var totalRemoved = 0

        totalRemoved += try deduplicateMonthlyPlans(in: context)
        totalRemoved += try deduplicateExecutionRecords(in: context)
        totalRemoved += try deduplicateCompletedExecutions(in: context)
        totalRemoved += try deduplicateAssets(in: context)
        totalRemoved += try deduplicateAssetAllocations(in: context)
        totalRemoved += try deduplicateAllocationHistory(in: context)

        if totalRemoved > 0 {
            try context.save()
            logger.info("Deduplication complete: removed \(totalRemoved) duplicate(s)")
        } else {
            logger.info("Deduplication complete: no duplicates found")
        }
    }

    // MARK: - Per-Entity Deduplication

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

    /// Deduplicate MonthlyExecutionRecord by monthLabel. Keep the most recently created.
    @discardableResult
    func deduplicateExecutionRecords(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<MonthlyExecutionRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let records = try context.fetch(descriptor)

        var seen = Set<String>()
        var removed = 0

        for record in records {
            if seen.contains(record.monthLabel) {
                context.delete(record)
                removed += 1
            } else {
                seen.insert(record.monthLabel)
            }
        }

        if removed > 0 {
            logger.debug("MonthlyExecutionRecord: removed \(removed) duplicate(s)")
        }
        return removed
    }

    /// Deduplicate CompletedExecution by monthLabel. Keep the most recently completed.
    @discardableResult
    func deduplicateCompletedExecutions(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<CompletedExecution>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        let records = try context.fetch(descriptor)

        var seen = Set<String>()
        var removed = 0

        for record in records {
            if seen.contains(record.monthLabel) {
                context.delete(record)
                removed += 1
            } else {
                seen.insert(record.monthLabel)
            }
        }

        if removed > 0 {
            logger.debug("CompletedExecution: removed \(removed) duplicate(s)")
        }
        return removed
    }

    /// Deduplicate Asset by (currency, chainId, address). Keep the one with more transactions.
    /// Merges transactions and allocations from duplicates into the survivor.
    @discardableResult
    func deduplicateAssets(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Asset>()
        let assets = try context.fetch(descriptor)

        // Group by logical key
        var groups: [String: [Asset]] = [:]
        for asset in assets {
            let currency = asset.currency.uppercased()
            let chain = (asset.chainId ?? "").lowercased()
            let addr = (asset.address ?? "").lowercased()
            let key = "\(currency)|\(chain)|\(addr)"
            groups[key, default: []].append(asset)
        }

        var removed = 0

        for (_, group) in groups where group.count > 1 {
            // Keep the asset with the most transactions
            let sorted = group.sorted { $0.transactions.count > $1.transactions.count }
            let survivor = sorted[0]
            let duplicates = sorted.dropFirst()

            for duplicate in duplicates {
                // Migrate transactions to survivor
                for transaction in duplicate.transactions {
                    transaction.asset = survivor
                }
                // Migrate allocations to survivor
                for allocation in duplicate.allocations {
                    allocation.asset = survivor
                }
                // Migrate allocation history to survivor
                for history in duplicate.allocationHistory {
                    history.asset = survivor
                }
                context.delete(duplicate)
                removed += 1
            }
        }

        if removed > 0 {
            logger.debug("Asset: removed \(removed) duplicate(s)")
        }
        return removed
    }

    /// Deduplicate AssetAllocation by (asset.id, goal.id). Keep the one with higher amount.
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

        var removed = 0

        for (_, group) in groups where group.count > 1 {
            let sorted = group.sorted { $0.amount > $1.amount }
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
}
