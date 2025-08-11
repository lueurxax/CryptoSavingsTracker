//
//  CurrencyFormatter.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 10/08/2025.
//

import Foundation

/// Utility for consistent currency formatting across the app
struct CurrencyFormatter {
    
    /// Format an amount with currency symbol
    static func format(amount: Double, currency: String, maximumFractionDigits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = maximumFractionDigits
        
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(Int(amount))"
    }
    
    /// Format amount for accessibility (spells out currency)
    static func accessibilityFormat(amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        
        if let formatted = formatter.string(from: NSNumber(value: amount)) {
            // Replace currency symbol with spelled out currency for better VoiceOver
            return formatted.replacingOccurrences(of: "$", with: "dollars ")
                           .replacingOccurrences(of: "€", with: "euros ")
                           .replacingOccurrences(of: "£", with: "pounds ")
        }
        
        return "\(Int(amount)) \(currency)"
    }
}