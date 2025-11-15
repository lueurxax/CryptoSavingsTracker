//
//  Contribution.swift
//  CryptoSavingsTracker
//
//  Created for v2.0 - Fixed-amount allocations
//  Tracks allocation history and money movement
//

import SwiftData
import Foundation

@Model
final class Contribution {
    @Attribute(.unique) var id: UUID
    var amount: Double           // Value in goal's currency (converted at exchange rate)
    var assetAmount: Double?     // Original crypto amount (e.g., 0.5 BTC)
    var date: Date
    var sourceType: ContributionSource
    var notes: String?

    // Relationships
    var goal: Goal?
    var asset: Asset?

    // Tracking metadata
    var monthLabel: String       // "2025-09" for grouping by month (UTC-based)
    var isPlanned: Bool          // Was this from monthly plan?
    var executionRecordId: UUID? // Link to MonthlyExecutionRecord for tracking

    // Exchange rate tracking for accurate historical valuation
    var exchangeRateSnapshot: Double?  // Rate at time of contribution
    var exchangeRateTimestamp: Date?   // When rate was captured
    var exchangeRateProvider: String?  // e.g., "CoinGecko", "Manual"
    var currencyCode: String?          // Goal currency (e.g., "USD")
    var assetSymbol: String?           // Asset symbol (e.g., "BTC")

    init(amount: Double, goal: Goal, asset: Asset, source: ContributionSource) {
        self.id = UUID()
        self.amount = amount
        self.assetAmount = nil
        self.date = Date()
        self.sourceType = source
        self.notes = nil
        self.goal = goal
        self.asset = asset
        self.monthLabel = Self.monthLabel(from: Date())
        self.isPlanned = false
        self.exchangeRateSnapshot = nil
        self.exchangeRateTimestamp = nil
        self.exchangeRateProvider = nil
        self.currencyCode = goal.currency
        self.assetSymbol = asset.currency
    }

    /// Generate month label from date (format: "YYYY-MM") using UTC calendar
    static func monthLabel(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else {
            return "Unknown"
        }
        return String(format: "%04d-%02d", year, month)
    }

    /// Check if this contribution is from the current month
    var isCurrentMonth: Bool {
        return monthLabel == Self.monthLabel(from: Date())
    }

    /// Formatted display of contribution amount
    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = goal?.currency ?? "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    /// Source type display name
    var sourceDisplayName: String {
        return sourceType.displayName
    }
}

/// Types of contribution sources
enum ContributionSource: String, Codable, Sendable {
    case manualDeposit      // User added money to asset
    case assetReallocation  // Moved between goals
    case initialAllocation  // First-time asset allocation
    case valueAppreciation  // Crypto price increase (optional)

    var displayName: String {
        switch self {
        case .manualDeposit:
            return "Manual Deposit"
        case .assetReallocation:
            return "Reallocation"
        case .initialAllocation:
            return "Initial Allocation"
        case .valueAppreciation:
            return "Value Appreciation"
        }
    }

    var systemImageName: String {
        switch self {
        case .manualDeposit:
            return "plus.circle.fill"
        case .assetReallocation:
            return "arrow.left.arrow.right"
        case .initialAllocation:
            return "sparkles"
        case .valueAppreciation:
            return "chart.line.uptrend.xyaxis"
        }
    }
}