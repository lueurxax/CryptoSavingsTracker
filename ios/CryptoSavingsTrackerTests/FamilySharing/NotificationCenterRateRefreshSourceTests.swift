import XCTest
@testable import CryptoSavingsTracker

@MainActor
final class NotificationCenterRateRefreshSourceTests: XCTestCase {
    func testRatesDidRefreshEventCarriesRefreshedRates() async throws {
        let source = NotificationCenterRateRefreshSource()
        let pair = CurrencyPair(from: "BTC", to: "USD")
        let pairKey = pair.canonicalKey
        let timestamp = Date(timeIntervalSince1970: 1_763_000_000)
        let rates = [pairKey: Decimal(string: "86432.45")!]

        let expectation = expectation(description: "rate event received")
        var received: RateRefreshEvent?

        let task = Task {
            for await event in source.ratesDidRefresh {
                received = event
                expectation.fulfill()
                break
            }
        }

        NotificationCenter.default.post(
            name: .exchangeRatesDidRefresh,
            object: nil,
            userInfo: [
                "refreshedPairs": Set([pairKey]),
                "refreshedRates": rates,
                "rateSnapshotTimestamp": timestamp
            ]
        )

        await fulfillment(of: [expectation], timeout: 1)
        task.cancel()

        XCTAssertEqual(received?.refreshedPairs, Set([pairKey]))
        XCTAssertEqual(received?.rates[pairKey], rates[pairKey])
        XCTAssertEqual(received?.rateSnapshotTimestamp, timestamp)
    }
}
