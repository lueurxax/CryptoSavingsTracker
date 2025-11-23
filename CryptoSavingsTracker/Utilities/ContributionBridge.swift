//
//  ContributionBridge.swift
//  CryptoSavingsTracker
//
//  Utility to keep execution tracking in sync when transactions are added or removed.
//

import Foundation
import SwiftData

enum ContributionBridge {
    /// Remove contributions that were bridged from a transaction (match by asset, month, same-day, and assetAmount)
    static func removeLinkedContributions(for transaction: Transaction, in modelContext: ModelContext) {
        let assetId = transaction.asset.id

        let monthLabel = Contribution.monthLabel(from: transaction.date)

        // Fetch all contributions for this month
        let descriptor = FetchDescriptor<Contribution>()
        guard let allContributions = try? modelContext.fetch(descriptor) else { return }

        // Filter manually
        let contributions = allContributions.filter { contrib in
            guard let contribAsset = contrib.asset else { return false }
            return contribAsset.id == assetId && contrib.monthLabel == monthLabel
        }

        var deleted = 0
        for contribution in contributions {
            // Match on same day and assetAmount (fallback to amount)
            let sameDay = Calendar.current.isDate(contribution.date, inSameDayAs: transaction.date)
            let bridgedAmount = contribution.assetAmount ?? contribution.amount
            let matchesAmount = abs(bridgedAmount - transaction.amount) < 0.0001

            if sameDay && matchesAmount {
                if let plan = contribution.monthlyPlan {
                    plan.totalContributed = max(0, plan.totalContributed - contribution.amount)
                }
                modelContext.delete(contribution)
                deleted += 1
            }
        }

        if deleted > 0 {
            try? modelContext.save()
        }
    }
}
