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
    init(currency: String, goal: Goal, address: String? = nil, chainId: String? = nil) {
        self.id = UUID()
        self.currency = currency
        self.goal = goal
        self.transactions = []
        self.address = address
        self.chainId = chainId
    }

    @Attribute(.unique) var id: UUID
    var currency: String
    var address: String?
    var chainId: String?
    
    @Relationship(deleteRule: .cascade) var transactions: [Transaction] = []
    @Relationship var goal: Goal
    
    var manualBalance: Double {
        transactions.reduce(0) { $0 + $1.amount }
    }
    
    // For synchronous access, return manual balance only
    // For accurate totals including on-chain balance, use AssetViewModel
    var currentAmount: Double {
        manualBalance
    }
}