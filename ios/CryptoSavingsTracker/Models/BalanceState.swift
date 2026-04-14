//
//  BalanceState.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 11/08/2025.
//

import Foundation

// Represents the state of a balance fetch operation
enum BalanceState: Equatable {
    enum CryptoTrackingStatus: String, CaseIterable {
        case connecting = "Connecting"
        case syncing = "Syncing"
        case connected = "Connected"
        case stale = "Stale"
        case needsAttention = "Needs Attention"

        var title: String { rawValue }

        var systemImage: String {
            switch self {
            case .connecting:
                return "link.badge.plus"
            case .syncing:
                return "arrow.triangle.2.circlepath"
            case .connected:
                return "checkmark.circle"
            case .stale:
                return "clock.badge.exclamationmark"
            case .needsAttention:
                return "exclamationmark.triangle"
            }
        }

        var addAssetDescription: String {
            switch self {
            case .connecting:
                return "Checking the wallet for the first time."
            case .syncing:
                return "Refreshing the latest balance and transactions."
            case .connected:
                return "Balance data is current."
            case .stale:
                return "Showing cached values while the latest refresh catches up."
            case .needsAttention:
                return "Refresh failed. The last successful balance stays visible until tracking recovers."
            }
        }
    }

    case loading
    case loaded(balance: Double, isCached: Bool, lastUpdated: Date)
    case error(message: String, cachedBalance: Double?, lastUpdated: Date?)
    
    var balance: Double {
        switch self {
        case .loading:
            return 0
        case .loaded(let balance, _, _):
            return balance
        case .error(_, let cachedBalance, _):
            return cachedBalance ?? 0
        }
    }
    
    var displayBalance: String {
        switch self {
        case .loading:
            return "Loading..."
        case .loaded(let balance, let isCached, let lastUpdated):
            if isCached {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .short
                let timeAgo = formatter.localizedString(for: lastUpdated, relativeTo: Date())
                return "\(balance) (cached \(timeAgo))"
            }
            return String(balance)
        case .error(_, let cachedBalance, let lastUpdated):
            if let balance = cachedBalance, let updated = lastUpdated {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .short
                let timeAgo = formatter.localizedString(for: updated, relativeTo: Date())
                return "\(balance) (offline, last seen \(timeAgo))"
            }
            return "Unavailable"
        }
    }
    
    var isStale: Bool {
        switch self {
        case .loading:
            return false
        case .loaded(_, let isCached, _):
            return isCached
        case .error:
            return true
        }
    }
    
    var hasError: Bool {
        if case .error = self {
            return true
        }
        return false
    }

    func publicCryptoTrackingStatus(
        isRefreshing: Bool,
        hasRetainedValue: Bool
    ) -> CryptoTrackingStatus {
        switch self {
        case .loading:
            return (isRefreshing || hasRetainedValue) ? .syncing : .connecting
        case .loaded(_, let isCached, _):
            return isCached ? .stale : .connected
        case .error:
            return .needsAttention
        }
    }

    func publicTrackingStatusDetail(
        isRefreshing: Bool,
        hasRetainedValue: Bool
    ) -> String {
        publicCryptoTrackingStatus(
            isRefreshing: isRefreshing,
            hasRetainedValue: hasRetainedValue
        ).addAssetDescription
    }
}

// Helper for balance state management
// Note: BalanceState should be managed by ViewModels, not stored in the model directly
