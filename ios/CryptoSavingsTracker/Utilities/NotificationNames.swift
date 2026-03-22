//
//  NotificationNames.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import Foundation

extension Notification.Name {
    static let goalDeleted = Notification.Name("goalDeleted")
    static let goalProgressRefreshed = Notification.Name("goalProgressRefreshed")
    static let goalUpdated = Notification.Name("goalUpdated")

    // MARK: - Freshness Pipeline (Shared Goals)

    /// Posted by `ExchangeRateService` after every successful rate fetch batch.
    /// userInfo: ["refreshedPairs": Set<CurrencyPair>, "refreshedRates": [CurrencyPair: Decimal], "rateSnapshotTimestamp": Date]
    static let exchangeRatesDidRefresh = Notification.Name("exchangeRatesDidRefresh")

    /// Posted by all mutation services after changes that affect shared-goal semantics.
    /// userInfo: ["affectedGoalIDs": [UUID], "reason": "goalMutation|assetMutation|transactionMutation|importOrRepair"]
    static let sharedGoalDataDidChange = Notification.Name("sharedGoalDataDidChange")
}
