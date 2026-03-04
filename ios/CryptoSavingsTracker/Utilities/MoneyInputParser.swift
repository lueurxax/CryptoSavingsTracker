//
//  MoneyInputParser.swift
//  CryptoSavingsTracker
//
//  Locale-aware parser for money amount text input.
//

import Foundation

enum MoneyParseFailure: String, Equatable {
    case invalidFormat
    case ambiguousSeparators
    case tooManyFractionDigits
    case unsupportedCharacters

    var message: String {
        switch self {
        case .invalidFormat:
            return "Enter a valid amount."
        case .ambiguousSeparators:
            return "Couldn't read this amount for your locale."
        case .tooManyFractionDigits:
            return "Too many decimal places for this currency."
        case .unsupportedCharacters:
            return "Remove unsupported characters and try again."
        }
    }
}

struct MoneyInputParseResult {
    let amount: MoneyAmount?
    let failure: MoneyParseFailure?
}

enum MoneyInputParser {
    static func parse(
        rawText: String,
        currency: String,
        locale: Locale = .current,
        mode: MoneyRoundingMode = .halfUp
    ) -> MoneyInputParseResult {
        let trimmed = rawText
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return MoneyInputParseResult(amount: nil, failure: .invalidFormat)
        }

        guard hasOnlySupportedCharacters(trimmed) else {
            return MoneyInputParseResult(amount: nil, failure: .unsupportedCharacters)
        }

        let normalized = strippedCurrencySymbols(trimmed)
            .replacingOccurrences(of: " ", with: "")

        if isAmbiguous(normalized, locale: locale) {
            return MoneyInputParseResult(amount: nil, failure: .ambiguousSeparators)
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale

        guard let number = formatter.number(from: normalized) else {
            return MoneyInputParseResult(amount: nil, failure: .invalidFormat)
        }

        let decimalValue = number.decimalValue
        if decimalValue < 0 {
            return MoneyInputParseResult(amount: nil, failure: .invalidFormat)
        }

        let configuredUnits = MoneyQuantizer.minorUnits(for: currency)
        let fractionPart = fractionDigitsPart(from: normalized, locale: locale)
        if fractionPart.count > configuredUnits {
            let overflowDigits = fractionPart.dropFirst(configuredUnits)
            let isZeroOverflow = overflowDigits.allSatisfy { $0 == "0" }
            if !isZeroOverflow {
                return MoneyInputParseResult(amount: nil, failure: .tooManyFractionDigits)
            }
        }

        let canonical = MoneyQuantizer.normalize(decimalValue, currency: currency, mode: mode)
        return MoneyInputParseResult(amount: canonical, failure: nil)
    }

    private static func hasOnlySupportedCharacters(_ input: String) -> Bool {
        let allowedPunctuation: Set<Character> = [".", ",", "'", " ", "_", "-", "+"]
        for char in input {
            if char.isNumber || allowedPunctuation.contains(char) {
                continue
            }
            if String(char).unicodeScalars.allSatisfy({ $0.properties.generalCategory == .currencySymbol }) {
                continue
            }
            return false
        }
        return true
    }

    private static func strippedCurrencySymbols(_ input: String) -> String {
        String(input.unicodeScalars.filter { scalar in
            scalar.properties.generalCategory != .currencySymbol
        })
    }

    private static func isAmbiguous(_ input: String, locale: Locale) -> Bool {
        let decimalSeparator = locale.decimalSeparator ?? "."
        let containsDot = input.contains(".")
        let containsComma = input.contains(",")

        if containsDot && containsComma {
            guard let lastDot = input.lastIndex(of: "."), let lastComma = input.lastIndex(of: ",") else {
                return true
            }
            let lastSeparator: Character = lastDot > lastComma ? "." : ","
            return String(lastSeparator) != decimalSeparator
        }

        return false
    }

    private static func fractionDigitsPart(from input: String, locale: Locale) -> String {
        let decimalSeparator = locale.decimalSeparator ?? "."
        guard let separatorRange = input.range(of: decimalSeparator, options: .backwards) else {
            return ""
        }
        return String(input[separatorRange.upperBound...])
    }
}
