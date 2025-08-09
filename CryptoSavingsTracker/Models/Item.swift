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
    init(name: String, currency: String, targetAmount: Double, deadline: Date, startDate: Date = Date(), frequency: ReminderFrequency = .weekly) {
        self.id = UUID()
        self.name = name
        self.currency = currency
        self.targetAmount = targetAmount
        self.deadline = deadline
        self.startDate = startDate
        self.assets = []
        self.reminderFrequency = frequency.rawValue
        self.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
    }

    @Attribute(.unique) var id: UUID
    var name: String
    var currency: String = "USD"
    var targetAmount: Double = 0.0
    var deadline: Date
    var startDate: Date = Date()
    
    // Archive and modification tracking
    var archivedDate: Date?
    var lastModifiedDate: Date = Date()
    
    // Reminder properties
    var reminderFrequency: String?
    var reminderTime: Date?
    var firstReminderDate: Date?
    
    @Relationship(deleteRule: .cascade) var assets: [Asset] = []
    
    // Computed properties for reminder functionality - direct property access for simplicity
    var frequency: ReminderFrequency {
        get {
            guard let freq = reminderFrequency,
                  let reminder = ReminderFrequency(rawValue: freq) else {
                return .weekly
            }
            return reminder
        }
        set {
            reminderFrequency = newValue.rawValue
        }
    }
    
    var isReminderEnabled: Bool {
        return reminderFrequency != nil
    }
    
    // Simple computed properties for basic calculations without external dependencies
    var daysRemaining: Int {
        let components = Calendar.current.dateComponents([.day], from: Date(), to: deadline)
        return max(components.day ?? 0, 0)
    }
    
    // Manual total from all assets - synchronous calculation without external services
    var manualTotal: Double {
        return assets.reduce(0) { total, asset in
            total + asset.transactions.reduce(0) { $0 + $1.amount }
        }
    }
    
    // Manual progress based on manual total - synchronous calculation
    var manualProgress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(manualTotal / targetAmount, 1.0)
    }
    
    // Legacy properties for backward compatibility - these delegate to the new simple calculations
    var currentTotal: Double { manualTotal }
    var progress: Double { manualProgress }
    
    // Simple reminder dates calculation without external service dependencies
    var reminderDates: [Date] {
        var dates: [Date] = []
        var currentDate = startDate
        
        while currentDate <= deadline {
            dates.append(currentDate)
            
            guard let nextDate = Calendar.current.date(byAdding: frequency.dateComponents, to: currentDate) else { break }
            currentDate = nextDate
            
            if currentDate > deadline { break }
        }
        
        return dates
    }
    
    var remainingDates: [Date] {
        let now = Date()
        return reminderDates.filter { $0 > now }
    }
    
    var nextReminder: Date? {
        return remainingDates.first
    }
    
    var suggestedDailyDeposit: Double {
        // Simple calculation based on days remaining and manual total
        guard daysRemaining > 0, targetAmount > 0 else { return 0 }
        let remainingAmount = max(targetAmount - manualTotal, 0)
        return remainingAmount / Double(daysRemaining)
    }
    
    // MARK: - Deprecated Async Methods 
    // These methods have been removed to break circular dependencies
    // Use ViewModels with proper dependency injection instead
    
    @available(*, deprecated, message: "Use GoalViewModel with dependency injection instead")
    @MainActor
    func getCurrentTotal() async -> Double {
        // Return manual total as fallback
        return manualTotal
    }
    
    @available(*, deprecated, message: "Use GoalViewModel with dependency injection instead")
    @MainActor
    func getProgress() async -> Double {
        // Return manual progress as fallback
        return manualProgress
    }
    
    @available(*, deprecated, message: "Use GoalViewModel with dependency injection instead")
    @MainActor
    func getSuggestedDeposit() async -> Double {
        // Return simple calculation as fallback
        return suggestedDailyDeposit
    }
}

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
    
    // MARK: - Deprecated Async Methods
    // This method has been removed to break circular dependencies
    // Use AssetViewModel with proper dependency injection instead
    
    @available(*, deprecated, message: "Use AssetViewModel with dependency injection instead")
    @MainActor
    func getCurrentAmount() async -> Double {
        // Return manual balance as fallback
        return manualBalance
    }
}

@Model
final class Transaction {
    init(amount: Double, asset: Asset, comment: String? = nil) {
        self.id = UUID()
        self.amount = amount
        self.date = Date()
        self.asset = asset
        self.comment = comment
    }

    @Attribute(.unique) var id: UUID
    var amount: Double
    var date: Date
    var comment: String?
    
    @Relationship var asset: Asset
}
