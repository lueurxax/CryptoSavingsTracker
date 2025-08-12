//
//  DashboardViewModel.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var balanceHistory: [BalanceHistoryPoint] = []
    @Published var assetComposition: [AssetComposition] = []
    @Published var forecastData: [ForecastPoint] = []
    @Published var heatmapData: [HeatmapDay] = []
    @Published var transactionCount: Int = 0
    @Published var daysRemaining: Int = 0
    @Published var dailyTarget: Double = 0
    @Published var streak: Int = 0
    
    // Loading states
    @Published var isLoading: Bool = false
    @Published var balanceHistoryState: ChartLoadingState = .idle
    @Published var assetCompositionState: ChartLoadingState = .idle
    @Published var forecastState: ChartLoadingState = .idle
    @Published var heatmapState: ChartLoadingState = .idle
    
    // Computed loading states for backward compatibility
    var isLoadingBalanceHistory: Bool { balanceHistoryState.isLoading }
    var isLoadingAssetComposition: Bool { assetCompositionState.isLoading }
    var isLoadingForecast: Bool { forecastState.isLoading }
    var isLoadingHeatmap: Bool { heatmapState.isLoading }
    
    private let exchangeRateService = ExchangeRateService.shared
    private let balanceService = BalanceService.shared
    private let transactionService = TransactionService.shared
    
    private var currentGoal: Goal?
    
    func loadData(for goal: Goal, modelContext: ModelContext) async {
        currentGoal = goal
        
        // Set global loading state
        isLoading = true
        balanceHistoryState = .loading
        assetCompositionState = .loading
        heatmapState = .loading
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask { 
                await self.loadBalanceHistory(for: goal, modelContext: modelContext)
            }
            group.addTask { 
                await self.loadAssetComposition(for: goal)
            }
            group.addTask { 
                await self.loadTransactionData(for: goal, modelContext: modelContext)
            }
            group.addTask { await self.calculateMetrics(for: goal) }
        }
        
        // Generate forecast after balance history is loaded
        forecastState = .loading
        await generateForecastData(for: goal)
        
        // All loading complete
        isLoading = false
    }
    
    private func loadBalanceHistory(for goal: Goal, modelContext: ModelContext) async {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .month, value: -3, to: endDate) ?? endDate
        
        var history: [BalanceHistoryPoint] = []
        var currentDate = startDate
        
        // Generate weekly data points instead of daily for better performance
        while currentDate <= endDate {
            // Calculate total balance for this date by querying transactions up to this date
            var totalBalance: Double = 0
            
            for asset in goal.assets {
                // For historical dates, use transaction-based calculation only
                // For recent dates (last 7 days), include on-chain balance if available
                let isRecentDate = currentDate >= calendar.date(byAdding: .day, value: -7, to: endDate)!
                
                var assetBalance: Double = 0
                
                if isRecentDate && (asset.address != nil || asset.chainId != nil) {
                    // Use current on-chain balance for recent dates
                    assetBalance = await AssetViewModel.getCurrentAmount(for: asset)
                } else {
                    // Use transaction history for older dates
                    let transactions = asset.transactions.filter { $0.date <= currentDate }
                    assetBalance = transactions.reduce(0) { $0 + $1.amount }
                }
                
                // Convert to goal currency if needed
                if asset.currency != goal.currency {
                    do {
                        let rate = try await exchangeRateService.fetchRate(
                            from: asset.currency,
                            to: goal.currency
                        )
                        totalBalance += assetBalance * rate
                    } catch {
                        // Use asset balance as is if conversion fails
                        AppLog.error("Currency conversion failed for \(asset.currency) to \(goal.currency): \(error)", category: .exchangeRate)
                        totalBalance += assetBalance
                    }
                } else {
                    totalBalance += assetBalance
                }
            }
            
            history.append(BalanceHistoryPoint(
                date: currentDate,
                balance: totalBalance,
                currency: goal.currency
            ))
            
            currentDate = calendar.date(byAdding: .weekOfYear, value: 1, to: currentDate) ?? endDate
        }
        
        // Ensure we always have at least the current balance as the most recent point
        if history.isEmpty || (history.last?.date ?? Date.distantPast) < calendar.date(byAdding: .day, value: -1, to: endDate)! {
            let currentTotal = await GoalCalculationService.getCurrentTotal(for: goal)
            history.append(BalanceHistoryPoint(
                date: endDate,
                balance: currentTotal,
                currency: goal.currency
            ))
        }
        
        // If we have very little data, create more realistic baseline points
        if history.count < 3 {
            let currentTotal = await GoalCalculationService.getCurrentTotal(for: goal)
            
            // Only create artificial history if we actually have a meaningful current total
            if currentTotal > 0 {
                let weekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: endDate) ?? endDate
                let monthAgo = calendar.date(byAdding: .month, value: -1, to: endDate) ?? endDate
                
                // Create more realistic progression by analyzing transaction history
                var baselineHistory: [BalanceHistoryPoint] = []
                
                // Calculate actual balance progression based on transaction dates
                let allTransactions = goal.assets.flatMap { $0.transactions }.sorted { $0.date < $1.date }
                
                if !allTransactions.isEmpty {
                    // Use actual transaction-based progression
                    var runningBalance: Double = 0
                    var lastTransactionDate = allTransactions.first!.date
                    
                    // Add starting point
                    baselineHistory.append(BalanceHistoryPoint(
                        date: max(monthAgo, lastTransactionDate),
                        balance: 0,
                        currency: goal.currency
                    ))
                    
                    // Add points at key transaction milestones
                    let transactionMilestones = allTransactions.enumerated().compactMap { index, transaction in
                        runningBalance += transaction.amount
                        // Only add milestone if it's a significant change or time gap
                        if index == allTransactions.count - 1 || 
                           abs(transaction.amount) > currentTotal * 0.1 ||
                           transaction.date.timeIntervalSince(lastTransactionDate) > 86400 * 7 { // 7 days
                            lastTransactionDate = transaction.date
                            return BalanceHistoryPoint(
                                date: transaction.date,
                                balance: max(0, runningBalance),
                                currency: goal.currency
                            )
                        }
                        return nil
                    }
                    
                    baselineHistory.append(contentsOf: transactionMilestones.prefix(5)) // Limit to 5 points
                } else {
                    // No transactions - create minimal realistic progression
                    baselineHistory = [
                        BalanceHistoryPoint(date: monthAgo, balance: 0, currency: goal.currency),
                        BalanceHistoryPoint(date: weekAgo, balance: currentTotal * 0.3, currency: goal.currency),
                        BalanceHistoryPoint(date: endDate, balance: currentTotal, currency: goal.currency)
                    ]
                }
                
                history = baselineHistory
            } else {
                // No meaningful balance - show flat zero line
                history = [
                    BalanceHistoryPoint(date: calendar.date(byAdding: .month, value: -1, to: endDate) ?? endDate, balance: 0, currency: goal.currency),
                    BalanceHistoryPoint(date: endDate, balance: 0, currency: goal.currency)
                ]
            }
        }
        
        // Debug: Print balance history info
        AppLog.debug("Generated \(history.count) balance history points for goal: \(goal.name)", category: .performance)
        if let first = history.first, let last = history.last {
            AppLog.debug("Balance history range: \(first.balance) to \(last.balance)", category: .performance)
        }
        
            balanceHistory = history
            balanceHistoryState = .loaded
    }
    
    private func loadAssetComposition(for goal: Goal) async {
        let totalValue = await GoalCalculationService.getCurrentTotal(for: goal)
        guard totalValue > 0 else {
            assetComposition = []
            assetCompositionState = .loaded
            return
        }
        
        let colors = AccessibleColors.chartColors
        var composition: [AssetComposition] = []
        
        for (index, asset) in goal.assets.enumerated() {
            let assetValue = await getAssetValueInGoalCurrency(asset: asset, goalCurrency: goal.currency)
            let percentage = (assetValue / totalValue) * 100
            
            composition.append(AssetComposition(
                currency: asset.currency,
                value: assetValue,
                percentage: percentage,
                color: colors[index % colors.count]
            ))
        }
        
            assetComposition = composition.sorted { $0.value > $1.value }
            assetCompositionState = .loaded
    }
    
    private func loadTransactionData(for goal: Goal, modelContext: ModelContext) async {
        var totalTransactions = 0
        var activityData: [HeatmapDay] = []
        
        // Collect all transactions from all assets
        let allTransactions = goal.assets.flatMap { $0.transactions }
        totalTransactions = allTransactions.count
        
        // Generate heatmap data for the last year
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .year, value: -1, to: endDate) ?? endDate
        
        var currentDate = startDate
        while currentDate <= endDate {
            let dayTransactions = allTransactions.filter { 
                calendar.isDate($0.date, inSameDayAs: currentDate) 
            }
            
            let dayValue = dayTransactions.reduce(0) { $0 + abs($1.amount) }
            let transactionCount = dayTransactions.count
            
            // Calculate intensity based on both transaction count and value
            // Use transaction count as primary factor, value as secondary
            let countIntensity = min(Double(transactionCount) / 5.0, 1.0) // Scale to 5 transactions = 100% intensity
            let valueIntensity = min(dayValue / 1000.0, 1.0) // Scale to 1000 value = 100% intensity
            let combinedIntensity = max(countIntensity, valueIntensity * 0.5) // Favor count over value
            
            activityData.append(HeatmapDay(
                date: currentDate,
                value: dayValue,
                intensity: combinedIntensity,
                transactionCount: transactionCount
            ))
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? endDate
        }
        
        transactionCount = totalTransactions
        heatmapData = activityData
        
            // Calculate streak
            calculateStreak(from: activityData)
            heatmapState = .loaded
    }
    
    private func calculateMetrics(for goal: Goal) async {
        let calendar = Calendar.current
        let now = Date()
        
        // Days remaining
        let days = calendar.dateComponents([.day], from: now, to: goal.deadline).day ?? 0
        daysRemaining = max(0, days)
        
        // Daily target to reach goal
        let currentTotal = await GoalCalculationService.getCurrentTotal(for: goal)
        let remaining = max(0, goal.targetAmount - currentTotal)
        dailyTarget = daysRemaining > 0 ? remaining / Double(daysRemaining) : 0
    }
    
    private func generateForecastData(for goal: Goal) async {
        guard !balanceHistory.isEmpty else {
            forecastData = []
            return
        }
        
        let calendar = Calendar.current
        let startDate = Date()
        let endDate = goal.deadline
        
        // Calculate historical growth rate
        let recentHistory = Array(balanceHistory.suffix(30)) // Last 30 days
        let growthRate = calculateGrowthRate(from: recentHistory)
        
        var forecast: [ForecastPoint] = []
        var currentDate = startDate
        let currentBalance = await GoalCalculationService.getCurrentTotal(for: goal)
        
        while currentDate <= endDate {
            let daysFromNow = calendar.dateComponents([.day], from: startDate, to: currentDate).day ?? 0
            
            // Calculate three scenarios
            let optimisticGrowth = growthRate * 1.5
            let realisticGrowth = growthRate
            let pessimisticGrowth = growthRate * 0.5
            
            let optimistic = currentBalance + (optimisticGrowth * Double(daysFromNow))
            let realistic = currentBalance + (realisticGrowth * Double(daysFromNow))
            let pessimistic = currentBalance + (pessimisticGrowth * Double(daysFromNow))
            
            forecast.append(ForecastPoint(
                date: currentDate,
                optimistic: max(optimistic, 0),
                realistic: max(realistic, 0),
                pessimistic: max(pessimistic, 0)
            ))
            
            currentDate = calendar.date(byAdding: .day, value: 7, to: currentDate) ?? endDate
        }
        
            forecastData = forecast
            forecastState = .loaded
    }
    
    private func calculateGrowthRate(from history: [BalanceHistoryPoint]) -> Double {
        guard history.count >= 2 else { return 0 }
        
        let first = history.first!.balance
        let last = history.last!.balance
        let days = Double(history.count)
        
        return days > 0 ? (last - first) / days : 0
    }
    
    private func calculateStreak(from heatmapData: [HeatmapDay]) {
        let activeDays = heatmapData
            .filter { $0.value > 0 }
            .sorted { $0.date > $1.date } // Most recent first
        
        var currentStreak = 0
        let calendar = Calendar.current
        var expectedDate = Date()
        
        for day in activeDays {
            if calendar.isDate(day.date, inSameDayAs: expectedDate) {
                currentStreak += 1
                expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate) ?? expectedDate
            } else {
                break
            }
        }
        
        streak = currentStreak
    }
    
    private func getAssetValueInGoalCurrency(asset: Asset, goalCurrency: String) async -> Double {
        let assetBalance = await AssetViewModel.getCurrentAmount(for: asset)
        
        if asset.currency == goalCurrency {
            return assetBalance
        }
        
        do {
            let rate = try await exchangeRateService.fetchRate(
                from: asset.currency,
                to: goalCurrency
            )
            return assetBalance * rate
        } catch {
            AppLog.error("Failed to get exchange rate for \(asset.currency) to \(goalCurrency): \(error)", category: .exchangeRate)
            return assetBalance // Return original value if conversion fails
        }
    }
    
    // MARK: - Retry Methods
    func retryBalanceHistory(for goal: Goal, modelContext: ModelContext) async {
        balanceHistoryState = .loading
        await loadBalanceHistory(for: goal, modelContext: modelContext)
    }
    
    func retryAssetComposition(for goal: Goal) async {
        assetCompositionState = .loading
        await loadAssetComposition(for: goal)
    }
    
    func retryHeatmapData(for goal: Goal, modelContext: ModelContext) async {
        heatmapState = .loading
        await loadTransactionData(for: goal, modelContext: modelContext)
    }
    
    func retryForecastData(for goal: Goal) async {
        forecastState = .loading
        await generateForecastData(for: goal)
    }
}