//
//  BalanceServiceHumanReadableBalanceTests.swift
//  CryptoSavingsTrackerTests
//

import Foundation
import Testing
@testable import CryptoSavingsTracker

/// Locks down the assumption that `BalanceService.humanReadableBalance(from:)` treats
/// Tatum v4's `denominatedBalance` as an always-raw, base-unit value that must be scaled
/// by `decimals`. There is intentionally no ">1000" magnitude heuristic fallback anymore:
/// if the API ever returns an already human-readable value here, the result will be wrong,
/// so these tests exist to make that contract explicit and catch regressions.
struct BalanceServiceHumanReadableBalanceTests {

    private func makeItem(
        balance: String = "0",
        denominatedBalance: String,
        decimals: Int
    ) -> TatumV4BalanceItem {
        TatumV4BalanceItem(
            chain: "ethereum",
            address: "0xabc",
            balance: balance,
            denominatedBalance: denominatedBalance,
            decimals: decimals,
            type: "native",
            tokenAddress: nil,
            tokenName: nil,
            tokenSymbol: "ETH"
        )
    }

    @Test("Scales raw denominatedBalance by decimals for an 18-decimal token")
    func scalesRawBalanceByDecimals() {
        // 1.5 ETH expressed in wei
        let item = makeItem(denominatedBalance: "1500000000000000000", decimals: 18)
        let result = BalanceService.humanReadableBalance(from: item)
        #expect(abs(result - 1.5) < 0.0000001)
    }

    @Test("Scales raw denominatedBalance by decimals for a high-value asset")
    func scalesHighValueAssetCorrectly() {
        // A large, high-value raw balance (well above the old ">1000" heuristic threshold)
        // should still be divided by 10^decimals, not returned as-is. Uses 8 decimals (like
        // BTC) so the raw integer stays within `Double`'s exact-integer range (< 2^53),
        // keeping the assertion free of unrelated floating-point precision noise.
        let item = makeItem(denominatedBalance: "12345600000000", decimals: 8)
        let result = BalanceService.humanReadableBalance(from: item)
        #expect(abs(result - 123456.0) < 0.000001)
    }

    @Test("Handles zero decimals without altering magnitude")
    func handlesZeroDecimals() {
        let item = makeItem(denominatedBalance: "42", decimals: 0)
        let result = BalanceService.humanReadableBalance(from: item)
        #expect(result == 42.0)
    }

    @Test("Falls back to human-readable balance field when denominatedBalance is not numeric")
    func fallsBackToBalanceFieldWhenDenominatedBalanceInvalid() {
        let item = makeItem(balance: "2.75", denominatedBalance: "not-a-number", decimals: 18)
        let result = BalanceService.humanReadableBalance(from: item)
        #expect(result == 2.75)
    }

    @Test("Returns zero when neither balance field is a valid number")
    func returnsZeroWhenNoValidNumberAvailable() {
        let item = makeItem(balance: "not-a-number", denominatedBalance: "also-not-a-number", decimals: 18)
        let result = BalanceService.humanReadableBalance(from: item)
        #expect(result == 0.0)
    }
}
