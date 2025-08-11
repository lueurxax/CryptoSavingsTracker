//
//  BalanceState.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 11/08/2025.
//

import Foundation

// Represents the state of a balance fetch operation
enum BalanceState: Equatable {
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
}

// Helper for balance state management
// Note: BalanceState should be managed by ViewModels, not stored in the model directly