//
//  Item.swift
//  CryptoSavingsTracker
//
//  Created by user on 25/07/2025.
//

import SwiftData
import Foundation

@Model
final class Goal: @unchecked Sendable {
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
    
    var daysRemaining: Int {
        return GoalCalculationService.getDaysRemaining(for: self)
    }
    
    // Simple computed properties for basic UI display - delegates to service layer
    // For accurate values with currency conversion, use getCurrentTotal() async method
    var currentTotal: Double {
        return GoalCalculationService.getManualTotal(for: self)
    }
    
    var progress: Double {
        return GoalCalculationService.getManualProgress(for: self)
    }
    
    var reminderDates: [Date] {
        return GoalCalculationService.getReminderDates(for: self)
    }
    
    var remainingDates: [Date] {
        return GoalCalculationService.getRemainingReminderDates(for: self)
    }
    
    var nextReminder: Date? {
        return GoalCalculationService.getNextReminder(for: self)
    }
    
    var suggestedDailyDeposit: Double {
        // For synchronous access, use manual balance
        let remaining = remainingDates.count
        guard remaining > 0, targetAmount > 0 else { return 0 }
        
        let remainingAmount = max(targetAmount - currentTotal, 0)
        return remainingAmount / Double(remaining)
    }
    
    // Async methods that delegate to GoalCalculationService
    // This maintains API compatibility while properly separating concerns
    @MainActor
    func getCurrentTotal() async -> Double {
        return await GoalCalculationService.getCurrentTotal(for: self)
    }
    
    @MainActor
    func getProgress() async -> Double {
        return await GoalCalculationService.getProgress(for: self)
    }
    
    @MainActor
    func getSuggestedDeposit() async -> Double {
        return await GoalCalculationService.getSuggestedDeposit(for: self)
    }
}

@Model
final class Asset: @unchecked Sendable {
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
    
    // Async method that delegates to AssetViewModel static helper method
    // This maintains API compatibility while properly separating concerns
    @MainActor
    func getCurrentAmount() async -> Double {
        return await AssetViewModel.getCurrentAmount(for: self)
    }
}

@Model
final class Transaction: @unchecked Sendable {
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
