//
//  TatumBalanceResponseHumanReadableBalanceTests.swift
//  CryptoSavingsTrackerTests
//

import Foundation
import Testing
@testable import CryptoSavingsTracker

/// Locks down the assumption that `TatumBalanceResponse.humanReadableBalance` treats the
/// legacy `balance` field as an always-raw, base-unit value whenever `tokenDecimals` is
/// present. There is intentionally no ">1000" magnitude heuristic fallback anymore: if the
/// Tatum API ever returns an already human-readable balance alongside `tokenDecimals`, the
/// result will be wrong, so these tests exist to make that contract explicit.
struct TatumBalanceResponseHumanReadableBalanceTests {

    @Test("Scales raw balance by tokenDecimals for an 18-decimal token")
    func scalesRawBalanceByTokenDecimals() {
        let response = TatumBalanceResponse(
            balance: "1500000000000000000",
            tokenAddress: nil,
            tokenName: "Ether",
            tokenSymbol: "ETH",
            tokenDecimals: 18
        )
        #expect(abs(response.humanReadableBalance - 1.5) < 0.0000001)
    }

    @Test("Scales a high-value raw balance without triggering a magnitude fallback")
    func scalesHighValueBalanceCorrectly() {
        // Uses 8 decimals (like BTC) so the raw integer stays within `Double`'s
        // exact-integer range (< 2^53), keeping the assertion free of unrelated
        // floating-point precision noise while still exercising a high-value asset.
        let response = TatumBalanceResponse(
            balance: "12345600000000",
            tokenAddress: nil,
            tokenName: "Bitcoin",
            tokenSymbol: "BTC",
            tokenDecimals: 8
        )
        #expect(abs(response.humanReadableBalance - 123456.0) < 0.000001)
    }

    @Test("Returns balance as-is when tokenDecimals is absent")
    func returnsRawValueWhenDecimalsMissing() {
        let response = TatumBalanceResponse(
            balance: "2.5",
            tokenAddress: nil,
            tokenName: nil,
            tokenSymbol: nil,
            tokenDecimals: nil
        )
        #expect(response.humanReadableBalance == 2.5)
    }

    @Test("Returns zero when balance is not a valid number")
    func returnsZeroForInvalidBalance() {
        let response = TatumBalanceResponse(
            balance: "not-a-number",
            tokenAddress: nil,
            tokenName: nil,
            tokenSymbol: nil,
            tokenDecimals: 18
        )
        #expect(response.humanReadableBalance == 0)
    }
}
