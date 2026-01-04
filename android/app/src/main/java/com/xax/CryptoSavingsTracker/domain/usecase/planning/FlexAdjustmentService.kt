package com.xax.CryptoSavingsTracker.domain.usecase.planning

import com.xax.CryptoSavingsTracker.domain.model.MonthlyRequirement
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/**
 * Redistribution strategy for flex adjustments.
 * Determines how excess funds are distributed among goals.
 */
enum class RedistributionStrategy {
    /** Equal distribution among eligible goals, capped at 150% */
    BALANCED,
    /** Prioritize goals with shortest deadlines, max +50% increase */
    PRIORITIZE_URGENT,
    /** Distribute proportionally to goal size, capped at 150% */
    PRIORITIZE_LARGEST,
    /** Prioritize high-risk goals, max +80% for high-risk */
    MINIMIZE_RISK
}

/**
 * Risk level for impact analysis.
 */
enum class RiskLevel(val value: Int) {
    LOW(1),
    MEDIUM(2),
    HIGH(3)
}

/**
 * Analysis of the impact of a flex adjustment on a goal.
 */
data class ImpactAnalysis(
    /** Change in amount (positive = increase, negative = decrease) */
    val changeAmount: Double,
    /** Change as percentage of original amount */
    val changePercentage: Double,
    /** Estimated months of delay caused by reduction */
    val estimatedDelay: Int,
    /** Risk level based on reduction severity */
    val riskLevel: RiskLevel
)

/**
 * A requirement with flex adjustment applied.
 */
data class AdjustedRequirement(
    /** Original requirement */
    val requirement: MonthlyRequirement,
    /** Amount after adjustment */
    val adjustedAmount: Double,
    /** Reason for this adjustment */
    val adjustmentReason: String,
    /** Whether this goal is protected from reduction */
    val isProtected: Boolean,
    /** Whether this goal is skipped (set to 0) */
    val isSkipped: Boolean,
    /** Adjustment multiplier applied (0.0-2.0) */
    val adjustmentFactor: Double,
    /** Amount redistributed to/from this goal */
    val redistributionAmount: Double,
    /** Impact analysis for this adjustment */
    val impactAnalysis: ImpactAnalysis
) {
    /** Adjustment as percentage of original */
    val adjustmentPercentage: Double
        get() = if (requirement.requiredMonthly > 0) {
            adjustedAmount / requirement.requiredMonthly
        } else 1.0

    /** Whether the amount was reduced */
    val hasBeenReduced: Boolean
        get() = adjustedAmount < requirement.requiredMonthly

    /** Whether the amount was increased */
    val hasBeenIncreased: Boolean
        get() = adjustedAmount > requirement.requiredMonthly
}

/**
 * Summary of redistribution effects.
 */
data class RedistributionSummary(
    /** Total amount reduced from all goals */
    val totalReduced: Double,
    /** Total amount redistributed to goals */
    val totalRedistributed: Double,
    /** Number of goals affected by redistribution */
    val affectedGoals: Int
)

/**
 * Result of simulating a flex adjustment.
 */
data class AdjustmentSimulation(
    /** All adjusted requirements */
    val adjustedRequirements: List<AdjustedRequirement>,
    /** Risk level per goal ID */
    val riskAnalysis: Map<String, RiskLevel>,
    /** Estimated delay in months per goal ID */
    val delayEstimates: Map<String, Int>,
    /** Total amount saved vs original */
    val totalSavings: Double,
    /** Total original amount */
    val totalOriginal: Double,
    /** Total adjusted amount */
    val totalAdjusted: Double,
    /** Redistribution summary */
    val redistributionSummary: RedistributionSummary
)

/**
 * Service for applying flex adjustments with redistribution strategies.
 * Ports iOS FlexAdjustmentService functionality to Android.
 */
@Singleton
class FlexAdjustmentService @Inject constructor() {

    companion object {
        /** Minimum amount as percentage of original (10%) */
        private const val MIN_CONSTRAINT_PERCENT = 0.10
        /** Maximum amount as percentage of original (150%) */
        private const val MAX_CONSTRAINT_PERCENT = 1.50
        /** Threshold for considering excess trivial */
        private const val TRIVIAL_THRESHOLD = 1.0
    }

    /**
     * Apply flex adjustment with redistribution strategy.
     *
     * @param requirements List of monthly requirements to adjust
     * @param adjustment Adjustment factor (0.0 = nothing, 1.0 = full amount, 1.5 = 150%)
     * @param protectedGoalIds Goals that cannot be reduced
     * @param skippedGoalIds Goals to skip (set to 0)
     * @param strategy Redistribution strategy for excess funds
     * @return List of adjusted requirements
     */
    suspend fun applyFlexAdjustment(
        requirements: List<MonthlyRequirement>,
        adjustment: Double,
        protectedGoalIds: Set<String>,
        skippedGoalIds: Set<String>,
        strategy: RedistributionStrategy = RedistributionStrategy.BALANCED
    ): List<AdjustedRequirement> {
        val clampedAdjustment = adjustment.coerceIn(0.0, 2.0)

        // Stage 1: Categorize requirements
        val (protected, flexible, skipped) = categorize(requirements, protectedGoalIds, skippedGoalIds)

        // Stage 2: Apply base adjustment with constraints
        val baseAdjusted = mutableListOf<AdjustedRequirement>()
        var totalExcess = 0.0
        var totalDeficit = 0.0

        // Protected goals: unchanged
        for (req in protected) {
            baseAdjusted.add(createAdjustedRequirement(
                requirement = req,
                adjustedAmount = req.requiredMonthly,
                reason = "Protected",
                isProtected = true,
                isSkipped = false,
                factor = 1.0,
                redistribution = 0.0
            ))
        }

        // Skipped goals: set to 0
        for (req in skipped) {
            baseAdjusted.add(createAdjustedRequirement(
                requirement = req,
                adjustedAmount = 0.0,
                reason = "Skipped this month",
                isProtected = false,
                isSkipped = true,
                factor = 0.0,
                redistribution = 0.0
            ))
        }

        // Flexible goals: apply adjustment with constraints
        val flexibleAdjusted = mutableListOf<Pair<MonthlyRequirement, Double>>()
        for (req in flexible) {
            val original = req.requiredMonthly
            val rawAdjusted = original * clampedAdjustment

            // Apply constraints
            val minAmount = original * MIN_CONSTRAINT_PERCENT
            val maxAmount = original * MAX_CONSTRAINT_PERCENT
            val constrained = rawAdjusted.coerceIn(minAmount, maxAmount)

            // Track excess/deficit
            if (rawAdjusted > maxAmount) {
                totalExcess += rawAdjusted - maxAmount
            } else if (rawAdjusted < minAmount) {
                totalDeficit += minAmount - rawAdjusted
            }

            flexibleAdjusted.add(req to constrained)
        }

        // Stage 3: Calculate net excess for redistribution
        val netExcess = totalExcess - totalDeficit

        // Stage 4: Apply redistribution strategy
        val redistributed = if (netExcess > TRIVIAL_THRESHOLD) {
            redistributeExcess(flexibleAdjusted, netExcess, strategy, clampedAdjustment)
        } else {
            flexibleAdjusted.map { (req, amount) ->
                createAdjustedRequirement(
                    requirement = req,
                    adjustedAmount = amount,
                    reason = "Adjusted",
                    isProtected = false,
                    isSkipped = false,
                    factor = clampedAdjustment,
                    redistribution = 0.0
                )
            }
        }

        baseAdjusted.addAll(redistributed)
        return baseAdjusted.sortedBy { it.requirement.goalName }
    }

    /**
     * Simulate adjustment without persisting.
     * Returns comprehensive analysis of the adjustment impact.
     */
    suspend fun simulateAdjustment(
        requirements: List<MonthlyRequirement>,
        adjustment: Double,
        protectedGoalIds: Set<String>,
        skippedGoalIds: Set<String>,
        strategy: RedistributionStrategy = RedistributionStrategy.BALANCED
    ): AdjustmentSimulation {
        val adjusted = applyFlexAdjustment(requirements, adjustment, protectedGoalIds, skippedGoalIds, strategy)

        val riskAnalysis = adjusted.associate { it.requirement.goalId to it.impactAnalysis.riskLevel }
        val delayEstimates = adjusted.associate { it.requirement.goalId to it.impactAnalysis.estimatedDelay }

        val totalOriginal = requirements.sumOf { it.requiredMonthly }
        val totalAdjusted = adjusted.sumOf { it.adjustedAmount }
        val totalSavings = totalOriginal - totalAdjusted

        val totalReduced = adjusted.filter { it.hasBeenReduced }.sumOf { it.requirement.requiredMonthly - it.adjustedAmount }
        val totalRedistributed = adjusted.filter { it.redistributionAmount > 0 }.sumOf { it.redistributionAmount }
        val affectedGoals = adjusted.count { it.redistributionAmount != 0.0 }

        return AdjustmentSimulation(
            adjustedRequirements = adjusted,
            riskAnalysis = riskAnalysis,
            delayEstimates = delayEstimates,
            totalSavings = totalSavings,
            totalOriginal = totalOriginal,
            totalAdjusted = totalAdjusted,
            redistributionSummary = RedistributionSummary(
                totalReduced = totalReduced,
                totalRedistributed = totalRedistributed,
                affectedGoals = affectedGoals
            )
        )
    }

    // --- Private helpers ---

    private fun categorize(
        requirements: List<MonthlyRequirement>,
        protectedGoalIds: Set<String>,
        skippedGoalIds: Set<String>
    ): Triple<List<MonthlyRequirement>, List<MonthlyRequirement>, List<MonthlyRequirement>> {
        val protected = mutableListOf<MonthlyRequirement>()
        val flexible = mutableListOf<MonthlyRequirement>()
        val skipped = mutableListOf<MonthlyRequirement>()

        for (req in requirements) {
            when {
                skippedGoalIds.contains(req.goalId) -> skipped.add(req)
                protectedGoalIds.contains(req.goalId) -> protected.add(req)
                else -> flexible.add(req)
            }
        }

        return Triple(protected, flexible, skipped)
    }

    private fun redistributeExcess(
        flexibleAdjusted: List<Pair<MonthlyRequirement, Double>>,
        netExcess: Double,
        strategy: RedistributionStrategy,
        baseFactor: Double
    ): List<AdjustedRequirement> {
        return when (strategy) {
            RedistributionStrategy.BALANCED -> redistributeBalanced(flexibleAdjusted, netExcess, baseFactor)
            RedistributionStrategy.PRIORITIZE_URGENT -> redistributeUrgent(flexibleAdjusted, netExcess, baseFactor)
            RedistributionStrategy.PRIORITIZE_LARGEST -> redistributeLargest(flexibleAdjusted, netExcess, baseFactor)
            RedistributionStrategy.MINIMIZE_RISK -> redistributeMinimizeRisk(flexibleAdjusted, netExcess, baseFactor)
        }
    }

    /**
     * Balanced: Equal distribution among eligible goals, capped at 150%
     */
    private fun redistributeBalanced(
        flexibleAdjusted: List<Pair<MonthlyRequirement, Double>>,
        netExcess: Double,
        baseFactor: Double
    ): List<AdjustedRequirement> {
        val eligible = flexibleAdjusted.filter { (req, amount) ->
            amount > 0 && amount < req.requiredMonthly * MAX_CONSTRAINT_PERCENT
        }

        if (eligible.isEmpty()) {
            return flexibleAdjusted.map { (req, amount) ->
                createAdjustedRequirement(req, amount, "Adjusted", false, false, baseFactor, 0.0)
            }
        }

        val perGoal = netExcess / eligible.size
        val eligibleIds = eligible.map { it.first.goalId }.toSet()

        return flexibleAdjusted.map { (req, amount) ->
            if (eligibleIds.contains(req.goalId)) {
                val maxAmount = req.requiredMonthly * MAX_CONSTRAINT_PERCENT
                val redistribution = min(perGoal, maxAmount - amount)
                val finalAmount = amount + redistribution
                createAdjustedRequirement(req, finalAmount, "Balanced redistribution", false, false, baseFactor, redistribution)
            } else {
                createAdjustedRequirement(req, amount, "Adjusted", false, false, baseFactor, 0.0)
            }
        }
    }

    /**
     * Prioritize Urgent: Sort by deadline, assign sequentially, max +50% increase
     */
    private fun redistributeUrgent(
        flexibleAdjusted: List<Pair<MonthlyRequirement, Double>>,
        netExcess: Double,
        baseFactor: Double
    ): List<AdjustedRequirement> {
        // Sort by urgency: shortest monthsRemaining first, then lowest progress
        val sorted = flexibleAdjusted.sortedWith(
            compareBy({ it.first.monthsRemaining }, { it.first.progress })
        )

        var remaining = netExcess
        val redistributions = mutableMapOf<String, Double>()

        for ((req, amount) in sorted) {
            if (remaining <= 0) break
            if (amount <= 0) continue

            // Max increase: 50% of original
            val maxIncrease = req.requiredMonthly * 0.50
            val actualIncrease = min(remaining, maxIncrease)
            redistributions[req.goalId] = actualIncrease
            remaining -= actualIncrease
        }

        return flexibleAdjusted.map { (req, amount) ->
            val redistribution = redistributions[req.goalId] ?: 0.0
            val finalAmount = amount + redistribution
            val reason = if (redistribution > 0) "Urgent priority" else "Adjusted"
            createAdjustedRequirement(req, finalAmount, reason, false, false, baseFactor, redistribution)
        }
    }

    /**
     * Prioritize Largest: Distribute proportionally to goal size, capped at 150%
     */
    private fun redistributeLargest(
        flexibleAdjusted: List<Pair<MonthlyRequirement, Double>>,
        netExcess: Double,
        baseFactor: Double
    ): List<AdjustedRequirement> {
        val eligible = flexibleAdjusted.filter { (req, amount) ->
            amount > 0 && amount < req.requiredMonthly * MAX_CONSTRAINT_PERCENT
        }

        if (eligible.isEmpty()) {
            return flexibleAdjusted.map { (req, amount) ->
                createAdjustedRequirement(req, amount, "Adjusted", false, false, baseFactor, 0.0)
            }
        }

        val totalEligible = eligible.sumOf { it.first.requiredMonthly }
        val eligibleIds = eligible.map { it.first.goalId }.toSet()

        return flexibleAdjusted.map { (req, amount) ->
            if (eligibleIds.contains(req.goalId) && totalEligible > 0) {
                val proportion = req.requiredMonthly / totalEligible
                val maxAmount = req.requiredMonthly * MAX_CONSTRAINT_PERCENT
                val targetRedistribution = netExcess * proportion
                val redistribution = min(targetRedistribution, maxAmount - amount)
                val finalAmount = amount + redistribution
                createAdjustedRequirement(req, finalAmount, "Proportional redistribution", false, false, baseFactor, redistribution)
            } else {
                createAdjustedRequirement(req, amount, "Adjusted", false, false, baseFactor, 0.0)
            }
        }
    }

    /**
     * Minimize Risk: Prioritize high-risk goals, max +80% for high-risk
     */
    private fun redistributeMinimizeRisk(
        flexibleAdjusted: List<Pair<MonthlyRequirement, Double>>,
        netExcess: Double,
        baseFactor: Double
    ): List<AdjustedRequirement> {
        // Calculate risk for each goal
        val withRisk = flexibleAdjusted.map { (req, amount) ->
            val reductionPct = if (req.requiredMonthly > 0) {
                (req.requiredMonthly - amount) / req.requiredMonthly * 100
            } else 0.0

            val risk = when {
                reductionPct > 50 || req.monthsRemaining <= 2 -> RiskLevel.HIGH
                reductionPct > 25 || req.monthsRemaining <= 4 -> RiskLevel.MEDIUM
                else -> RiskLevel.LOW
            }
            Triple(req, amount, risk)
        }

        // Sort by risk (high first)
        val sorted = withRisk.sortedByDescending { it.third.value }

        var remaining = netExcess
        val redistributions = mutableMapOf<String, Double>()

        for ((req, amount, risk) in sorted) {
            if (remaining <= 0) break
            if (amount <= 0) continue

            // Max increase based on risk level
            val maxIncreasePct = if (risk == RiskLevel.HIGH) 0.80 else 0.30
            val maxIncrease = req.requiredMonthly * maxIncreasePct
            val actualIncrease = min(remaining, maxIncrease)
            redistributions[req.goalId] = actualIncrease
            remaining -= actualIncrease
        }

        return flexibleAdjusted.map { (req, amount) ->
            val redistribution = redistributions[req.goalId] ?: 0.0
            val finalAmount = amount + redistribution
            val reason = if (redistribution > 0) "Risk minimization" else "Adjusted"
            createAdjustedRequirement(req, finalAmount, reason, false, false, baseFactor, redistribution)
        }
    }

    private fun createAdjustedRequirement(
        requirement: MonthlyRequirement,
        adjustedAmount: Double,
        reason: String,
        isProtected: Boolean,
        isSkipped: Boolean,
        factor: Double,
        redistribution: Double
    ): AdjustedRequirement {
        val original = requirement.requiredMonthly
        val changeAmount = adjustedAmount - original
        val changePercentage = if (original > 0) (changeAmount / original) * 100 else 0.0

        // Calculate estimated delay (only for reductions)
        val estimatedDelay = if (changeAmount < 0 && adjustedAmount > 0) {
            val monthlyReduction = -changeAmount
            ceil(monthlyReduction / max(1.0, adjustedAmount) * requirement.monthsRemaining).toInt()
        } else {
            0
        }

        // Determine risk level
        val riskLevel = when {
            changePercentage < -50 -> RiskLevel.HIGH
            changePercentage < -25 -> RiskLevel.MEDIUM
            else -> RiskLevel.LOW
        }

        return AdjustedRequirement(
            requirement = requirement,
            adjustedAmount = adjustedAmount,
            adjustmentReason = reason,
            isProtected = isProtected,
            isSkipped = isSkipped,
            adjustmentFactor = factor,
            redistributionAmount = redistribution,
            impactAnalysis = ImpactAnalysis(
                changeAmount = changeAmount,
                changePercentage = changePercentage,
                estimatedDelay = estimatedDelay,
                riskLevel = riskLevel
            )
        )
    }
}
