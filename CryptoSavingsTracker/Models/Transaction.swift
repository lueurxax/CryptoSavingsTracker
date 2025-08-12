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
    init(amount: Double, asset: Asset, comment: String? = nil) {
        self.id = UUID()
        self.amount = amount
        self.date = Date()
        self.asset = asset
        self.comment = comment
    }

    @Attribute(.unique) var id: UUID
    var amount: Double
    var date: Date
    var comment: String?
    
    @Relationship var asset: Asset
}