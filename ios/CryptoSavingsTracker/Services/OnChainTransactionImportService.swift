//
//  OnChainTransactionImportService.swift
//  CryptoSavingsTracker
//
//  Persists fetched on-chain transactions as `Transaction` rows (source: .onChain)
//  so execution tracking can remain timestamp-based without relying on network at calculation time.
//

import Foundation
import SwiftData

@MainActor
final class OnChainTransactionImportService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Upserts fetched on-chain transactions into SwiftData as `Transaction` rows.
    /// - Returns: number of inserted transactions.
    func upsert(transactions: [TatumTransaction], for asset: Asset) throws -> Int {
        guard let address = asset.address, let chainId = asset.chainId, !address.isEmpty, !chainId.isEmpty else { return 0 }

        let normalizedAddress = address.lowercased()
        let existingExternalIds = Set(
            asset.transactions
                .filter { $0.source == .onChain }
                .compactMap(\.externalId)
        )

        var inserted = 0
        var insertedModels: [Transaction] = []
        insertedModels.reserveCapacity(transactions.count)
        let epsilon = 0.0000000001

        for tx in transactions {
            guard !existingExternalIds.contains(tx.hash) else { continue }
            guard let signedAmount = tx.signedAmount(forAssetSymbol: asset.currency, trackedAddress: normalizedAddress),
                  abs(signedAmount) > epsilon
            else { continue }

            let counterparty = tx.counterAddress ?? tx.from ?? tx.to
            let newTransaction = Transaction(
                amount: signedAmount,
                asset: asset,
                date: tx.date,
                source: .onChain,
                externalId: tx.hash,
                counterparty: counterparty,
                comment: "On-chain"
            )

            modelContext.insert(newTransaction)

            // Ensure relationship collections update immediately.
            if !asset.transactions.contains(where: { $0.id == newTransaction.id }) {
                asset.transactions.append(newTransaction)
            }

            insertedModels.append(newTransaction)
            inserted += 1
        }

        if inserted > 0 {
            applyDedicatedAutoAllocationIfNeeded(for: asset, insertedTransactions: insertedModels)
            try modelContext.save()
        }

        return inserted
    }

    /// Implements the redesign rule for on-chain arrivals:
    /// if an asset is fully allocated to exactly one goal, new deposits should keep it fully allocated.
    /// For partially allocated or shared assets, deposits remain unallocated.
    private func applyDedicatedAutoAllocationIfNeeded(for asset: Asset, insertedTransactions: [Transaction]) {
        let epsilon = 0.0000001
        guard asset.allocations.count == 1,
              let allocation = asset.allocations.first,
              let goal = allocation.goal
        else { return }

        let deposits = insertedTransactions
            .filter { $0.amount > epsilon }
            .sorted(by: { $0.date < $1.date })
        guard !deposits.isEmpty else { return }

        // Only auto-allocate when the newly observed "unallocated" portion matches the new deposits.
        // This avoids guessing for intentionally partially allocated assets.
        let unallocatedNow = max(0, asset.currentAmount - allocation.amountValue)
        let depositsSum = deposits.reduce(0.0) { $0 + $1.amount }
        let tolerance = max(epsilon, max(unallocatedNow, depositsSum) * 0.000001)
        guard abs(unallocatedNow - depositsSum) <= tolerance else { return }

        var runningTarget = allocation.amountValue
        for deposit in deposits {
            runningTarget += deposit.amount
            allocation.updateAmount(runningTarget)
            modelContext.insert(AllocationHistory(asset: asset, goal: goal, amount: runningTarget, timestamp: deposit.date))
        }
    }
}

private extension TatumTransaction {
    func signedAmount(forAssetSymbol symbol: String, trackedAddress: String) -> Double? {
        let normalizedSymbol = symbol.uppercased()

        let baseAmount: Double = {
            // Prefer matching token transfers when present (e.g., USDT on EVM).
            if let transfers = tokenTransfers, !transfers.isEmpty {
                if let match = transfers.first(where: { ($0.tokenSymbol ?? "").uppercased() == normalizedSymbol }) {
                    return abs(match.humanReadableValue)
                }
            }
            return abs(nativeValue)
        }()

        guard baseAmount > 0 else { return nil }

        if let subtype = transactionSubtype?.lowercased() {
            if subtype.contains("receive") { return baseAmount }
            if subtype.contains("sent") { return -baseAmount }
        }

        // Fallback: infer direction from from/to fields.
        if let toAddress = to?.lowercased(), toAddress == trackedAddress {
            return baseAmount
        }
        if let fromAddress = from?.lowercased(), fromAddress == trackedAddress {
            return -baseAmount
        }

        return nil
    }
}
