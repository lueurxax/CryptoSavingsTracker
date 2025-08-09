//
//  QuickAction.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 09/08/2025.
//

import Foundation

/// Quick action options for monthly planning
enum QuickAction {
    case skipMonth
    case payHalf
    case payExact
    case reset
    
    var title: String {
        switch self {
        case .skipMonth: return "Skip Month"
        case .payHalf: return "Pay Half"
        case .payExact: return "Pay Exact"
        case .reset: return "Reset"
        }
    }
    
    var systemImage: String {
        switch self {
        case .skipMonth: return "forward.fill"
        case .payHalf: return "divide"
        case .payExact: return "checkmark.circle"
        case .reset: return "arrow.counterclockwise"
        }
    }
    
    var description: String {
        switch self {
        case .skipMonth: return "Skip all flexible goals this month"
        case .payHalf: return "Pay 50% of required amounts"
        case .payExact: return "Pay exact calculated amounts"
        case .reset: return "Reset all adjustments"
        }
    }
}