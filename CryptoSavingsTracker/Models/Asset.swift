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
    @Relationship(deleteRule: .cascade, inverse: \Contribution.asset) var contributions: [Contribution] = []
    
    var manualBalance: Double {
        transactions.reduce(0) { $0 + $1.amount }
    }
    
    // For synchronous access, return manual balance only
    // For accurate totals including on-chain balance, use AssetViewModel
    var currentAmount: Double {
        manualBalance
    }
    
    // MARK: - Allocation Helper Methods
    
    /// Sum of allocated amounts in asset currency (using fixed amounts, falling back to percentage if needed)
    var totalAllocatedAmount: Double {
        let balance = currentAmount
        return allocations.reduce(0) { partial, allocation in
            let allocAmount = allocation.amount > 0
            ? allocation.amount
            : allocation.percentage * balance
            return partial + allocAmount
        }
    }
    
    /// Remaining unallocated amount (never negative)
    var unallocatedAmount: Double {
        max(0, currentAmount - totalAllocatedAmount)
    }
    
    /// Check if the asset is fully allocated
    var isFullyAllocated: Bool {
        unallocatedAmount <= 0.0000001
    }
    
    /// Get all goals this asset is allocated to
    var allocatedGoals: [Goal] {
        allocations.compactMap { $0.goal }
    }
    
    /// Get the allocation amount for a specific goal
    func getAllocationAmount(for goal: Goal) -> Double {
        guard let allocation = allocations.first(where: { $0.goal?.id == goal.id }) else { return 0.0 }
        if allocation.amount > 0 { return allocation.amount }
        return allocation.percentage * currentAmount
    }
    
    /// Get the allocated value for a specific goal (capped by asset total)
    func getAllocatedValue(for goal: Goal, totalAssetValue: Double) -> Double {
        let amount = getAllocationAmount(for: goal)
        return min(amount, totalAssetValue)
    }
}
