//
//  NotificationNames.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import Foundation

extension Notification.Name {
    nonisolated static let goalDeleted = Notification.Name("goalDeleted")
    nonisolated static let goalProgressRefreshed = Notification.Name("goalProgressRefreshed")
    nonisolated static let goalUpdated = Notification.Name("goalUpdated")

    // MARK: - Freshness Pipeline (Shared Goals)

    /// Posted by `ExchangeRateService` after every successful rate fetch batch.
    /// userInfo: ["refreshedPairs": Set<String>, "refreshedRates": [String: Decimal], "rateSnapshotTimestamp": Date]
    nonisolated static let exchangeRatesDidRefresh = Notification.Name("exchangeRatesDidRefresh")

    /// Posted by all mutation services after changes that affect shared-goal semantics.
    /// userInfo: ["affectedGoalIDs": [UUID], "reason": "goalMutation|assetMutation|transactionMutation|importOrRepair"]
    nonisolated static let sharedGoalDataDidChange = Notification.Name("sharedGoalDataDidChange")
}
