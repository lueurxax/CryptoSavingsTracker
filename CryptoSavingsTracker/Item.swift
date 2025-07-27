//
//  Item.swift
//  CryptoSavingsTracker
//
//  Created by user on 25/07/2025.
//

import SwiftData
import Foundation

@Model
final class Goal {
    init(name: String, currency: String, targetAmount: Double, deadline: Date) {
        self.id = UUID()
        self.name = name
        self.currency = currency
        self.targetAmount = targetAmount
        self.deadline = deadline
        self.assets = []
    }

    @Attribute(.unique) var id: UUID
    var name: String
    var currency: String = "USD"  // Default value for migration
    var targetAmount: Double = 0.0  // Default value for migration
    var deadline: Date
    
    @Relationship(deleteRule: .cascade) var assets: [Asset] = []
    
    var daysRemaining: Int {
        let components = Calendar.current.dateComponents([.day], from: Date(), to: deadline)
        return max(components.day ?? 0, 0)
    }
    
    func getCurrentTotal() async -> Double {
        var total: Double = 0
        for asset in assets {
            let assetValue = asset.currentAmount
            if asset.currency == currency {
                total += assetValue
            } else {
                do {
                    let rate = try await ExchangeRateService.shared.fetchRate(from: asset.currency, to: currency)
                    total += assetValue * rate
                } catch {
                    total += assetValue
                }
            }
        }
        return total
    }
    
    func getProgress() async -> Double {
        guard targetAmount > 0 else { return 0 }
        let current = await getCurrentTotal()
        return min(current / targetAmount, 1.0)
    }
}

@Model
final class Asset {
    init(currency: String, goal: Goal) {
        self.id = UUID()
        self.currency = currency
        self.goal = goal
        self.transactions = []
    }

    @Attribute(.unique) var id: UUID
    var currency: String
    
    @Relationship(deleteRule: .cascade) var transactions: [Transaction] = []
    @Relationship var goal: Goal
    
    var currentAmount: Double {
        transactions.reduce(0) { $0 + $1.amount }
    }
}

@Model
final class Transaction {
    init(amount: Double, asset: Asset) {
        self.id = UUID()
        self.amount = amount
        self.date = Date()
        self.asset = asset
    }

    @Attribute(.unique) var id: UUID
    var amount: Double
    var date: Date
    
    @Relationship var asset: Asset
}
