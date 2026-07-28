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
        asset: Asset? = nil,
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
    
    @Relationship var asset: Asset?

    var source: TransactionSource {
        TransactionSource(rawValue: sourceRawValue) ?? .manual
    }

    var isVerifiedOnChainMovement: Bool {
        guard source == .onChain,
              let externalId,
              let asset,
              let chainId = asset.chainId,
              let address = asset.address
        else {
            return false
        }

        let namespace = OnChainIdentifierPolicy
            .usesCaseInsensitiveOpaqueIdentifiers(forChainIdentifier: chainId)
            ? "onchain_v3"
            : "onchain_v4"
        let normalizedAddress = OnChainIdentifierPolicy.normalizedAddress(
            address,
            forChainIdentifier: chainId
        )
        let expectedScopePrefix = [
            namespace,
            chainId.lowercased(),
            normalizedAddress,
            asset.currency.lowercased(),
            asset.id.uuidString.lowercased()
        ].joined(separator: "|") + "|"
        guard externalId.hasPrefix(expectedScopePrefix) else {
            return false
        }

        if chainId.caseInsensitiveCompare("MATIC") == .orderedSame,
           asset.currency.caseInsensitiveCompare("QUICK") == .orderedSame,
           externalId.lowercased().contains(
               "0x831753dd7087cac61ab5644b308642cc1c33dc13"
           ) {
            return false
        }
        return true
    }

    var isEligibleForExecutionContribution: Bool {
        source == .manual || isVerifiedOnChainMovement
    }
}
