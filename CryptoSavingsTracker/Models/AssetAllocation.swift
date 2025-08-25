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
    var percentage: Double // Stored as 0.0 to 1.0 (where 1.0 = 100%)
    var createdDate: Date
    var lastModifiedDate: Date

    // Relationships
    var asset: Asset?
    var goal: Goal?

    init(asset: Asset, goal: Goal, percentage: Double) {
        self.id = UUID()
        self.asset = asset
        self.goal = goal
        self.percentage = max(0.0, min(percentage, 1.0)) // Ensure percentage is between 0 and 1
        self.createdDate = Date()
        self.lastModifiedDate = Date()
    }
    
    /// Updates the percentage and modifies the lastModifiedDate
    func updatePercentage(_ newPercentage: Double) {
        self.percentage = max(0.0, min(newPercentage, 1.0))
        self.lastModifiedDate = Date()
    }
    
    /// Computed property to get the percentage as a display value (0-100)
    var displayPercentage: Double {
        return percentage * 100
    }
    
    /// Computed property to calculate the allocated value for this allocation
    func getAllocatedValue(assetTotalValue: Double) -> Double {
        return assetTotalValue * percentage
    }
}