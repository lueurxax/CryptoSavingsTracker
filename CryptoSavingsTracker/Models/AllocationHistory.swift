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
    @Attribute(.unique) var id: UUID
    var amount: Double
    var timestamp: Date
    var monthLabel: String
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
        self.monthLabel = MonthlyExecutionRecord.monthLabel(from: timestamp)
    }
}
