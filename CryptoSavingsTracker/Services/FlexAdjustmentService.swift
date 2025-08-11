//
//  FlexAdjustmentService.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 09/08/2025.
//

import Foundation
import SwiftData

// MARK: - Supporting Types


struct RedistributionResult: Sendable {
    let adjustedRequirements: [AdjustedRequirement]
    let totalOriginal: Double
    let totalAdjusted: Double
    let redistribution: Double
    let strategy: RedistributionStrategy
    let timestamp: Date
    let totalExcess: Double
    let totalDeficit: Double
    let redistributionSummary: RedistributionSummary
    
    init(adjustedRequirements: [AdjustedRequirement], totalOriginal: Double = 0, totalAdjusted: Double = 0, redistribution: Double = 0, strategy: RedistributionStrategy = .balanced, timestamp: Date = Date(), totalExcess: Double, totalDeficit: Double, redistributionSummary: RedistributionSummary) {
        self.adjustedRequirements = adjustedRequirements
        self.totalOriginal = totalOriginal
        self.totalAdjusted = totalAdjusted
        self.redistribution = redistribution
        self.strategy = strategy
        self.timestamp = timestamp
        self.totalExcess = totalExcess
        self.totalDeficit = totalDeficit
        self.redistributionSummary = redistributionSummary
    }
    
    var adjustmentRatio: Double {
        guard totalOriginal > 0 else { return 0 }
        return totalAdjusted / totalOriginal
    }
    
    var isReduction: Bool {
        totalAdjusted < totalOriginal
    }
    
    var isIncrease: Bool {
        totalAdjusted > totalOriginal
    }
}

struct AdjustedRequirement: Identifiable, Sendable {
    let id = UUID()
    let requirement: MonthlyRequirement
    let adjustedAmount: Double
    let adjustmentReason: String
    let isProtected: Bool
    let isSkipped: Bool
    let adjustmentFactor: Double
    let redistributionAmount: Double
    let impactAnalysis: ImpactAnalysis
    
    init(requirement: MonthlyRequirement, adjustedAmount: Double, adjustmentReason: String = "", isProtected: Bool = false, isSkipped: Bool = false, adjustmentFactor: Double = 1.0, redistributionAmount: Double = 0.0, impactAnalysis: ImpactAnalysis? = nil) {
        self.requirement = requirement
        self.adjustedAmount = max(0, adjustedAmount) // Ensure non-negative
        self.adjustmentReason = adjustmentReason
        self.isProtected = isProtected
        self.isSkipped = isSkipped
        self.adjustmentFactor = adjustmentFactor
        self.redistributionAmount = redistributionAmount
        self.impactAnalysis = impactAnalysis ?? ImpactAnalysis(changeAmount: 0, changePercentage: 0, estimatedDelay: 0, riskLevel: .low)
    }
    
    var adjustmentPercentage: Double {
        guard requirement.requiredMonthly > 0 else { return 0 }
        return adjustedAmount / requirement.requiredMonthly
    }
    
    var hasBeenReduced: Bool {
        adjustedAmount < requirement.requiredMonthly
    }
    
    var hasBeenIncreased: Bool {
        adjustedAmount > requirement.requiredMonthly
    }
}

/// Advanced service for handling flexible payment adjustments with intelligent redistribution
@MainActor
final class FlexAdjustmentService {
    
    // MARK: - Dependencies
    
    private let exchangeRateService: ExchangeRateService
    private let modelContext: ModelContext
    
    // MARK: - Cache
    
    private var redistributionCache: [String: RedistributionResult] = [:]
    private var lastCacheUpdate: Date?
    private let cacheExpiration: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    init(exchangeRateService: ExchangeRateService, modelContext: ModelContext) {
        self.exchangeRateService = exchangeRateService
        self.modelContext = modelContext
    }
    
    // MARK: - Public Methods
    
    /// Apply flex adjustment with intelligent redistribution
    /// - Parameters:
    ///   - requirements: Array of monthly requirements
    ///   - adjustment: Overall adjustment factor (0.0 to 2.0)
    ///   - protectedGoalIds: Goals that cannot be reduced
    ///   - skippedGoalIds: Goals to skip entirely
    ///   - strategy: Redistribution strategy to use
    /// - Returns: Array of adjusted requirements with redistribution applied
    func applyFlexAdjustment(
        requirements: [MonthlyRequirement],
        adjustment: Double,
        protectedGoalIds: Set<UUID>,
        skippedGoalIds: Set<UUID>,
        strategy: RedistributionStrategy = .balanced
    ) async -> [AdjustedRequirement] {
        
        // Create cache key
        let cacheKey = createCacheKey(
            requirements: requirements,
            adjustment: adjustment,
            protectedGoalIds: protectedGoalIds,
            skippedGoalIds: skippedGoalIds,
            strategy: strategy
        )
        
        // Check cache
        if let cached = getCachedResult(for: cacheKey) {
            return cached.adjustedRequirements
        }
        
        // Perform adjustment calculation
        let result = await calculateAdjustment(
            requirements: requirements,
            adjustment: adjustment,
            protectedGoalIds: protectedGoalIds,
            skippedGoalIds: skippedGoalIds,
            strategy: strategy
        )
        
        // Cache result
        redistributionCache[cacheKey] = result
        lastCacheUpdate = Date()
        
        return result.adjustedRequirements
    }
    
    /// Calculate optimal adjustment that meets a target total
    /// - Parameters:
    ///   - requirements: Array of monthly requirements
    ///   - targetTotal: Desired total amount
    ///   - protectedGoalIds: Goals that cannot be adjusted
    ///   - skippedGoalIds: Goals to skip entirely
    ///   - displayCurrency: Currency for total calculation
    /// - Returns: Optimal adjustment factor and resulting requirements
    func calculateOptimalAdjustment(
        requirements: [MonthlyRequirement],
        targetTotal: Double,
        protectedGoalIds: Set<UUID>,
        skippedGoalIds: Set<UUID>,
        displayCurrency: String
    ) async -> OptimalAdjustmentResult {
        
        // Calculate current total in display currency
        let currentTotal = await calculateTotal(
            requirements: requirements,
            protectedGoalIds: protectedGoalIds,
            skippedGoalIds: skippedGoalIds,
            displayCurrency: displayCurrency
        )
        
        // Calculate protected total (cannot be adjusted)
        let protectedTotal = await calculateProtectedTotal(
            requirements: requirements,
            protectedGoalIds: protectedGoalIds,
            displayCurrency: displayCurrency
        )
        
        // Calculate flexible total (can be adjusted)
        let flexibleTotal = currentTotal - protectedTotal
        
        // If no flexible amount or target is less than protected, return minimum viable
        guard flexibleTotal > 0, targetTotal >= protectedTotal else {
            let minViableAdjustments = requirements.map { requirement in
                AdjustedRequirement(
                    requirement: requirement,
                    adjustedAmount: protectedGoalIds.contains(requirement.goalId) ? requirement.requiredMonthly : 0,
                    adjustmentFactor: protectedGoalIds.contains(requirement.goalId) ? 1.0 : 0.0,
                    redistributionAmount: 0,
                    impactAnalysis: calculateImpact(
                        original: requirement.requiredMonthly,
                        adjusted: protectedGoalIds.contains(requirement.goalId) ? requirement.requiredMonthly : 0,
                        deadline: requirement.deadline
                    )
                )
            }
            
            return OptimalAdjustmentResult(
                adjustmentFactor: 0.0,
                adjustedRequirements: minViableAdjustments,
                achievedTotal: protectedTotal,
                targetTotal: targetTotal,
                redistribution: RedistributionSummary(
                    totalReduced: currentTotal - protectedTotal,
                    totalRedistributed: 0,
                    affectedGoals: requirements.count - protectedGoalIds.count
                )
            )
        }
        
        // Calculate required adjustment for flexible goals
        let availableForFlexible = targetTotal - protectedTotal
        let adjustmentFactor = availableForFlexible / flexibleTotal
        
        // Apply adjustment with redistribution
        let adjustedRequirements = await applyFlexAdjustment(
            requirements: requirements,
            adjustment: adjustmentFactor,
            protectedGoalIds: protectedGoalIds,
            skippedGoalIds: skippedGoalIds,
            strategy: .balanced
        )
        
        // Calculate achieved total
        let achievedTotal = await calculateAdjustedTotal(
            adjustedRequirements: adjustedRequirements,
            displayCurrency: displayCurrency
        )
        
        return OptimalAdjustmentResult(
            adjustmentFactor: adjustmentFactor,
            adjustedRequirements: adjustedRequirements,
            achievedTotal: achievedTotal,
            targetTotal: targetTotal,
            redistribution: calculateRedistributionSummary(adjustedRequirements)
        )
    }
    
    /// Simulate adjustment impact without applying changes
    /// - Parameters:
    ///   - requirements: Array of monthly requirements
    ///   - adjustment: Proposed adjustment factor
    ///   - protectedGoalIds: Goals that cannot be adjusted
    ///   - skippedGoalIds: Goals to skip entirely
    /// - Returns: Simulation results with impact analysis
    func simulateAdjustment(
        requirements: [MonthlyRequirement],
        adjustment: Double,
        protectedGoalIds: Set<UUID>,
        skippedGoalIds: Set<UUID>
    ) async -> AdjustmentSimulation {
        
        let adjustedRequirements = await applyFlexAdjustment(
            requirements: requirements,
            adjustment: adjustment,
            protectedGoalIds: protectedGoalIds,
            skippedGoalIds: skippedGoalIds,
            strategy: .balanced
        )
        
        var riskAnalysis: [UUID: RiskLevel] = [:]
        var delayEstimates: [UUID: Int] = [:]
        
        for adjusted in adjustedRequirements {
            let risk = calculateRiskLevel(adjusted)
            riskAnalysis[adjusted.requirement.goalId] = risk
            
            if adjusted.adjustedAmount < adjusted.requirement.requiredMonthly {
                let delayMonths = estimateDelay(adjusted)
                delayEstimates[adjusted.requirement.goalId] = delayMonths
            }
        }
        
        return AdjustmentSimulation(
            adjustedRequirements: adjustedRequirements,
            riskAnalysis: riskAnalysis,
            delayEstimates: delayEstimates,
            totalSavings: calculateTotalSavings(requirements, adjustedRequirements),
            redistribution: calculateRedistributionSummary(adjustedRequirements)
        )
    }
    
    /// Clear adjustment cache
    func clearCache() {
        redistributionCache.removeAll()
        lastCacheUpdate = nil
    }
    
    // MARK: - Private Methods
    
    /// Perform the core adjustment calculation with redistribution
    private func calculateAdjustment(
        requirements: [MonthlyRequirement],
        adjustment: Double,
        protectedGoalIds: Set<UUID>,
        skippedGoalIds: Set<UUID>,
        strategy: RedistributionStrategy
    ) async -> RedistributionResult {
        
        // Separate requirements into categories
        let (protected, flexible, skipped) = categorizeRequirements(
            requirements,
            protectedGoalIds: protectedGoalIds,
            skippedGoalIds: skippedGoalIds
        )
        
        // Apply base adjustment to flexible goals
        var adjustedRequirements: [AdjustedRequirement] = []
        var excessAmount: Double = 0
        var deficitAmount: Double = 0
        
        // Process flexible goals with base adjustment
        for requirement in flexible {
            let baseAdjustment = requirement.requiredMonthly * adjustment
            let (finalAmount, excess, deficit) = applyConstraints(
                originalAmount: requirement.requiredMonthly,
                adjustedAmount: baseAdjustment,
                requirement: requirement
            )
            
            adjustedRequirements.append(AdjustedRequirement(
                requirement: requirement,
                adjustedAmount: finalAmount,
                adjustmentFactor: adjustment,
                redistributionAmount: 0, // Will be calculated in redistribution
                impactAnalysis: calculateImpact(
                    original: requirement.requiredMonthly,
                    adjusted: finalAmount,
                    deadline: requirement.deadline
                )
            ))
            
            excessAmount += excess
            deficitAmount += deficit
        }
        
        // Add protected goals (unchanged)
        for requirement in protected {
            adjustedRequirements.append(AdjustedRequirement(
                requirement: requirement,
                adjustedAmount: requirement.requiredMonthly,
                adjustmentFactor: 1.0,
                redistributionAmount: 0,
                impactAnalysis: ImpactAnalysis(
                    changeAmount: 0,
                    changePercentage: 0,
                    estimatedDelay: 0,
                    riskLevel: .low
                )
            ))
        }
        
        // Add skipped goals (zero amount)
        for requirement in skipped {
            adjustedRequirements.append(AdjustedRequirement(
                requirement: requirement,
                adjustedAmount: 0,
                adjustmentFactor: 0.0,
                redistributionAmount: 0,
                impactAnalysis: calculateImpact(
                    original: requirement.requiredMonthly,
                    adjusted: 0,
                    deadline: requirement.deadline
                )
            ))
        }
        
        // Apply redistribution strategy
        let redistributedRequirements = await applyRedistribution(
            adjustedRequirements: adjustedRequirements,
            excessAmount: excessAmount,
            deficitAmount: deficitAmount,
            strategy: strategy,
            protectedGoalIds: protectedGoalIds,
            skippedGoalIds: skippedGoalIds
        )
        
        return RedistributionResult(
            adjustedRequirements: redistributedRequirements,
            totalExcess: excessAmount,
            totalDeficit: deficitAmount,
            redistributionSummary: calculateRedistributionSummary(redistributedRequirements)
        )
    }
    
    /// Apply redistribution strategy to balance excess and deficit amounts
    private func applyRedistribution(
        adjustedRequirements: [AdjustedRequirement],
        excessAmount: Double,
        deficitAmount: Double,
        strategy: RedistributionStrategy,
        protectedGoalIds: Set<UUID>,
        skippedGoalIds: Set<UUID>
    ) async -> [AdjustedRequirement] {
        
        var requirements = adjustedRequirements
        let netExcess = excessAmount - deficitAmount
        
        guard netExcess > 1.0 else { return requirements } // No meaningful redistribution needed
        
        // Find eligible goals for redistribution (flexible goals that can accept more)
        let eligibleForIncrease = requirements.filter { adjusted in
            !protectedGoalIds.contains(adjusted.requirement.goalId) &&
            !skippedGoalIds.contains(adjusted.requirement.goalId) &&
            adjusted.adjustedAmount > 0 &&
            canAcceptAdditionalAmount(adjusted)
        }
        
        guard !eligibleForIncrease.isEmpty else { return requirements }
        
        // Apply redistribution based on strategy
        switch strategy {
        case .balanced:
            return applyBalancedRedistribution(requirements, netExcess: netExcess, eligibleGoals: eligibleForIncrease)
        case .prioritizeUrgent:
            return applyUrgencyBasedRedistribution(requirements, netExcess: netExcess, eligibleGoals: eligibleForIncrease)
        case .prioritizeLargest:
            return applyVolumeBasedRedistribution(requirements, netExcess: netExcess, eligibleGoals: eligibleForIncrease)
        case .minimizeRisk:
            return applyRiskMinimizingRedistribution(requirements, netExcess: netExcess, eligibleGoals: eligibleForIncrease)
        }
    }
    
    /// Apply balanced redistribution (equal distribution)
    private func applyBalancedRedistribution(
        _ requirements: [AdjustedRequirement],
        netExcess: Double,
        eligibleGoals: [AdjustedRequirement]
    ) -> [AdjustedRequirement] {
        
        var result = requirements
        let redistributionPerGoal = netExcess / Double(eligibleGoals.count)
        
        for eligible in eligibleGoals {
            if let index = result.firstIndex(where: { $0.requirement.goalId == eligible.requirement.goalId }) {
                let newAmount = min(
                    result[index].adjustedAmount + redistributionPerGoal,
                    result[index].requirement.requiredMonthly * 1.5 // Cap at 150% of original
                )
                let redistributionAmount = newAmount - result[index].adjustedAmount
                
                result[index] = AdjustedRequirement(
                    requirement: result[index].requirement,
                    adjustedAmount: newAmount,
                    adjustmentFactor: result[index].adjustmentFactor,
                    redistributionAmount: redistributionAmount,
                    impactAnalysis: calculateImpact(
                        original: result[index].requirement.requiredMonthly,
                        adjusted: newAmount,
                        deadline: result[index].requirement.deadline
                    )
                )
            }
        }
        
        return result
    }
    
    /// Apply urgency-based redistribution (critical goals first)
    private func applyUrgencyBasedRedistribution(
        _ requirements: [AdjustedRequirement],
        netExcess: Double,
        eligibleGoals: [AdjustedRequirement]
    ) -> [AdjustedRequirement] {
        
        var result = requirements
        var remainingExcess = netExcess
        
        // Sort by urgency (shortest deadline first, then by progress)
        let sortedByUrgency = eligibleGoals.sorted { lhs, rhs in
            if lhs.requirement.monthsRemaining != rhs.requirement.monthsRemaining {
                return lhs.requirement.monthsRemaining < rhs.requirement.monthsRemaining
            }
            return lhs.requirement.progress < rhs.requirement.progress
        }
        
        for eligible in sortedByUrgency {
            guard remainingExcess > 1.0 else { break }
            
            if let index = result.firstIndex(where: { $0.requirement.goalId == eligible.requirement.goalId }) {
                let maxIncrease = result[index].requirement.requiredMonthly * 0.5 // Up to 50% increase
                let actualIncrease = min(remainingExcess, maxIncrease)
                let newAmount = result[index].adjustedAmount + actualIncrease
                
                result[index] = AdjustedRequirement(
                    requirement: result[index].requirement,
                    adjustedAmount: newAmount,
                    adjustmentFactor: result[index].adjustmentFactor,
                    redistributionAmount: actualIncrease,
                    impactAnalysis: calculateImpact(
                        original: result[index].requirement.requiredMonthly,
                        adjusted: newAmount,
                        deadline: result[index].requirement.deadline
                    )
                )
                
                remainingExcess -= actualIncrease
            }
        }
        
        return result
    }
    
    /// Apply volume-based redistribution (largest goals get more)
    private func applyVolumeBasedRedistribution(
        _ requirements: [AdjustedRequirement],
        netExcess: Double,
        eligibleGoals: [AdjustedRequirement]
    ) -> [AdjustedRequirement] {
        
        var result = requirements
        let totalEligibleAmount = eligibleGoals.reduce(0) { $0 + $1.requirement.requiredMonthly }
        
        for eligible in eligibleGoals {
            if let index = result.firstIndex(where: { $0.requirement.goalId == eligible.requirement.goalId }) {
                let proportion = eligible.requirement.requiredMonthly / totalEligibleAmount
                let redistributionAmount = netExcess * proportion
                let newAmount = min(
                    result[index].adjustedAmount + redistributionAmount,
                    result[index].requirement.requiredMonthly * 1.5
                )
                let actualRedistribution = newAmount - result[index].adjustedAmount
                
                result[index] = AdjustedRequirement(
                    requirement: result[index].requirement,
                    adjustedAmount: newAmount,
                    adjustmentFactor: result[index].adjustmentFactor,
                    redistributionAmount: actualRedistribution,
                    impactAnalysis: calculateImpact(
                        original: result[index].requirement.requiredMonthly,
                        adjusted: newAmount,
                        deadline: result[index].requirement.deadline
                    )
                )
            }
        }
        
        return result
    }
    
    /// Apply risk-minimizing redistribution
    private func applyRiskMinimizingRedistribution(
        _ requirements: [AdjustedRequirement],
        netExcess: Double,
        eligibleGoals: [AdjustedRequirement]
    ) -> [AdjustedRequirement] {
        
        var result = requirements
        
        // Sort by risk level (highest risk first)
        let sortedByRisk = eligibleGoals.sorted { lhs, rhs in
            let lhsRisk = calculateRiskLevel(lhs)
            let rhsRisk = calculateRiskLevel(rhs)
            return lhsRisk.rawValue > rhsRisk.rawValue
        }
        
        var remainingExcess = netExcess
        
        for eligible in sortedByRisk {
            guard remainingExcess > 1.0 else { break }
            
            if let index = result.firstIndex(where: { $0.requirement.goalId == eligible.requirement.goalId }) {
                let riskLevel = calculateRiskLevel(eligible)
                let maxIncrease = eligible.requirement.requiredMonthly * (riskLevel == .high ? 0.8 : 0.3)
                let actualIncrease = min(remainingExcess, maxIncrease)
                let newAmount = result[index].adjustedAmount + actualIncrease
                
                result[index] = AdjustedRequirement(
                    requirement: result[index].requirement,
                    adjustedAmount: newAmount,
                    adjustmentFactor: result[index].adjustmentFactor,
                    redistributionAmount: actualIncrease,
                    impactAnalysis: calculateImpact(
                        original: result[index].requirement.requiredMonthly,
                        adjusted: newAmount,
                        deadline: result[index].requirement.deadline
                    )
                )
                
                remainingExcess -= actualIncrease
            }
        }
        
        return result
    }
    
    /// Helper methods for calculations
    private func categorizeRequirements(
        _ requirements: [MonthlyRequirement],
        protectedGoalIds: Set<UUID>,
        skippedGoalIds: Set<UUID>
    ) -> (protected: [MonthlyRequirement], flexible: [MonthlyRequirement], skipped: [MonthlyRequirement]) {
        
        var protected: [MonthlyRequirement] = []
        var flexible: [MonthlyRequirement] = []
        var skipped: [MonthlyRequirement] = []
        
        for requirement in requirements {
            if skippedGoalIds.contains(requirement.goalId) {
                skipped.append(requirement)
            } else if protectedGoalIds.contains(requirement.goalId) {
                protected.append(requirement)
            } else {
                flexible.append(requirement)
            }
        }
        
        return (protected, flexible, skipped)
    }
    
    private func applyConstraints(
        originalAmount: Double,
        adjustedAmount: Double,
        requirement: MonthlyRequirement
    ) -> (finalAmount: Double, excess: Double, deficit: Double) {
        
        let minAmount = originalAmount * 0.1 // Minimum 10% of original
        let maxAmount = originalAmount * 1.5 // Maximum 150% of original
        
        let constrainedAmount = max(minAmount, min(maxAmount, adjustedAmount))
        
        let excess = max(0, adjustedAmount - constrainedAmount)
        let deficit = max(0, adjustedAmount - constrainedAmount)
        
        return (constrainedAmount, excess, deficit)
    }
    
    private func canAcceptAdditionalAmount(_ adjusted: AdjustedRequirement) -> Bool {
        return adjusted.adjustedAmount < adjusted.requirement.requiredMonthly * 1.5
    }
    
    private func calculateImpact(original: Double, adjusted: Double, deadline: Date) -> ImpactAnalysis {
        let changeAmount = adjusted - original
        let changePercentage = original > 0 ? (changeAmount / original) * 100 : 0
        
        // Estimate delay based on reduction
        var estimatedDelay = 0
        if changeAmount < 0 {
            let reduction = abs(changeAmount)
            let monthsToDeadline = max(1, Calendar.current.dateComponents([.month], from: Date(), to: deadline).month ?? 1)
            estimatedDelay = Int(ceil(reduction / max(1, adjusted) * Double(monthsToDeadline)))
        }
        
        // Determine risk level
        let riskLevel: RiskLevel
        if changePercentage < -50 {
            riskLevel = .high
        } else if changePercentage < -25 {
            riskLevel = .medium
        } else {
            riskLevel = .low
        }
        
        return ImpactAnalysis(
            changeAmount: changeAmount,
            changePercentage: changePercentage,
            estimatedDelay: estimatedDelay,
            riskLevel: riskLevel
        )
    }
    
    private func calculateRiskLevel(_ adjusted: AdjustedRequirement) -> RiskLevel {
        let reductionPercentage = (adjusted.requirement.requiredMonthly - adjusted.adjustedAmount) / adjusted.requirement.requiredMonthly * 100
        
        if reductionPercentage > 50 || adjusted.requirement.monthsRemaining <= 2 {
            return .high
        } else if reductionPercentage > 25 || adjusted.requirement.monthsRemaining <= 4 {
            return .medium
        } else {
            return .low
        }
    }
    
    private func estimateDelay(_ adjusted: AdjustedRequirement) -> Int {
        let shortfall = adjusted.requirement.requiredMonthly - adjusted.adjustedAmount
        let monthsToMakeUp = shortfall / max(1, adjusted.adjustedAmount)
        return Int(ceil(monthsToMakeUp))
    }
    
    private func calculateTotalSavings(_ original: [MonthlyRequirement], _ adjusted: [AdjustedRequirement]) -> Double {
        let originalTotal = original.reduce(0) { $0 + $1.requiredMonthly }
        let adjustedTotal = adjusted.reduce(0) { $0 + $1.adjustedAmount }
        return originalTotal - adjustedTotal
    }
    
    private func calculateRedistributionSummary(_ adjusted: [AdjustedRequirement]) -> RedistributionSummary {
        let totalReduced = adjusted.reduce(0) { sum, adj in
            sum + max(0, adj.requirement.requiredMonthly - adj.adjustedAmount)
        }
        let totalRedistributed = adjusted.reduce(0) { $0 + $1.redistributionAmount }
        let affectedGoals = adjusted.filter { $0.redistributionAmount != 0 }.count
        
        return RedistributionSummary(
            totalReduced: totalReduced,
            totalRedistributed: totalRedistributed,
            affectedGoals: affectedGoals
        )
    }
    
    private func calculateTotal(
        requirements: [MonthlyRequirement],
        protectedGoalIds: Set<UUID>,
        skippedGoalIds: Set<UUID>,
        displayCurrency: String
    ) async -> Double {
        var total: Double = 0
        
        for requirement in requirements {
            if skippedGoalIds.contains(requirement.goalId) {
                continue
            }
            
            if requirement.currency == displayCurrency {
                total += requirement.requiredMonthly
            } else {
                do {
                    let rate = try await exchangeRateService.fetchRate(from: requirement.currency, to: displayCurrency)
                    total += requirement.requiredMonthly * rate
                } catch {
                    // Fallback to original amount if conversion fails
                    AppLog.warning("Exchange rate failed for \(requirement.currency) → \(displayCurrency), using raw value: \(requirement.requiredMonthly) \(requirement.currency). Error: \(error.localizedDescription)", category: .exchangeRate)
                    total += requirement.requiredMonthly
                }
            }
        }
        
        return total
    }
    
    private func calculateProtectedTotal(
        requirements: [MonthlyRequirement],
        protectedGoalIds: Set<UUID>,
        displayCurrency: String
    ) async -> Double {
        var total: Double = 0
        
        for requirement in requirements.filter({ protectedGoalIds.contains($0.goalId) }) {
            if requirement.currency == displayCurrency {
                total += requirement.requiredMonthly
            } else {
                do {
                    let rate = try await exchangeRateService.fetchRate(from: requirement.currency, to: displayCurrency)
                    total += requirement.requiredMonthly * rate
                } catch {
                    AppLog.warning("Exchange rate failed for \(requirement.currency) → \(displayCurrency), using raw value: \(requirement.requiredMonthly) \(requirement.currency). Error: \(error.localizedDescription)", category: .exchangeRate)
                    total += requirement.requiredMonthly
                }
            }
        }
        
        return total
    }
    
    private func calculateAdjustedTotal(
        adjustedRequirements: [AdjustedRequirement],
        displayCurrency: String
    ) async -> Double {
        var total: Double = 0
        
        for adjusted in adjustedRequirements {
            if adjusted.requirement.currency == displayCurrency {
                total += adjusted.adjustedAmount
            } else {
                do {
                    let rate = try await exchangeRateService.fetchRate(from: adjusted.requirement.currency, to: displayCurrency)
                    total += adjusted.adjustedAmount * rate
                } catch {
                    AppLog.warning("Exchange rate failed for \(adjusted.requirement.currency) → \(displayCurrency), using raw value: \(adjusted.adjustedAmount) \(adjusted.requirement.currency). Error: \(error.localizedDescription)", category: .exchangeRate)
                    total += adjusted.adjustedAmount
                }
            }
        }
        
        return total
    }
    
    private func createCacheKey(
        requirements: [MonthlyRequirement],
        adjustment: Double,
        protectedGoalIds: Set<UUID>,
        skippedGoalIds: Set<UUID>,
        strategy: RedistributionStrategy
    ) -> String {
        let requirementIds = requirements.map { $0.goalId.uuidString }.sorted().joined(separator: ",")
        let protectedIds = protectedGoalIds.map { $0.uuidString }.sorted().joined(separator: ",")
        let skippedIds = skippedGoalIds.map { $0.uuidString }.sorted().joined(separator: ",")
        
        return "\(requirementIds)|\(adjustment)|\(protectedIds)|\(skippedIds)|\(strategy.rawValue)"
    }
    
    private func getCachedResult(for key: String) -> RedistributionResult? {
        guard let lastUpdate = lastCacheUpdate,
              Date().timeIntervalSince(lastUpdate) < cacheExpiration else {
            return nil
        }
        return redistributionCache[key]
    }
}

// MARK: - Supporting Data Structures

/// Result of optimal adjustment calculation
struct OptimalAdjustmentResult: Sendable {
    let adjustmentFactor: Double
    let adjustedRequirements: [AdjustedRequirement]
    let achievedTotal: Double
    let targetTotal: Double
    let redistribution: RedistributionSummary
}

/// Simulation result with risk analysis
struct AdjustmentSimulation: Sendable {
    let adjustedRequirements: [AdjustedRequirement]
    let riskAnalysis: [UUID: RiskLevel]
    let delayEstimates: [UUID: Int]
    let totalSavings: Double
    let redistribution: RedistributionSummary
}

/// Summary of redistribution activity
struct RedistributionSummary: Sendable {
    let totalReduced: Double
    let totalRedistributed: Double
    let affectedGoals: Int
}

/// Impact analysis for an adjustment
struct ImpactAnalysis: Sendable {
    let changeAmount: Double
    let changePercentage: Double
    let estimatedDelay: Int
    let riskLevel: RiskLevel
}

/// Redistribution strategy options
enum RedistributionStrategy: String, CaseIterable, Sendable {
    case balanced = "balanced"
    case prioritizeUrgent = "prioritize_urgent"
    case prioritizeLargest = "prioritize_largest"
    case minimizeRisk = "minimize_risk"
    
    var displayName: String {
        switch self {
        case .balanced: return "Balanced Distribution"
        case .prioritizeUrgent: return "Prioritize Urgent Goals"
        case .prioritizeLargest: return "Prioritize Largest Goals"
        case .minimizeRisk: return "Minimize Risk"
        }
    }
    
    var description: String {
        switch self {
        case .balanced: return "Distribute excess evenly among all eligible goals"
        case .prioritizeUrgent: return "Give priority to goals with nearest deadlines"
        case .prioritizeLargest: return "Allocate more to goals with larger amounts"
        case .minimizeRisk: return "Focus on reducing overall risk to goal completion"
        }
    }
}

/// Risk level assessment
enum RiskLevel: Int, CaseIterable, Sendable {
    case low = 1
    case medium = 2
    case high = 3
    
    var displayName: String {
        switch self {
        case .low: return "Low Risk"
        case .medium: return "Medium Risk"
        case .high: return "High Risk"
        }
    }
    
    var color: String {
        switch self {
        case .low: return "systemGreen"
        case .medium: return "systemOrange"
        case .high: return "systemRed"
        }
    }
}