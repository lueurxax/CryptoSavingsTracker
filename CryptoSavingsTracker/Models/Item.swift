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
    
    // Archive and modification tracking
    var archivedDate: Date?
    var lastModifiedDate: Date = Date()
    var reminderFrequency: String? // For notifications
    var reminderTime: Date? // For notification timing
    
    @Relationship(deleteRule: .cascade) var assets: [Asset] = []
    
    var daysRemaining: Int {
        let components = Calendar.current.dateComponents([.day], from: Date(), to: deadline)
        return max(components.day ?? 0, 0)
    }
    
    // Simple computed properties for basic UI display
    // For accurate values with currency conversion, use GoalViewModel
    var currentTotal: Double {
        assets.reduce(0) { $0 + $1.manualBalance }
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
    
    
    var nextReminder: Date? {
        return remainingDates.first
    }
    
    var suggestedDailyDeposit: Double {
        let remaining = remainingDates.count
        guard remaining > 0, targetAmount > 0 else { return 0 }
        
        let remainingAmount = max(targetAmount - currentTotal, 0)
        return remainingAmount / Double(remaining)
    }
    
    // Async methods for backward compatibility - these delegate to GoalViewModel
    @MainActor
    func getCurrentTotal() async -> Double {
        // Create a temporary ViewModel for this calculation
        // In production, views should use GoalViewModel directly
        let viewModel = GoalViewModel(goal: self)
        await viewModel.refreshValues()
        return viewModel.currentTotal
    }
    
    @MainActor
    func getProgress() async -> Double {
        let total = await getCurrentTotal()
        guard targetAmount > 0 else { return 0 }
        return min(total / targetAmount, 1.0)
    }
    
    @MainActor
    func getSuggestedDeposit() async -> Double {
        let total = await getCurrentTotal()
        let remaining = remainingDates.count
        guard remaining > 0, targetAmount > 0 else { return 0 }
        
        let remainingAmount = max(targetAmount - total, 0)
        return remainingAmount / Double(remaining)
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
    
    // Async method for backward compatibility - delegates to AssetViewModel
    @MainActor
    func getCurrentAmount() async -> Double {
        return await AssetViewModel.getCurrentAmount(for: self)
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
