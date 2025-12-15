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
    // Fixed amount allocated in the asset's native currency.
    var amount: Double
    var createdDate: Date
    var lastModifiedDate: Date

    // Relationships
    var asset: Asset?
    var goal: Goal?

    init(asset: Asset, goal: Goal, amount: Double) {
        self.id = UUID()
        self.asset = asset
        self.goal = goal
        self.amount = max(0.0, amount)
        self.createdDate = Date()
        self.lastModifiedDate = Date()
    }
    
    /// Updates the fixed amount.
    func updateAmount(_ newAmount: Double) {
        self.amount = max(0.0, newAmount)
        self.lastModifiedDate = Date()
    }

    var amountValue: Double {
        amount
    }
    
    /// Computed property to get the percentage as a display value (0-100).
    var displayPercentage: Double {
        let currentBalance = asset?.currentAmount ?? 0
        let pct = currentBalance > 0 ? amountValue / currentBalance : 0
        return pct * 100
    }
    
    /// Allocated value from a given asset total.
    func getAllocatedValue(assetTotalValue: Double) -> Double {
        min(amountValue, assetTotalValue)
    }
}
