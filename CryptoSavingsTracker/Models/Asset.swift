//
//  Asset.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 11/08/2025.
//

import SwiftData
import Foundation

@Model
final class Asset {
    init(currency: String, address: String? = nil, chainId: String? = nil) {
        self.id = UUID()
        self.currency = currency
        self.transactions = []
        self.address = address
        self.chainId = chainId
        self.allocations = []
    }

    @Attribute(.unique) var id: UUID
    var currency: String
    var address: String?
    var chainId: String?
    
    @Relationship(deleteRule: .cascade) var transactions: [Transaction] = []
    @Relationship(deleteRule: .cascade) var allocations: [AssetAllocation] = []
    
    var manualBalance: Double {
        transactions.reduce(0) { $0 + $1.amount }
    }
    
    // For synchronous access, return manual balance only
    // For accurate totals including on-chain balance, use AssetViewModel
    var currentAmount: Double {
        manualBalance
    }
    
    // MARK: - Allocation Helper Methods
    
    /// Get the total percentage allocated across all goals
    var totalAllocatedPercentage: Double {
        allocations.reduce(0) { $0 + $1.percentage }
    }
    
    /// Get the remaining unallocated percentage
    var unallocatedPercentage: Double {
        max(0, 1.0 - totalAllocatedPercentage)
    }
    
    /// Check if the asset is fully allocated
    var isFullyAllocated: Bool {
        totalAllocatedPercentage >= 1.0
    }
    
    /// Get all goals this asset is allocated to
    var allocatedGoals: [Goal] {
        allocations.compactMap { $0.goal }
    }
    
    /// Get the allocation percentage for a specific goal
    func getAllocationPercentage(for goal: Goal) -> Double {
        return allocations.first { $0.goal?.id == goal.id }?.percentage ?? 0.0
    }
    
    /// Get the allocated value for a specific goal
    func getAllocatedValue(for goal: Goal, totalAssetValue: Double) -> Double {
        let percentage = getAllocationPercentage(for: goal)
        return totalAssetValue * percentage
    }
}