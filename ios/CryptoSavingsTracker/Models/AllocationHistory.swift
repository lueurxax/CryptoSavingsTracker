//
//  AllocationHistory.swift
//  CryptoSavingsTracker
//
//  Records allocation amount changes over time for execution tracking.
//

import SwiftData
import Foundation

@Model
final class AllocationHistory {
    var id: UUID = UUID()
    var amount: Double = 0.0
    var timestamp: Date = Date()
    /// Creation time for tie-breaking when multiple snapshots share the same `timestamp`.
    var createdAt: Date = Date()
    var monthLabel: String = ""
    var assetId: UUID?
    var goalId: UUID?
    /// Durable link for allocation targets created automatically from a
    /// transaction. Manual allocation history keeps this nil.
    var sourceTransactionId: UUID?
    /// Exact allocation target immediately before `sourceTransactionId` was
    /// applied. This is required because a withdrawal clamped at zero cannot
    /// be inverted from the post-transaction amount alone.
    var sourcePreviousAmount: Double?

    // Relationships
    @Relationship var asset: Asset?
    @Relationship var goal: Goal?

    init(
        asset: Asset,
        goal: Goal,
        amount: Double,
        timestamp: Date = Date(),
        sourceTransactionId: UUID? = nil,
        sourcePreviousAmount: Double? = nil
    ) {
        self.id = UUID()
        self.assetId = asset.id
        self.goalId = goal.id
        self.asset = asset
        self.goal = goal
        self.amount = amount
        self.timestamp = timestamp
        self.createdAt = Date()
        self.monthLabel = MonthlyExecutionRecord.monthLabel(from: timestamp)
        self.sourceTransactionId = sourceTransactionId
        self.sourcePreviousAmount = sourcePreviousAmount
    }

    var effectiveCreatedAt: Date {
        createdAt
    }
}
