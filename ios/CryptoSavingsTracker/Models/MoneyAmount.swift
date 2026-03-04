//
//  MoneyAmount.swift
//  CryptoSavingsTracker
//
//  Canonical money representation for budget planning flows.
//

import Foundation

struct MoneyAmount: Equatable, Hashable {
    let value: Decimal
    let currency: String

    var minorUnits: Int {
        MoneyQuantizer.minorUnits(for: currency)
    }

    var minorUnitValue: Int64 {
        MoneyQuantizer.minorUnitValue(for: value, currency: currency)
    }

    init(value: Decimal, currency: String) {
        self.value = value
        self.currency = currency.uppercased()
    }

    init(doubleValue: Double, currency: String) {
        self.init(value: Decimal(doubleValue), currency: currency)
    }

    var doubleValue: Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
