//
//  Goal.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 11/08/2025.
//

import SwiftData
import Foundation

@Model
final class Goal {
    init(name: String, currency: String, targetAmount: Double, deadline: Date, startDate: Date = Date(), frequency: ReminderFrequency = .weekly, emoji: String? = nil, description: String? = nil, link: String? = nil) {
        self.id = UUID()
        self.name = name
        self.currency = currency
        self.targetAmount = targetAmount
        self.deadline = deadline
        self.startDate = startDate
        self.allocations = nil
        self.reminderFrequency = frequency.rawValue
        self.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
        self.emoji = emoji
        self.goalDescription = description
        self.link = link
    }

    var id: UUID = UUID()
    var name: String = ""
    var currency: String = "USD"
    var targetAmount: Double = 0.0
    var deadline: Date = Date()
    var startDate: Date = Date()
    
    // Lifecycle and modification tracking
    var lifecycleStatusRawValue: String = GoalLifecycleStatus.active.rawValue
    var lifecycleStatusChangedAt: Date?
    var lastModifiedDate: Date = Date()
    
    // Reminder properties
    var reminderFrequency: String?
    var reminderTime: Date?
    var firstReminderDate: Date?
    
    // Visual and metadata properties
    var emoji: String?
    var goalDescription: String?
    var link: String?
    
    @Relationship(deleteRule: .cascade, inverse: \AssetAllocation.goal) var allocations: [AssetAllocation]?
    @Relationship(deleteRule: .nullify, inverse: \AllocationHistory.goal) var allocationHistory: [AllocationHistory]?

    // MARK: - Computed Properties

    var lifecycleStatus: GoalLifecycleStatus {
        get { GoalLifecycleStatus(rawValue: lifecycleStatusRawValue) ?? .active }
        set { lifecycleStatusRawValue = newValue.rawValue }
    }
    
    var manualTotal: Double {
        (allocations ?? []).reduce(0) { result, allocation in
            guard let asset = allocation.asset else { return result }
            let allocatedPortion = min(max(0, allocation.amountValue), asset.manualBalance)
            return result + allocatedPortion
        }
    }
    
    var manualProgress: Double {
        targetAmount > 0 ? min(manualTotal / targetAmount, 1.0) : 0
    }
    
    var daysRemaining: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: deadline)
        return max(components.day ?? 0, 0)
    }
    
    var isExpired: Bool {
        return deadline < Date()
    }
    
    var isAchieved: Bool {
        return manualTotal >= targetAmount
    }
    
    var isReminderEnabled: Bool {
        return reminderFrequency != nil && reminderTime != nil
    }
    
    var status: String {
        if isAchieved {
            return "Achieved"
        } else if isExpired {
            return "Expired"
        } else if daysRemaining < 7 {
            return "Urgent"
        } else if manualProgress > 0.7 {
            return "On Track"
        } else if manualProgress > 0.3 {
            return "In Progress"
        } else {
            return "Just Started"
        }
    }
    
    var currentTotal: Double {
        return manualTotal
    }
    
    var progress: Double {
        return manualProgress
    }
    
    var frequency: ReminderFrequency? {
        guard let rawValue = reminderFrequency else { return nil }
        return ReminderFrequency(rawValue: rawValue)
    }
    
    var reminderDates: [Date] {
        guard let frequency = frequency,
              let _ = reminderTime else { return [] }
        
        var dates: [Date] = []
        var currentDate = firstReminderDate ?? startDate
        
        while dates.count < 100 {
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
    
    // Helper for smart emoji suggestions
    static func suggestEmoji(for goalName: String) -> String? {
        let lowercasedName = goalName.lowercased()
        
        // Common goal categories and their emojis
        let emojiMap: [(keywords: [String], emoji: String)] = [
            (["house", "home", "apartment", "mortgage", "property"], "🏠"),
            (["car", "vehicle", "auto", "tesla", "bmw", "mercedes"], "🚗"),
            (["travel", "vacation", "trip", "holiday", "tour"], "✈️"),
            (["education", "college", "university", "course", "degree", "school"], "🎓"),
            (["wedding", "marriage", "engagement"], "💒"),
            (["baby", "child", "family"], "👶"),
            (["phone", "iphone", "samsung", "mobile"], "📱"),
            (["computer", "laptop", "macbook", "pc", "desktop"], "💻"),
            (["gaming", "playstation", "xbox", "nintendo", "console"], "🎮"),
            (["watch", "rolex", "timepiece"], "⌚"),
            (["camera", "photography", "canon", "nikon"], "📷"),
            (["bike", "bicycle", "cycling"], "🚴"),
            (["gym", "fitness", "workout", "health"], "💪"),
            (["business", "startup", "company", "investment"], "💼"),
            (["retirement", "pension", "future"], "🏖️"),
            (["emergency", "fund", "safety", "backup"], "🛡️"),
            (["gift", "present", "birthday", "christmas"], "🎁"),
            (["music", "guitar", "piano", "instrument"], "🎵"),
            (["art", "painting", "drawing"], "🎨"),
            (["boat", "yacht", "sailing"], "⛵"),
            (["crypto", "bitcoin", "ethereum", "investment"], "₿"),
            (["stock", "trading", "market"], "📈"),
            (["save", "saving", "money", "cash"], "💰")
        ]
        
        for (keywords, emoji) in emojiMap {
            if keywords.contains(where: { lowercasedName.contains($0) }) {
                return emoji
            }
        }
        
        // Default fallback
        return "🎯"
    }
    
    var suggestedDailyDeposit: Double {
        // Simple calculation based on days remaining and manual total
        guard daysRemaining > 0, targetAmount > 0 else { return 0 }
        let remainingAmount = max(targetAmount - manualTotal, 0)
        return remainingAmount / Double(daysRemaining)
    }
    
    // MARK: - Allocation Helper Methods
    
    /// Get all assets allocated to this goal
    var allocatedAssets: [Asset] {
        (allocations ?? []).compactMap { $0.asset }
    }
    
    /// Get unique assets (without duplicates) allocated to this goal
    var uniqueAllocatedAssets: [Asset] {
        let assets = allocatedAssets
        var uniqueAssets: [Asset] = []
        var seenIds: Set<UUID> = []
        
        for asset in assets {
            if !seenIds.contains(asset.id) {
                uniqueAssets.append(asset)
                seenIds.insert(asset.id)
            }
        }
        
        return uniqueAssets
    }
    
    /// Get the total amount allocated from a specific asset
    func getAllocationAmount(from asset: Asset) -> Double {
        guard let allocation = (allocations ?? []).first(where: { $0.asset?.id == asset.id }) else { return 0.0 }
        return allocation.amountValue
    }
    
    /// Get the allocated value from a specific asset (capped by asset total)
    func getAllocatedValue(from asset: Asset, totalAssetValue: Double) -> Double {
        let amount = getAllocationAmount(from: asset)
        return min(amount, totalAssetValue)
    }
    
    /// Get allocation breakdown showing asset and amount pairs
    var allocationBreakdown: [(asset: Asset, amount: Double)] {
        return (allocations ?? []).compactMap { allocation in
            guard let asset = allocation.asset else { return nil }
            return (asset: asset, amount: allocation.amountValue)
        }
    }
    
    // MARK: - Note on Business Logic
    // Business logic has been moved to ViewModels (GoalViewModel, AssetViewModel)
    // This ensures proper separation of concerns and avoids circular dependencies
    // For calculations use: GoalViewModel.getCurrentTotal(), etc.
}
