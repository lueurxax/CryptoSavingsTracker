//
//  ContributionSource.swift
//  CryptoSavingsTracker
//
//  Shared enum used by execution tracking snapshots and derived events.
//

import Foundation

/// Types of value-change sources in execution tracking.
enum ContributionSource: String, Codable, Sendable {
    case manualDeposit
    case assetReallocation
    case initialAllocation
    case valueAppreciation

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

