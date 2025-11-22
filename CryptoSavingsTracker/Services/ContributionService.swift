//
//  ContributionService.swift
//  CryptoSavingsTracker
//
//  Created for v2.0 - Track contribution history
//

import SwiftData
import Foundation

/// Service responsible for managing contribution records
/// Tracks all money movements: deposits, reallocations, initial allocations
@MainActor
class ContributionService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Create Contributions

    /// Record a manual deposit contribution
    /// - Parameters:
    ///   - amount: Amount in goal's currency (fiat)
    ///   - assetAmount: Original crypto amount
    ///   - goal: The goal receiving the contribution
    ///   - asset: The asset the contribution comes from
    ///   - exchangeRate: Exchange rate at time of deposit
    ///   - exchangeRateProvider: Source of exchange rate
    ///   - notes: Optional notes
    func recordDeposit(
        amount: Double,
        assetAmount: Double,
        to goal: Goal,
        from asset: Asset,
        exchangeRate: Double,
        exchangeRateProvider: String = "Manual",
        notes: String? = nil
    ) throws -> Contribution {
        let contribution = Contribution(
            amount: amount,  // Fiat amount
            goal: goal,
            asset: asset,
            source: .manualDeposit
        )
        contribution.assetAmount = assetAmount  // Crypto amount
        contribution.notes = notes
        contribution.currencyCode = goal.currency
        contribution.assetSymbol = asset.currency
        contribution.exchangeRateSnapshot = exchangeRate
        contribution.exchangeRateTimestamp = Date()
        contribution.exchangeRateProvider = exchangeRateProvider

        modelContext.insert(contribution)
        try modelContext.save()

        return contribution
    }

    /// Record a reallocation between goals
    /// - Parameters:
    ///   - fiatAmount: Amount in goal's currency
    ///   - assetAmount: Crypto amount being reallocated
    ///   - fromGoal: Source goal
    ///   - toGoal: Destination goal
    ///   - asset: The asset being reallocated
    ///   - exchangeRate: Exchange rate at time of reallocation
    ///   - exchangeRateProvider: Source of exchange rate
    func recordReallocation(
        fiatAmount: Double,
        assetAmount: Double,
        from fromGoal: Goal,
        to toGoal: Goal,
        asset: Asset,
        exchangeRate: Double,
        exchangeRateProvider: String = "Manual"
    ) throws -> (withdrawal: Contribution, deposit: Contribution) {
        // Create withdrawal record (negative amount)
        let withdrawal = Contribution(
            amount: -fiatAmount,  // Negative fiat amount
            goal: fromGoal,
            asset: asset,
            source: .assetReallocation
        )
        withdrawal.assetAmount = -assetAmount  // Negative crypto amount
        withdrawal.notes = "Reallocated to \(toGoal.name)"
        withdrawal.currencyCode = fromGoal.currency
        withdrawal.assetSymbol = asset.currency
        withdrawal.exchangeRateSnapshot = exchangeRate
        withdrawal.exchangeRateTimestamp = Date()
        withdrawal.exchangeRateProvider = exchangeRateProvider

        // Create deposit record (positive amount)
        let deposit = Contribution(
            amount: fiatAmount,  // Positive fiat amount
            goal: toGoal,
            asset: asset,
            source: .assetReallocation
        )
        deposit.assetAmount = assetAmount  // Positive crypto amount
        deposit.notes = "Reallocated from \(fromGoal.name)"
        deposit.currencyCode = toGoal.currency
        deposit.assetSymbol = asset.currency
        deposit.exchangeRateSnapshot = exchangeRate
        deposit.exchangeRateTimestamp = Date()
        deposit.exchangeRateProvider = exchangeRateProvider

        modelContext.insert(withdrawal)
        modelContext.insert(deposit)
        try modelContext.save()

        return (withdrawal, deposit)
    }

    /// Record initial allocation (used during migration)
    /// - Parameters:
    ///   - fiatAmount: Fixed amount in goal's currency
    ///   - assetAmount: Crypto amount allocated
    ///   - goal: Goal receiving allocation
    ///   - asset: Asset being allocated
    ///   - exchangeRate: Exchange rate at time of allocation
    ///   - exchangeRateProvider: Source of exchange rate
    ///   - date: Date of allocation (defaults to now)
    func recordInitialAllocation(
        fiatAmount: Double,
        assetAmount: Double,
        to goal: Goal,
        from asset: Asset,
        exchangeRate: Double,
        exchangeRateProvider: String = "Migration",
        date: Date = Date()
    ) throws -> Contribution {
        let contribution = Contribution(
            amount: fiatAmount,  // Fiat amount in goal currency
            goal: goal,
            asset: asset,
            source: .initialAllocation
        )
        contribution.date = date
        contribution.assetAmount = assetAmount  // Crypto amount
        contribution.notes = "Initial allocation"
        contribution.currencyCode = goal.currency
        contribution.assetSymbol = asset.currency
        contribution.exchangeRateSnapshot = exchangeRate
        contribution.exchangeRateTimestamp = date
        contribution.exchangeRateProvider = exchangeRateProvider

        modelContext.insert(contribution)
        try modelContext.save()

        return contribution
    }

    /// Record value appreciation (price increase)
    /// - Parameters:
    ///   - fiatAmount: Appreciation amount in goal's currency
    ///   - goal: Goal benefiting from appreciation
    ///   - asset: Asset that appreciated
    ///   - oldExchangeRate: Previous exchange rate
    ///   - newExchangeRate: New exchange rate
    ///   - exchangeRateProvider: Source of exchange rate
    func recordAppreciation(
        fiatAmount: Double,
        for goal: Goal,
        asset: Asset,
        oldExchangeRate: Double,
        newExchangeRate: Double,
        exchangeRateProvider: String = "CoinGecko"
    ) throws -> Contribution {
        let contribution = Contribution(
            amount: fiatAmount,  // Fiat appreciation amount
            goal: goal,
            asset: asset,
            source: .valueAppreciation
        )
        contribution.assetAmount = 0 // No crypto amount change for appreciation
        contribution.notes = "Value appreciation (rate: \(oldExchangeRate) → \(newExchangeRate))"
        contribution.currencyCode = goal.currency
        contribution.assetSymbol = asset.currency
        contribution.exchangeRateSnapshot = newExchangeRate
        contribution.exchangeRateTimestamp = Date()
        contribution.exchangeRateProvider = exchangeRateProvider

        modelContext.insert(contribution)
        try modelContext.save()

        return contribution
    }

    // MARK: - Query Contributions

    /// Get all contributions for a goal
    func getContributions(for goal: Goal, sortedBy: ContributionSortOrder = .dateDescending) -> [Contribution] {
        let contributions = goal.contributions

        switch sortedBy {
        case .dateAscending:
            return contributions.sorted { $0.date < $1.date }
        case .dateDescending:
            return contributions.sorted { $0.date > $1.date }
        case .amountAscending:
            return contributions.sorted { $0.amount < $1.amount }
        case .amountDescending:
            return contributions.sorted { $0.amount > $1.amount }
        }
    }

    /// Get contributions for a specific month
    func getContributions(for goal: Goal, month: String) -> [Contribution] {
        return goal.contributions.filter { $0.monthLabel == month }
    }

    /// Get contributions grouped by month
    func getContributionsByMonth(for goal: Goal) -> [String: [Contribution]] {
        let contributions = goal.contributions.sorted { $0.date > $1.date }
        return Dictionary(grouping: contributions, by: { $0.monthLabel })
    }

    /// Get total contributions for a goal within a date range
    func getTotalContributions(
        for goal: Goal,
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        excludingSources: [ContributionSource] = []
    ) -> Double {
        var contributions = goal.contributions

        if let start = startDate {
            contributions = contributions.filter { $0.date >= start }
        }

        if let end = endDate {
            contributions = contributions.filter { $0.date <= end }
        }

        if !excludingSources.isEmpty {
            contributions = contributions.filter { !excludingSources.contains($0.sourceType) }
        }

        return contributions.reduce(0) { $0 + $1.amount }
    }

    /// Get contribution statistics for a goal
    func getStatistics(for goal: Goal) -> ContributionStatistics {
        let contributions = goal.contributions

        let deposits = contributions.filter { $0.sourceType == ContributionSource.manualDeposit }
        let reallocations = contributions.filter { $0.sourceType == ContributionSource.assetReallocation }
        let appreciations = contributions.filter { $0.sourceType == ContributionSource.valueAppreciation }

        let totalDeposited = deposits.reduce(0) { $0 + $1.amount }
        let totalReallocated = reallocations.reduce(0) { $0 + $1.amount }
        let totalAppreciation = appreciations.reduce(0) { $0 + $1.amount }

        return ContributionStatistics(
            totalContributions: contributions.count,
            totalAmount: contributions.reduce(0) { $0 + $1.amount },
            totalDeposited: totalDeposited,
            totalReallocated: totalReallocated,
            totalAppreciation: totalAppreciation,
            firstContribution: contributions.min(by: { $0.date < $1.date }),
            lastContribution: contributions.max(by: { $0.date < $1.date })
        )
    }

    // MARK: - Execution Tracking (v2.1)

    /// Link contribution to execution record
    func linkToExecutionRecord(_ contribution: Contribution, recordId: UUID) throws {
        contribution.executionRecordId = recordId
        contribution.isPlanned = true
        try modelContext.save()
    }

    /// Get contributions for specific goal, month, and execution record
    func getContributions(
        for goalId: UUID,
        monthLabel: String,
        executionRecordId: UUID?
    ) throws -> [Contribution] {
        // If executionRecordId is provided, filter by it
        let predicate: Predicate<Contribution>
        if let recordId = executionRecordId {
            predicate = #Predicate<Contribution> { contribution in
                contribution.goal?.id == goalId &&
                contribution.monthLabel == monthLabel &&
                contribution.executionRecordId == recordId
            }
        } else {
            predicate = #Predicate<Contribution> { contribution in
                contribution.goal?.id == goalId &&
                contribution.monthLabel == monthLabel
            }
        }

        let descriptor = FetchDescriptor<Contribution>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date)]
        )

        return try modelContext.fetch(descriptor)
    }

    /// Get all contributions for execution record
    func getContributions(for executionRecordId: UUID) throws -> [Contribution] {
        let predicate = #Predicate<Contribution> { contribution in
            contribution.executionRecordId == executionRecordId
        }

        let descriptor = FetchDescriptor<Contribution>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date)]
        )

        return try modelContext.fetch(descriptor)
    }

    // MARK: - Delete Contributions

    /// Delete a specific contribution
    func deleteContribution(_ contribution: Contribution) throws {
        modelContext.delete(contribution)
        try modelContext.save()
    }

    /// Delete all contributions for a goal (useful when deleting goal)
    func deleteAllContributions(for goal: Goal) throws {
        for contribution in goal.contributions {
            modelContext.delete(contribution)
        }
        try modelContext.save()
    }
}

// MARK: - Supporting Types

enum ContributionSortOrder {
    case dateAscending
    case dateDescending
    case amountAscending
    case amountDescending
}

struct ContributionStatistics {
    let totalContributions: Int
    let totalAmount: Double
    let totalDeposited: Double
    let totalReallocated: Double
    let totalAppreciation: Double
    let firstContribution: Contribution?
    let lastContribution: Contribution?

    var averageContribution: Double {
        totalContributions > 0 ? totalAmount / Double(totalContributions) : 0
    }
}
