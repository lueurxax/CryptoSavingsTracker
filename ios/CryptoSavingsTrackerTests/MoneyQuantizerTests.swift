import Testing
import Foundation
@testable import CryptoSavingsTracker

struct MoneyQuantizerTests {

    @Test("Minor units policy for key currencies")
    func minorUnitsPolicy() {
        #expect(MoneyQuantizer.minorUnits(for: "USD") == 2)
        #expect(MoneyQuantizer.minorUnits(for: "JPY") == 0)
        #expect(MoneyQuantizer.minorUnits(for: "KWD") == 3)
    }

    @Test("Normalization respects currency minor units")
    func normalization() {
        let usd = MoneyQuantizer.normalize(Decimal(string: "2500.005")!, currency: "USD", mode: .halfUp)
        #expect(usd.value == Decimal(string: "2500.01"))

        let jpy = MoneyQuantizer.normalize(Decimal(string: "2500.6")!, currency: "JPY", mode: .halfUp)
        #expect(jpy.value == Decimal(string: "2501"))

        let kwd = MoneyQuantizer.normalize(Decimal(string: "2500.0009")!, currency: "KWD", mode: .halfUp)
        #expect(kwd.value == Decimal(string: "2500.001"))
    }

    @Test("Comparison and difference use minor-unit values")
    func compareAndDifference() {
        let lhs = MoneyQuantizer.normalize(Decimal(string: "2500.00")!, currency: "USD", mode: .halfUp)
        let rhs = MoneyQuantizer.normalize(Decimal(string: "2499.99")!, currency: "USD", mode: .halfUp)

        #expect(MoneyQuantizer.compare(lhs, rhs) == .orderedDescending)

        let diff = MoneyQuantizer.difference(lhs, rhs)
        #expect(diff.value == Decimal(string: "0.01"))
        #expect(diff.currency == "USD")
    }
}
