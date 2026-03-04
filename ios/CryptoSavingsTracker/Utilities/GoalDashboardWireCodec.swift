//
//  GoalDashboardWireCodec.swift
//  CryptoSavingsTracker
//
//  Canonical wire format helpers for Goal Dashboard shared fixtures.
//

import Foundation

enum GoalDashboardWireCodecError: Error, LocalizedError {
    case invalidDecimalFormat(String)
    case invalidDateFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidDecimalFormat(let value):
            return "Invalid canonical decimal format: \(value)"
        case .invalidDateFormat(let value):
            return "Invalid canonical RFC3339 UTC date format: \(value)"
        }
    }
}

enum GoalDashboardWireCodec {
    private static let decimalPattern = #"^-?(0|[1-9][0-9]*)(\.[0-9]{1,18})?$"#
    private static let decimalRegex = try? NSRegularExpression(pattern: decimalPattern, options: [])

    private static let iso8601Millis: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func encode(decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }

    static func decode(decimal string: String) throws -> Decimal {
        let range = NSRange(location: 0, length: string.utf16.count)
        let matches = decimalRegex?.numberOfMatches(in: string, options: [], range: range) ?? 0
        guard matches == 1 else {
            throw GoalDashboardWireCodecError.invalidDecimalFormat(string)
        }
        guard let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
            throw GoalDashboardWireCodecError.invalidDecimalFormat(string)
        }
        return decimal
    }

    static func encode(date: Date) -> String {
        iso8601Millis.string(from: date)
    }

    static func decode(date string: String) throws -> Date {
        guard string.hasSuffix("Z"), let date = iso8601Millis.date(from: string) else {
            throw GoalDashboardWireCodecError.invalidDateFormat(string)
        }
        return date
    }
}
