//
//  GoalCalculationService.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import Foundation
import SwiftData

/// Service for performing goal calculations with proper separation of concerns
/// This avoids having model objects directly instantiate ViewModels
@MainActor
class GoalCalculationService: GoalCalculationServiceProtocol {
    private let exchangeRateService: ExchangeRateServiceProtocol
    private let tatumService: TatumServiceProtocol
    private let modelContext: ModelContext?

    init(exchangeRateService: ExchangeRateServiceProtocol,
         tatumService: TatumServiceProtocol,
         modelContext: ModelContext? = nil) {
        self.exchangeRateService = exchangeRateService
        self.tatumService = tatumService
        self.modelContext = modelContext
    }

    @MainActor
    convenience init(container: DIContainer? = nil, modelContext: ModelContext? = nil) {
        let resolvedContainer = container ?? DIContainer.shared
        self.init(
            exchangeRateService: resolvedContainer.exchangeRateService,
            tatumService: resolvedContainer.tatumService,
            modelContext: modelContext
        )
    }

    // Instance methods prefer injected services (better for testing)
    func getCurrentTotal(for goal: Goal) async -> Double {
        let viewModel = GoalViewModel(
            goal: goal,
            tatumService: tatumService,
            exchangeRateService: exchangeRateService
        )
        await viewModel.refreshValues()
        return viewModel.currentTotal
    }

    func getProgress(for goal: Goal) async -> Double {
        let total = await getCurrentTotal(for: goal)
        guard goal.targetAmount > 0 else { return 0 }
        return min(total / goal.targetAmount, 1.0)
    }

    func getSuggestedDeposit(for goal: Goal) async -> Double {
        let total = await getCurrentTotal(for: goal)
        let remainingDates = Self.getRemainingReminderDates(for: goal)
        guard remainingDates.count > 0, goal.targetAmount > 0 else { return 0 }
        let remainingAmount = max(goal.targetAmount - total, 0)
        return remainingAmount / Double(remainingDates.count)
    }

    // MARK: - REMOVED: Contribution-Aware Calculations
    // These methods were implementing DOUBLE-COUNTING by adding contributions to asset totals.
    // Contributions are TRACKING RECORDS for monthly plan fulfillment, NOT part of goal totals.
    //
    // Correct calculation: Goal Total = Asset Values ONLY
    // Monthly fulfillment = sum(contributions for current month)
    //
    // The following methods have been removed:
    // - getCurrentTotalWithContributions() [DOUBLE-COUNTING BUG]
    // - getProgressWithContributions() [DOUBLE-COUNTING BUG]
    // - getSuggestedDepositWithContributions() [DOUBLE-COUNTING BUG]
    //
    // All callers should use:
    // - getCurrentTotal(for:) for asset-only totals
    // - Separate contribution queries for monthly plan tracking

    /// Calculate current total for a goal using proper ViewModel delegation
    @MainActor static func getCurrentTotal(for goal: Goal) async -> Double {
        let viewModel = GoalViewModel(goal: goal)
        await viewModel.refreshValues()
        return viewModel.currentTotal
    }
    
    /// Calculate progress percentage for a goal
    @MainActor static func getProgress(for goal: Goal) async -> Double {
        let total = await getCurrentTotal(for: goal)
        guard goal.targetAmount > 0 else { return 0 }
        return min(total / goal.targetAmount, 1.0)
    }
    
    /// Calculate suggested daily deposit based on remaining time and target
    @MainActor static func getSuggestedDeposit(for goal: Goal) async -> Double {
        let total = await getCurrentTotal(for: goal)
        let remainingDates = getRemainingReminderDates(for: goal)
        guard remainingDates.count > 0, goal.targetAmount > 0 else { return 0 }
        
        let remainingAmount = max(goal.targetAmount - total, 0)
        return remainingAmount / Double(remainingDates.count)
    }
    
    /// Calculate days remaining until goal deadline
    nonisolated static func getDaysRemaining(for goal: Goal) -> Int {
        let components = Calendar.current.dateComponents([.day], from: Date(), to: goal.deadline)
        return max(components.day ?? 0, 0)
    }
    
    /// Check if goal has reminders enabled
    nonisolated static func isReminderEnabled(for goal: Goal) -> Bool {
        return goal.reminderFrequency != nil
    }
    
    /// Get reminder frequency enum from goal
    nonisolated static func getReminderFrequency(for goal: Goal) -> ReminderFrequency {
        guard let freq = goal.reminderFrequency,
              let reminder = ReminderFrequency(rawValue: freq) else {
            return .weekly
        }
        return reminder
    }
    
    /// Calculate all reminder dates for a goal
    nonisolated static func getReminderDates(for goal: Goal) -> [Date] {
        guard isReminderEnabled(for: goal), let time = goal.reminderTime else { return [] }
        
        var dates: [Date] = []
        let calendar = Calendar.current
        let frequency = getReminderFrequency(for: goal)
        
        // Get time components from reminderTime
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        let hour = timeComponents.hour ?? 9
        let minute = timeComponents.minute ?? 0
        
        // Start from the first reminder date if set, otherwise use goal start date with preferred time
        let baseDate = goal.firstReminderDate ?? goal.startDate
        guard var currentDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate) else { return [] }
        
        // Generate dates based on frequency
        while currentDate <= goal.deadline {
            dates.append(currentDate)
            
            guard let nextDate = calendar.date(byAdding: frequency.dateComponents, to: currentDate) else { break }
            currentDate = nextDate
        }
        
        return dates
    }
    
    /// Get remaining reminder dates (future dates only)
    nonisolated static func getRemainingReminderDates(for goal: Goal) -> [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return getReminderDates(for: goal).filter { Calendar.current.startOfDay(for: $0) >= today }
    }
    
    /// Get next upcoming reminder date
    nonisolated static func getNextReminder(for goal: Goal) -> Date? {
        let now = Date()
        return getReminderDates(for: goal).first { $0 > now }
    }
    
    /// Calculate manual balance total (transactions only, no API calls)
    nonisolated static func getManualTotal(for goal: Goal) -> Double {
        return goal.allocations.reduce(0) { result, allocation in
            guard let asset = allocation.asset else { return result }
            let allocatedPortion = min(max(0, allocation.amountValue), asset.manualBalance)
            return result + allocatedPortion
        }
    }
    
    /// Calculate basic progress using manual balance only
    nonisolated static func getManualProgress(for goal: Goal) -> Double {
        let total = getManualTotal(for: goal)
        guard goal.targetAmount > 0 else { return 0 }
        return min(total / goal.targetAmount, 1.0)
    }
    
    // MARK: - Allocation-Aware Calculations
    
    /// Calculate total value for a goal including both manual balance and on-chain balance with currency conversion
    /// This method properly handles asset allocations and currency conversions
    @MainActor static func getTotalValue(for goal: Goal) async -> Double {
        var totalValue = 0.0
        
        for allocation in goal.allocations {
            guard let asset = allocation.asset else { continue }
            
            // Get the asset's total value (including on-chain balance if available)
            let assetViewModel = AssetViewModel(asset: asset, tatumService: DIContainer.shared.tatumService)
            await assetViewModel.refreshBalances()
            
            // Get asset value in the goal's currency
            let assetValueInGoalCurrency = await getAssetValueInGoalCurrency(
                asset: asset,
                goalCurrency: goal.currency,
                assetViewModel: assetViewModel
            )
            
            // Calculate allocated portion using the fixed-amount allocation target.
            let assetBalance = assetViewModel.totalBalance
            let allocatedPortion = min(max(0, allocation.amountValue), assetBalance)
            
            // Add the allocated portion to the total
            let totalAssetValue = assetBalance > 0 ? assetValueInGoalCurrency : 0
            let ratio = assetBalance > 0 ? allocatedPortion / assetBalance : 0
            totalValue += totalAssetValue * ratio
        }
        
        return totalValue
    }
    
    /// Helper method to get asset value in the goal's currency
    @MainActor
    private static func getAssetValueInGoalCurrency(
        asset: Asset,
        goalCurrency: String,
        assetViewModel: AssetViewModel
    ) async -> Double {
        let totalAssetValue = assetViewModel.totalBalance
        
        // If asset currency matches goal currency, no conversion needed
        if asset.currency.uppercased() == goalCurrency.uppercased() {
            return totalAssetValue
        }
        
        // Convert from asset currency to goal currency
        do {
            let exchangeRate = try await DIContainer.shared.exchangeRateService.fetchRate(
                from: asset.currency,
                to: goalCurrency
            )
            return totalAssetValue * exchangeRate
        } catch {
            print("Failed to get exchange rate from \(asset.currency) to \(goalCurrency): \(error)")
            // Fallback to manual balance only if conversion fails
            return asset.manualBalance
        }
    }
    
    /// Get allocated value from a specific asset to a goal
    @MainActor static func getAllocatedValue(from asset: Asset, to goal: Goal) async -> Double {
        guard let allocation = goal.allocations.first(where: { $0.asset?.id == asset.id }) else {
            return 0.0
        }
        
        let assetViewModel = AssetViewModel(asset: asset, tatumService: DIContainer.shared.tatumService)
        await assetViewModel.refreshBalances()
        
        let assetValueInGoalCurrency = await getAssetValueInGoalCurrency(
            asset: asset,
            goalCurrency: goal.currency,
            assetViewModel: assetViewModel
        )
        
        let assetBalance = assetViewModel.totalBalance
        let allocatedPortion = min(max(0, allocation.amountValue), assetBalance)
        let ratio = assetBalance > 0 ? allocatedPortion / assetBalance : 0
        return assetValueInGoalCurrency * ratio
    }
    
    /// Get a breakdown of value contributions from each asset to a goal
    @MainActor static func getValueBreakdown(for goal: Goal) async -> [(asset: Asset, value: Double, percentage: Double)] {
        var breakdown: [(asset: Asset, value: Double, percentage: Double)] = []
        
        for allocation in goal.allocations {
            guard let asset = allocation.asset else { continue }
            
            let allocatedValue = await getAllocatedValue(from: asset, to: goal)
            
            breakdown.append((
                asset: asset,
                value: allocatedValue,
                percentage: 0 // percentage no longer relevant
            ))
        }
        
        return breakdown.sorted { $0.value > $1.value }
    }
}
