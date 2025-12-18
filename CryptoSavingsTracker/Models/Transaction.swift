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

    @Attribute(.unique) var id: UUID
    var amount: Double
    var date: Date
    var sourceRawValue: String = TransactionSource.manual.rawValue
    var externalId: String?
    var counterparty: String?
    var comment: String?
    
    var asset: Asset

    var source: TransactionSource {
        TransactionSource(rawValue: sourceRawValue) ?? .manual
    }
}
