//
//  SchemaVersions.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 25/08/2025.
//

import SwiftData
import Foundation

/// Schema versioning for tracking data model changes
enum SchemaVersion: Int, CaseIterable, Comparable {
    case v1 = 1 // Original schema with direct Asset -> Goal relationship
    case v2 = 2 // New schema with AssetAllocation join table
    
    static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    
    var current: SchemaVersion {
        return SchemaVersion.allCases.last!
    }
    
    static var latest: SchemaVersion {
        return SchemaVersion.allCases.last!
    }
}

/// V1 Schema - Original models (for reference and migration)
enum SchemaV1 {
    @Model
    final class Asset {
        @Attribute(.unique) var id: UUID
        var currency: String
        var address: String?
        var chainId: String?
        
        @Relationship(deleteRule: .cascade) var transactions: [Transaction] = []
        @Relationship var goal: Goal
        
        init(currency: String, goal: Goal, address: String? = nil, chainId: String? = nil) {
            self.id = UUID()
            self.currency = currency
            self.goal = goal
            self.transactions = []
            self.address = address
            self.chainId = chainId
        }
    }
    
    @Model
    final class Goal {
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
        
        // Visual and metadata properties
        var emoji: String?
        var goalDescription: String?
        var link: String?
        
        @Relationship(deleteRule: .cascade) var assets: [Asset] = []
        
        init(name: String, currency: String, targetAmount: Double, deadline: Date, startDate: Date = Date(), frequency: ReminderFrequency = .weekly, emoji: String? = nil, description: String? = nil, link: String? = nil) {
            self.id = UUID()
            self.name = name
            self.currency = currency
            self.targetAmount = targetAmount
            self.deadline = deadline
            self.startDate = startDate
            self.assets = []
            self.reminderFrequency = frequency.rawValue
            self.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
            self.emoji = emoji
            self.goalDescription = description
            self.link = link
        }
    }
}

/// V2 Schema - New models with AssetAllocation
enum SchemaV2 {
    // This will use our updated Asset, Goal, and AssetAllocation models
    // The actual models are defined in their respective files
}