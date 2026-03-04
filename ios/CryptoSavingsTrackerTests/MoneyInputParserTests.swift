import Testing
import Foundation
@testable import CryptoSavingsTracker

struct MoneyInputParserTests {

    @Test("Parses en_US input")
    func parseEnUS() {
        let locale = Locale(identifier: "en_US")
        let result = MoneyInputParser.parse(rawText: "2,500.50", currency: "USD", locale: locale)
        #expect(result.failure == nil)
        #expect(result.amount?.value == Decimal(string: "2500.50"))
    }

    @Test("Parses de_DE input")
    func parseDeDE() {
        let locale = Locale(identifier: "de_DE")
        let result = MoneyInputParser.parse(rawText: "2.500,50", currency: "EUR", locale: locale)
        #expect(result.failure == nil)
        #expect(result.amount?.value == Decimal(string: "2500.50"))
    }

    @Test("Handles currency symbols and non-breaking spaces")
    func parseWithSymbolAndNBSP() {
        let locale = Locale(identifier: "en_US")
        let raw = "$\u{00A0}2,500.50"
        let result = MoneyInputParser.parse(rawText: raw, currency: "USD", locale: locale)
        #expect(result.failure == nil)
        #expect(result.amount?.value == Decimal(string: "2500.50"))
    }

    @Test("Rejects ambiguous separator pattern for locale")
    func rejectAmbiguousForLocale() {
        let locale = Locale(identifier: "en_US")
        let result = MoneyInputParser.parse(rawText: "2.500,50", currency: "USD", locale: locale)
        #expect(result.failure == .ambiguousSeparators)
        #expect(result.amount == nil)
    }

    @Test("Rejects too many fraction digits for currency policy")
    func rejectTooManyFractionDigits() {
        let locale = Locale(identifier: "en_US")
        let result = MoneyInputParser.parse(rawText: "2500.123", currency: "USD", locale: locale)
        #expect(result.failure == .tooManyFractionDigits)
        #expect(result.amount == nil)
    }

    @Test("Allows extra trailing zeros beyond minor units when canonical value is unchanged")
    func allowsTrailingZeroOverflow() {
        let locale = Locale(identifier: "en_US")
        let result = MoneyInputParser.parse(rawText: "2500.000", currency: "USD", locale: locale)
        #expect(result.failure == nil)
        #expect(result.amount?.value == Decimal(string: "2500.00"))
    }

    @Test("Rejects unsupported characters")
    func rejectUnsupportedCharacters() {
        let locale = Locale(identifier: "en_US")
        let result = MoneyInputParser.parse(rawText: "2500abc", currency: "USD", locale: locale)
        #expect(result.failure == .unsupportedCharacters)
        #expect(result.amount == nil)
    }
}
