//
//  Item.swift
//  CryptoSavingsTracker
//
//  Created by user on 25/07/2025.
//

import SwiftData
import Foundation
import Combine

@Model
final class Goal: ObservableObject {
    init(name: String, currency: String, targetAmount: Double, deadline: Date, startDate: Date = Date(), frequency: ReminderFrequency = .weekly) {
        self.id = UUID()
        self.name = name
        self.currency = currency
        self.targetAmount = targetAmount
        self.deadline = deadline
        self.startDate = startDate
        self.frequency = frequency
        self.assets = []
    }

    @Attribute(.unique) var id: UUID
    var name: String
    var currency: String = "USD"  // Default value for migration
    var targetAmount: Double = 0.0  // Default value for migration
    var deadline: Date
    var startDate: Date = Date()  // Default value for migration
    var frequency: ReminderFrequency {
        get {
            return _frequency ?? .weekly
        }
        set {
            _frequency = newValue
        }
    }
    
    private var _frequency: ReminderFrequency?
    
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
    
    var currentTotal: Double {
        var total: Double = 0
        for asset in assets {
            let assetValue = asset.currentAmount
            // For synchronous calculation, assume same currency or 1:1 rate
            total += assetValue
        }
        return total
    }
    
    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(currentTotal / targetAmount, 1.0)
    }
    
    var reminderDates: [Date] {
        var dates: [Date] = []
        var currentDate = startDate
        let calendar = Calendar.current
        
        while currentDate <= deadline {
            dates.append(currentDate)
            guard let nextDate = calendar.date(byAdding: frequency.dateComponents, to: currentDate) else {
                break
            }
            currentDate = nextDate
        }
        
        return dates
    }
    
    var remainingDates: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return reminderDates.filter { Calendar.current.startOfDay(for: $0) >= today }
    }
    
    func getSuggestedDeposit() async -> Double {
        let remaining = remainingDates.count
        guard remaining > 0, targetAmount > 0 else { return 0 }
        
        let current = await getCurrentTotal()
        let remainingAmount = max(targetAmount - current, 0)
        return remainingAmount / Double(remaining)
    }
    
    var nextReminder: Date? {
        return remainingDates.first
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
