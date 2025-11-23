//
//  AssetAllocation.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 25/08/2025.
//

import SwiftData
import Foundation

@Model
final class AssetAllocation {
    @Attribute(.unique) var id: UUID
    // Legacy percentage (0.0 - 1.0). Kept for migration compatibility.
    var percentage: Double
    // Fixed amount allocated in the asset's native currency.
    var amount: Double = 0.0
    var createdDate: Date
    var lastModifiedDate: Date

    // Relationships
    var asset: Asset?
    var goal: Goal?

    init(asset: Asset, goal: Goal, amount: Double) {
        let normalizedAmount = max(0.0, amount)
        let currentBalance = asset.currentAmount
        let derivedPercentage = currentBalance > 0 ? normalizedAmount / currentBalance : 0

        self.id = UUID()
        self.asset = asset
        self.goal = goal
        self.amount = normalizedAmount
        self.percentage = max(0.0, min(derivedPercentage, 1.0))
        self.createdDate = Date()
        self.lastModifiedDate = Date()
    }
    
    /// Legacy initializer preserving percentage call sites. Converts to fixed amount using current balance.
    convenience init(asset: Asset, goal: Goal, percentage: Double) {
        let pct = max(0.0, min(percentage, 1.0))
        let amount = asset.currentAmount * pct
        self.init(asset: asset, goal: goal, amount: amount)
        self.percentage = pct
    }
    
    /// Updates the fixed amount and refreshes the derived percentage for legacy paths.
    func updateAmount(_ newAmount: Double) {
        self.amount = max(0.0, newAmount)
        let currentBalance = asset?.currentAmount ?? 0
        let derivedPercentage = currentBalance > 0 ? self.amount / currentBalance : 0
        self.percentage = max(0.0, min(derivedPercentage, 1.0))
        self.lastModifiedDate = Date()
    }
    
    /// Computed property to get the percentage as a display value (0-100) for legacy UI.
    var displayPercentage: Double {
        let currentBalance = asset?.currentAmount ?? 0
        let pct = currentBalance > 0 ? amount / currentBalance : percentage
        return pct * 100
    }
    
    /// Allocated value from a given asset total, preferring fixed amount and falling back to legacy percentage.
    func getAllocatedValue(assetTotalValue: Double) -> Double {
        if amount > 0 {
            return min(amount, assetTotalValue)
        }
        return assetTotalValue * percentage
    }
}
