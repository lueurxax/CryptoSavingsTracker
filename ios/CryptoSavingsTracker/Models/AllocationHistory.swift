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
    @Attribute(.unique) var id: UUID = UUID()
    var amount: Double = 0.0
    var timestamp: Date = Date()
    /// Creation time for tie-breaking when multiple snapshots share the same `timestamp`.
    var createdAt: Date?
    var monthLabel: String = ""
    var assetId: UUID?
    var goalId: UUID?

    // Relationships
    var asset: Asset?
    var goal: Goal?

    init(asset: Asset, goal: Goal, amount: Double, timestamp: Date = Date()) {
        self.id = UUID()
        self.assetId = asset.id
        self.goalId = goal.id
        self.asset = asset
        self.goal = goal
        self.amount = amount
        self.timestamp = timestamp
        self.createdAt = Date()
        self.monthLabel = MonthlyExecutionRecord.monthLabel(from: timestamp)
    }

    var effectiveCreatedAt: Date {
        createdAt ?? timestamp
    }
}
