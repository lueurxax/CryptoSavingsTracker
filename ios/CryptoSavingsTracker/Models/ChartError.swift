//
//  ChartError.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import Foundation

// MARK: - Chart Error Types
enum ChartError: Error, LocalizedError, Equatable {
    case dataUnavailable(String)
    case networkError(String)
    case conversionError(from: String, to: String)
    case calculationError(String)
    case invalidDateRange
    case insufficientData(minimum: Int, actual: Int)
    
    var errorDescription: String? {
        switch self {
        case .dataUnavailable(let context):
            return "Data unavailable: \(context)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .conversionError(let from, let to):
            return "Currency conversion failed from \(from) to \(to)"
        case .calculationError(let context):
            return "Calculation error: \(context)"
        case .invalidDateRange:
            return "Invalid date range provided"
        case .insufficientData(let minimum, let actual):
            return "Insufficient data: need \(minimum), have \(actual)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .dataUnavailable:
            return "Try adding more transactions or refreshing your data"
        case .networkError:
            return "Check your internet connection and try again"
        case .conversionError:
            return "Verify currency settings and network connection"
        case .calculationError:
            return "Contact support if this error persists"
        case .invalidDateRange:
            return "Check your date range settings"
        case .insufficientData(let minimum, _):
            return "Add at least \(minimum) data points to view this chart"
        }
    }
    
    var helpAnchor: String? {
        switch self {
        case .dataUnavailable:
            return "data-requirements"
        case .networkError:
            return "network-troubleshooting"
        case .conversionError:
            return "currency-conversion"
        case .calculationError:
            return "technical-support"
        case .invalidDateRange:
            return "date-range-help"
        case .insufficientData:
            return "minimum-data-requirements"
        }
    }
}

// MARK: - Chart Error State
struct ChartErrorState: Equatable {
    let error: ChartError
    let timestamp: Date
    let canRetry: Bool
    
    init(error: ChartError, canRetry: Bool = true) {
        self.error = error
        self.timestamp = Date()
        self.canRetry = canRetry
    }
}

// MARK: - Chart Loading State
enum ChartLoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(ChartErrorState)
    
    static func == (lhs: ChartLoadingState, rhs: ChartLoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError.error == rhsError.error && 
                   lhsError.timestamp == rhsError.timestamp &&
                   lhsError.canRetry == rhsError.canRetry
        default:
            return false
        }
    }
    
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
    
    var error: ChartError? {
        if case .error(let errorState) = self { return errorState.error }
        return nil
    }
    
    var canRetry: Bool {
        if case .error(let errorState) = self { return errorState.canRetry }
        return false
    }
}