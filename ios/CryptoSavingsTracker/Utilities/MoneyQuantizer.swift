//
//  MoneyQuantizer.swift
//  CryptoSavingsTracker
//
//  Currency-aware normalization and comparison helpers for budget calculations.
//

import Foundation

enum MoneyRoundingMode {
    case halfUp
    case up
}

enum MoneyQuantizer {
    private static let threeDecimalCurrencies: Set<String> = ["KWD", "BHD", "OMR"]
    private static let zeroDecimalCurrencies: Set<String> = ["JPY", "KRW"]
    private static let twoDecimalCurrencies: Set<String> = ["USD", "EUR", "GBP"]

    static func minorUnits(for currency: String) -> Int {
        let upperCurrency = currency.uppercased()
        if threeDecimalCurrencies.contains(upperCurrency) {
            return 3
        }
        if zeroDecimalCurrencies.contains(upperCurrency) {
            return 0
        }
        if twoDecimalCurrencies.contains(upperCurrency) {
            return 2
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = upperCurrency
        if formatter.maximumFractionDigits >= 0 {
            return formatter.maximumFractionDigits
        }
        return 2
    }

    static func normalize(_ value: Decimal, currency: String, mode: MoneyRoundingMode) -> MoneyAmount {
        let units = minorUnits(for: currency)
        var working = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &working, units, nsRoundingMode(mode))
        return MoneyAmount(value: rounded, currency: currency)
    }

    static func compare(_ lhs: MoneyAmount, _ rhs: MoneyAmount) -> ComparisonResult {
        precondition(lhs.currency == rhs.currency, "Cannot compare different currencies")
        let lhsMinor = lhs.minorUnitValue
        let rhsMinor = rhs.minorUnitValue
        if lhsMinor == rhsMinor { return .orderedSame }
        return lhsMinor < rhsMinor ? .orderedAscending : .orderedDescending
    }

    static func difference(_ lhs: MoneyAmount, _ rhs: MoneyAmount) -> MoneyAmount {
        precondition(lhs.currency == rhs.currency, "Cannot diff different currencies")
        let units = minorUnits(for: lhs.currency)
        let scale = decimalScale(units)
        let deltaMinor = lhs.minorUnitValue - rhs.minorUnitValue
        let deltaDecimal = Decimal(deltaMinor) / scale
        return normalize(deltaDecimal, currency: lhs.currency, mode: .halfUp)
    }

    static func minorUnitValue(for value: Decimal, currency: String) -> Int64 {
        let units = minorUnits(for: currency)
        let normalized = normalize(value, currency: currency, mode: .halfUp)
        let scaled = normalized.value * decimalScale(units)
        let number = NSDecimalNumber(decimal: scaled)
        return number.int64Value
    }

    static func decimalScale(_ units: Int) -> Decimal {
        Decimal(sign: .plus, exponent: units, significand: 1)
    }

    private static func nsRoundingMode(_ mode: MoneyRoundingMode) -> NSDecimalNumber.RoundingMode {
        switch mode {
        case .halfUp:
            return .plain
        case .up:
            return .up
        }
    }
}
