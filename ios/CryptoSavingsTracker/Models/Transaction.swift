//
//  Transaction.swift
//  CryptoSavingsTracker
//
//  Created by Assistant on 11/08/2025.
//

import SwiftData
import Foundation

@Model
final class Transaction {
    init(
        amount: Double,
        asset: Asset,
        date: Date = Date(),
        source: TransactionSource = .manual,
        externalId: String? = nil,
        counterparty: String? = nil,
        comment: String? = nil
    ) {
        self.id = UUID()
        self.amount = amount
        self.date = date
        self.asset = asset
        self.comment = comment
        self.sourceRawValue = source.rawValue
        self.externalId = externalId
        self.counterparty = counterparty
    }

    var id: UUID = UUID()
    var amount: Double = 0.0
    var date: Date = Date()
    var sourceRawValue: String = TransactionSource.manual.rawValue
    var externalId: String?
    var counterparty: String?
    var comment: String?
    
    var asset: Asset?

    var source: TransactionSource {
        TransactionSource(rawValue: sourceRawValue) ?? .manual
    }
}
