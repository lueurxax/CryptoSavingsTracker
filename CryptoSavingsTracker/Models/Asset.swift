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
    
    @Relationship(deleteRule: .cascade, inverse: \Transaction.asset) var transactions: [Transaction] = []
    @Relationship(deleteRule: .cascade, inverse: \AssetAllocation.asset) var allocations: [AssetAllocation] = []
    
    var manualBalance: Double {
        transactions
            .filter { $0.source == .manual }
            .reduce(0) { $0 + $1.amount }
    }

    /// Best-effort on-chain balance from cache (0 if unknown).
    /// This avoids blocking UI and prevents allocation math from ignoring on-chain funds.
    var cachedOnChainBalance: Double {
        guard
            let chainId,
            let address,
            !chainId.isEmpty,
            !address.isEmpty
        else {
            return 0
        }

        let cacheKey = BalanceCacheManager.balanceCacheKey(chainId: chainId, address: address, symbol: currency)
        return BalanceCacheManager.shared.getFallbackBalance(for: cacheKey) ?? 0
    }

    // For synchronous access, return the best-known total (manual + cached on-chain).
    // For the freshest totals, use `AssetViewModel.getCurrentAmount(for:)` / `AssetViewModel.refreshBalances()`.
    var currentAmount: Double {
        manualBalance + cachedOnChainBalance
    }
    
    // MARK: - Allocation Helper Methods
    
    /// Sum of allocated amounts in asset currency.
    var totalAllocatedAmount: Double {
        allocations.reduce(0) { $0 + max(0, $1.amountValue) }
    }
    
    /// Balance minus allocated total (can be negative if over-allocated).
    var allocationDelta: Double {
        currentAmount - totalAllocatedAmount
    }

    /// Remaining unallocated amount (never negative)
    var unallocatedAmount: Double {
        max(0, allocationDelta)
    }
    
    /// Check if the asset is fully allocated
    var isFullyAllocated: Bool {
        abs(allocationDelta) <= 0.0000001
    }

    /// Check if allocations exceed balance.
    var isOverAllocated: Bool {
        allocationDelta < -0.0000001
    }
    
    /// Get all goals this asset is allocated to
    var allocatedGoals: [Goal] {
        allocations.compactMap { $0.goal }
    }
    
    /// Get the allocation amount for a specific goal
    func getAllocationAmount(for goal: Goal) -> Double {
        guard let allocation = allocations.first(where: { $0.goal?.id == goal.id }) else { return 0.0 }
        return allocation.amountValue
    }
    
    /// Get the allocated value for a specific goal (capped by asset total)
    func getAllocatedValue(for goal: Goal, totalAssetValue: Double) -> Double {
        let amount = getAllocationAmount(for: goal)
        return min(amount, totalAssetValue)
    }
}
