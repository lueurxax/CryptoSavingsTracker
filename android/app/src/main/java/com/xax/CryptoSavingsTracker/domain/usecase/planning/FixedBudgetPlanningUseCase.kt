package com.xax.CryptoSavingsTracker.domain.usecase.planning

import com.xax.CryptoSavingsTracker.domain.model.CompletionBehavior
import com.xax.CryptoSavingsTracker.domain.model.FeasibilityLevel
import com.xax.CryptoSavingsTracker.domain.model.FeasibilityResult
import com.xax.CryptoSavingsTracker.domain.model.FeasibilitySuggestion
import com.xax.CryptoSavingsTracker.domain.model.FixedBudgetPlan
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalContribution
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.InfeasibleGoal
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
import com.xax.CryptoSavingsTracker.domain.model.ScheduledGoalBlock
import com.xax.CryptoSavingsTracker.domain.model.ScheduledPayment
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.util.AllocationFunding
import java.time.LocalDate
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/**
 * Use case for computing fixed budget plans with optimal contribution sequencing.
 * Matches iOS FixedBudgetPlanningService for feature parity.
 */
@Singleton
class FixedBudgetPlanningUseCase @Inject constructor(
    private val allocationRepository: AllocationRepository,
    private val transactionRepository: TransactionRepository,
    private val exchangeRateRepository: ExchangeRateRepository,
    private val assetRepository: AssetRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository,
    private val settings: MonthlyPlanningSettings
) {
    // Cache
    private var cachedPlan: FixedBudgetPlan? = null
    private var cacheGoalIds: Set<String> = emptySet()
    private var cacheBudget: Double = 0.0
    private var lastCacheUpdate: Long = 0
    private val cacheExpiration: Long = 300_000 // 5 minutes in ms

    /**
     * Calculate the minimum budget needed to meet all goal deadlines.
     * Returns the MAX of all individual goal minimums (the binding constraint).
     */
    suspend fun calculateMinimumBudget(goals: List<Goal>, currency: String): Double {
        if (goals.isEmpty()) return 0.0

        val activeGoals = goals
            .filter { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
            .sortedBy { it.deadline }

        if (activeGoals.isEmpty()) return 0.0

        var cumulativeRemaining = 0.0
        var maxRequired = 0.0

        for (goal in activeGoals) {
            var remaining = calculateRemaining(goal)
            if (!goal.currency.equals(currency, ignoreCase = true)) {
                remaining = convertAmount(remaining, goal.currency, currency)
            }

            if (remaining <= 0.0) continue
            cumulativeRemaining += remaining

            val months = max(1, calculateMonthsRemaining(LocalDate.now(), goal.deadline))
            val required = cumulativeRemaining / months.toDouble()
            maxRequired = max(maxRequired, required)
        }

        return maxRequired
    }

    /**
     * Calculate the leveled budget (total remaining / months to last deadline).
     */
    suspend fun calculateLeveledBudget(goals: List<Goal>, currency: String): Double {
        if (goals.isEmpty()) return 0.0

        val activeGoals = goals.filter { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
        if (activeGoals.isEmpty()) return 0.0

        var totalRemaining = 0.0
        var latestDeadline = LocalDate.now()

        for (goal in activeGoals) {
            val remaining = calculateRemaining(goal)
            val convertedRemaining = if (!goal.currency.equals(currency, ignoreCase = true)) {
                convertAmount(remaining, goal.currency, currency)
            } else {
                remaining
            }
            totalRemaining += convertedRemaining

            if (goal.deadline.isAfter(latestDeadline)) {
                latestDeadline = goal.deadline
            }
        }

        val monthsToLast = max(1, calculateMonthsRemaining(LocalDate.now(), latestDeadline))
        return totalRemaining / monthsToLast.toDouble()
    }

    /**
     * Check if the given budget is sufficient for all goals.
     */
    suspend fun checkFeasibility(goals: List<Goal>, budget: Double, currency: String): FeasibilityResult {
        if (goals.isEmpty()) return FeasibilityResult.EMPTY

        val minimumRequired = calculateMinimumBudget(goals, currency)
        val isFeasible = budget >= minimumRequired && budget > 0

        val infeasibleGoals = mutableListOf<InfeasibleGoal>()
        val suggestions = mutableListOf<FeasibilitySuggestion>()

        if (!isFeasible) {
            val activeGoals = goals
                .filter { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
                .sortedBy { it.deadline }

            var cumulativeRemaining = 0.0
            for (goal in activeGoals) {
                var remaining = calculateRemaining(goal)
                if (!goal.currency.equals(currency, ignoreCase = true)) {
                    remaining = convertAmount(remaining, goal.currency, currency)
                }

                if (remaining <= 0.0) continue
                cumulativeRemaining += remaining

                val months = max(1, calculateMonthsRemaining(LocalDate.now(), goal.deadline))
                val required = cumulativeRemaining / months.toDouble()
                if (required > budget) {
                    val shortfall = required - budget
                    infeasibleGoals.add(
                        InfeasibleGoal(
                            goalId = goal.id,
                            goalName = goal.name,
                            deadline = goal.deadline,
                            requiredMonthly = required,
                            shortfall = shortfall,
                            currency = currency
                        )
                    )
                }
            }

            // Generate suggestions
            if (infeasibleGoals.isNotEmpty()) {
                // Suggest increasing budget
                suggestions.add(FeasibilitySuggestion.IncreaseBudget(minimumRequired, currency))

                // Suggest extending deadlines
                for (infeasible in infeasibleGoals.take(2)) {
                    val goal = goals.find { it.id == infeasible.goalId } ?: continue
                    val remaining = calculateRemaining(goal)
                    val convertedRemaining = if (!goal.currency.equals(currency, ignoreCase = true)) {
                        convertAmount(remaining, goal.currency, currency)
                    } else {
                        remaining
                    }

                    if (budget <= 0) continue
                    val monthsNeededDouble = convertedRemaining / budget
                    if (!monthsNeededDouble.isFinite()) continue
                    val monthsNeeded = ceil(monthsNeededDouble.coerceAtMost(Int.MAX_VALUE.toDouble())).toInt()
                    val currentMonths = calculateMonthsRemaining(LocalDate.now(), infeasible.deadline)
                    val extensionNeeded = monthsNeeded - currentMonths

                    if (extensionNeeded in 1..12) {
                        suggestions.add(
                            FeasibilitySuggestion.ExtendDeadline(
                                goalId = infeasible.goalId,
                                goalName = infeasible.goalName,
                                byMonths = extensionNeeded
                            )
                        )
                    }
                }
            }
        }

        return FeasibilityResult(
            isFeasible = isFeasible,
            minimumRequired = minimumRequired,
            currency = currency,
            infeasibleGoals = infeasibleGoals,
            suggestions = suggestions
        )
    }

    /**
     * Generate the optimal contribution schedule.
     */
    suspend fun generateSchedule(goals: List<Goal>, budget: Double, currency: String): FixedBudgetPlan {
        val goalIds = goals.map { it.id }.toSet()
        val now = System.currentTimeMillis()

        // Check cache
        if (cachedPlan != null &&
            cacheGoalIds == goalIds &&
            abs(cacheBudget - budget) < 0.01 &&
            now - lastCacheUpdate < cacheExpiration
        ) {
            return cachedPlan!!
        }

        // Sort goals by deadline (earliest first)
        val activeGoals = goals
            .filter { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
            .sortedBy { it.deadline }

        if (activeGoals.isEmpty()) {
            return FixedBudgetPlan(
                monthlyBudget = budget,
                currency = currency,
                schedule = emptyList(),
                isLeveled = true,
                minimumRequired = 0.0,
                goalRemainingById = emptyMap()
            )
        }

        if (budget <= 0) {
            val minimumRequired = calculateMinimumBudget(goals, currency)
            return FixedBudgetPlan(
                monthlyBudget = budget,
                currency = currency,
                schedule = emptyList(),
                isLeveled = false,
                minimumRequired = minimumRequired,
                goalRemainingById = goalRemaining
            )
        }

        // Calculate remaining amounts for each goal (converted to target currency)
        val goalRemaining = mutableMapOf<String, Double>()
        val goalNames = mutableMapOf<String, String>()

        for (goal in activeGoals) {
            var remaining = calculateRemaining(goal)
            if (!goal.currency.equals(currency, ignoreCase = true)) {
                remaining = convertAmount(remaining, goal.currency, currency)
            }
            goalRemaining[goal.id] = remaining
            goalNames[goal.id] = goal.name
        }

        // Generate payment dates starting from next payment day
        val payments = mutableListOf<ScheduledPayment>()
        var paymentNumber = 1
        var paymentDate = nextPaymentDate()
        val goalRunningTotals = mutableMapOf<String, Double>()
        val remainingByGoal = goalRemaining.toMutableMap()

        // Initialize running totals
        for (goal in activeGoals) {
            goalRunningTotals[goal.id] = 0.0
        }

        var safetyCounter = 0
        while (remainingByGoal.values.any { it > 0.01 } && safetyCounter < 600) {
            safetyCounter++
            val startTotals = goalRunningTotals.toMap()
            val paymentAllocations = mutableMapOf<String, Double>()
            val minimums = mutableMapOf<String, Double>()

            var totalMinimum = 0.0
            for (goal in activeGoals) {
                if (paymentDate.isAfter(goal.deadline)) continue
                val remaining = remainingByGoal[goal.id] ?: 0.0
                if (remaining <= 0.01) continue
                val monthsRemaining = max(1, calculateMonthsRemaining(paymentDate, goal.deadline))
                val minimum = remaining / monthsRemaining.toDouble()
                minimums[goal.id] = minimum
                totalMinimum += minimum
            }

            if (totalMinimum <= 0) break

            val scale = if (totalMinimum > budget) budget / totalMinimum else 1.0
            var remainingBudget = budget

            for (goal in activeGoals) {
                val minimum = minimums[goal.id] ?: continue
                val amount = min(remainingBudget, minimum * scale)
                if (amount <= 0.01) continue

                paymentAllocations[goal.id] = (paymentAllocations[goal.id] ?: 0.0) + amount
                goalRunningTotals[goal.id] = (goalRunningTotals[goal.id] ?: 0.0) + amount
                remainingByGoal[goal.id] = max(0.0, (remainingByGoal[goal.id] ?: 0.0) - amount)
                remainingBudget -= amount
            }

            if (remainingBudget > 0.01) {
                for (goal in activeGoals) {
                    if (paymentDate.isAfter(goal.deadline)) continue
                    val remaining = remainingByGoal[goal.id] ?: 0.0
                    if (remaining <= 0.01) continue
                    val extra = min(remainingBudget, remaining)
                    if (extra <= 0.01) continue
                    paymentAllocations[goal.id] = (paymentAllocations[goal.id] ?: 0.0) + extra
                    goalRunningTotals[goal.id] = (goalRunningTotals[goal.id] ?: 0.0) + extra
                    remainingByGoal[goal.id] = max(0.0, remaining - extra)
                    remainingBudget -= extra
                    if (remainingBudget <= 0.01) break
                }
            }

            val contributions = activeGoals.mapNotNull { goal ->
                val amount = paymentAllocations[goal.id] ?: 0.0
                if (amount <= 0.01) return@mapNotNull null

                val startingTotal = startTotals[goal.id] ?: 0.0
                val newTotal = goalRunningTotals[goal.id] ?: 0.0
                val isStart = startingTotal <= 0.01
                val isComplete = (remainingByGoal[goal.id] ?: 0.0) <= 0.01

                GoalContribution(
                    goalId = goal.id,
                    goalName = goalNames[goal.id] ?: goal.name,
                    amount = amount,
                    isGoalStart = isStart,
                    isGoalComplete = isComplete,
                    runningTotal = newTotal
                )
            }

            if (contributions.isNotEmpty()) {
                payments.add(
                    ScheduledPayment(
                        paymentDate = paymentDate,
                        paymentNumber = paymentNumber,
                        contributions = contributions
                    )
                )
            }

            paymentNumber++
            paymentDate = paymentDate.plusMonths(1)
        }

        val minimumRequired = calculateMinimumBudget(goals, currency)
        val plan = FixedBudgetPlan(
            monthlyBudget = budget,
            currency = currency,
            schedule = payments,
            isLeveled = abs(budget - minimumRequired) < 0.01,
            minimumRequired = minimumRequired,
            goalRemainingById = goalRemaining
        )

        // Cache the result
        cachedPlan = plan
        cacheGoalIds = goalIds
        cacheBudget = budget
        lastCacheUpdate = now

        return plan
    }

    /**
     * Build timeline blocks for visualization.
     */
    fun buildTimelineBlocks(plan: FixedBudgetPlan, goals: List<Goal>): List<ScheduledGoalBlock> {
        val deadlines = goals.associate { it.id to it.deadline }
        val summaries = mutableMapOf<String, CurrentBlock>()

        for (payment in plan.schedule) {
            for (contribution in payment.contributions) {
                val deadline = deadlines[contribution.goalId] ?: continue
                if (payment.paymentDate.isAfter(deadline)) continue
                val existing = summaries[contribution.goalId]
                if (existing == null) {
                    summaries[contribution.goalId] = CurrentBlock(
                        goalId = contribution.goalId,
                        startPayment = payment.paymentNumber,
                        startDate = payment.paymentDate,
                        totalAmount = contribution.amount,
                        paymentCount = 1,
                        endPayment = payment.paymentNumber,
                        endDate = payment.paymentDate
                    )
                } else {
                    summaries[contribution.goalId] = existing.copy(
                        totalAmount = existing.totalAmount + contribution.amount,
                        paymentCount = existing.paymentCount + 1,
                        endPayment = payment.paymentNumber,
                        endDate = payment.paymentDate
                    )
                }
            }
        }

        return summaries.values
            .sortedBy { it.startPayment }
            .map { summary ->
                val goal = goals.find { it.id == summary.goalId }
                ScheduledGoalBlock(
                    goalId = summary.goalId,
                    goalName = goal?.name ?: "",
                    emoji = goal?.emoji,
                    startPaymentNumber = summary.startPayment,
                    endPaymentNumber = summary.endPayment,
                    startDate = summary.startDate,
                    endDate = summary.endDate,
                    totalAmount = summary.totalAmount,
                    paymentCount = summary.paymentCount
                )
            }
    }

    /**
     * Clear the cache.
     */
    fun clearCache() {
        cachedPlan = null
        cacheGoalIds = emptySet()
        cacheBudget = 0.0
        lastCacheUpdate = 0
    }

    // MARK: - Recalculation with CompletionBehavior

    /**
     * Recalculate the schedule after an actual contribution that differs from the planned amount.
     * Uses the CompletionBehavior setting to determine how to handle the difference.
     *
     * @param plan The original fixed budget plan
     * @param actualContribution The amount actually contributed this period
     * @param forPaymentNumber The payment number where the contribution was made (1-indexed)
     * @param goals Current list of active goals
     * @param behavior How to handle over/under contributions
     * @return A new plan reflecting the recalculated schedule
     */
    suspend fun recalculateAfterContribution(
        plan: FixedBudgetPlan,
        actualContribution: Double,
        forPaymentNumber: Int,
        goals: List<Goal>,
        behavior: CompletionBehavior
    ): FixedBudgetPlan {
        clearCache()

        // Calculate total remaining after this payment
        val completedPayments = plan.schedule.take(forPaymentNumber)
        val totalContributedBefore = completedPayments.sumOf { it.totalAmount }
        val adjustedTotalContributed = totalContributedBefore -
            (completedPayments.lastOrNull()?.totalAmount ?: 0.0) + actualContribution

        // Calculate remaining amount for all goals
        var totalRemaining = 0.0
        for (goal in goals.filter { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE }) {
            val remaining = calculateRemaining(goal)
            val convertedRemaining = if (!goal.currency.equals(plan.currency, ignoreCase = true)) {
                convertAmount(remaining, goal.currency, plan.currency)
            } else {
                remaining
            }
            totalRemaining += convertedRemaining
        }

        // Subtract what's already contributed
        val remainingAfterContribution = max(0.0, totalRemaining - adjustedTotalContributed)

        return when (behavior) {
            CompletionBehavior.FINISH_FASTER -> {
                // Keep the same monthly budget, goals complete earlier if over-contributed
                // Just regenerate the schedule from the current state
                generateSchedule(goals, plan.monthlyBudget, plan.currency)
            }

            CompletionBehavior.LOWER_PAYMENTS -> {
                // Recalculate to spread remaining amount over remaining months
                // Keep original timeline, reduce monthly amount
                val remainingPayments = plan.schedule.size - forPaymentNumber
                if (remainingPayments <= 0) {
                    // No more payments needed
                    generateSchedule(goals, plan.monthlyBudget, plan.currency)
                } else {
                    val newMonthlyBudget = remainingAfterContribution / remainingPayments.toDouble()
                    // Ensure we don't go below minimum required
                    val minimum = calculateMinimumBudget(goals, plan.currency)
                    val adjustedBudget = max(newMonthlyBudget, minimum)
                    generateSchedule(goals, adjustedBudget, plan.currency)
                }
            }
        }
    }

    /**
     * Calculate the difference between planned and actual contribution.
     */
    fun contributionDifference(
        plan: FixedBudgetPlan,
        actualContribution: Double,
        forPaymentNumber: Int
    ): Double {
        if (forPaymentNumber < 1 || forPaymentNumber > plan.schedule.size) {
            return 0.0
        }
        val plannedAmount = plan.schedule[forPaymentNumber - 1].totalAmount
        return actualContribution - plannedAmount
    }

    /**
     * Get a summary of how the schedule would be adjusted.
     * @return Pair of (new monthly amount for LOWER_PAYMENTS, months saved for FINISH_FASTER)
     */
    fun adjustedScheduleSummary(
        plan: FixedBudgetPlan,
        actualContribution: Double,
        forPaymentNumber: Int,
        behavior: CompletionBehavior
    ): Pair<Double?, Int?> {
        val difference = contributionDifference(plan, actualContribution, forPaymentNumber)

        return when (behavior) {
            CompletionBehavior.FINISH_FASTER -> {
                // Calculate how many months could be saved
                if (difference > 0) {
                    val remainingPayments = plan.schedule.size - forPaymentNumber
                    val monthsSaved = (difference / plan.monthlyBudget).toInt()
                    Pair(null, min(monthsSaved, remainingPayments))
                } else {
                    Pair(null, null)
                }
            }

            CompletionBehavior.LOWER_PAYMENTS -> {
                // Calculate new monthly amount
                val futurePayments = plan.schedule.drop(forPaymentNumber)
                val totalRemaining = futurePayments.sumOf { it.totalAmount }
                val adjustedRemaining = totalRemaining - difference
                val remainingPayments = plan.schedule.size - forPaymentNumber
                if (remainingPayments <= 0) {
                    Pair(null, null)
                } else {
                    val newMonthly = adjustedRemaining / remainingPayments.toDouble()
                    Pair(newMonthly, null)
                }
            }
        }
    }

    // Private helpers

    private suspend fun calculateRemaining(goal: Goal): Double {
        val currentTotal = calculateCurrentTotal(goal)
        return max(0.0, goal.targetAmount - currentTotal)
    }

    private suspend fun calculateCurrentTotal(goal: Goal): Double {
        val allocations = allocationRepository.getAllocationsForGoal(goal.id)

        var total = 0.0
        for (allocation in allocations) {
            val asset = assetRepository.getAssetById(allocation.assetId)
            val assetCurrency = asset?.currency ?: goal.currency

            val manualBalance = transactionRepository.getManualBalanceForAsset(allocation.assetId)
            val onChainBalance = runCatching {
                if (asset != null && !asset.address.isNullOrBlank() && !asset.chainId.isNullOrBlank()) {
                    onChainBalanceRepository.getBalance(asset, forceRefresh = false).getOrNull()?.balance ?: 0.0
                } else {
                    0.0
                }
            }.getOrElse { 0.0 }
            val assetBalance = manualBalance + onChainBalance

            val allAssetAllocations = allocationRepository.getAllocationsForAsset(allocation.assetId)
            val totalAllocatedForAsset = allAssetAllocations.sumOf { max(0.0, it.amount) }
            val fundedInAssetCurrency = AllocationFunding.fundedPortion(
                allocationAmount = allocation.amount,
                assetBalance = assetBalance,
                totalAllocatedForAsset = totalAllocatedForAsset
            )

            val fundedInGoalCurrency = if (assetCurrency.equals(goal.currency, ignoreCase = true)) {
                fundedInAssetCurrency
            } else {
                convertAmount(fundedInAssetCurrency, assetCurrency, goal.currency)
            }
            total += fundedInGoalCurrency
        }

        return total
    }

    private suspend fun convertAmount(amount: Double, fromCurrency: String, toCurrency: String): Double {
        if (fromCurrency.equals(toCurrency, ignoreCase = true)) return amount
        return try {
            val rate = exchangeRateRepository.fetchRate(fromCurrency, toCurrency)
            amount * rate
        } catch (e: Exception) {
            amount
        }
    }

    private fun calculateMonthsRemaining(startDate: LocalDate, endDate: LocalDate): Int {
        val payDay = settings.paymentDay

        var paymentDate = startDate.withDayOfMonth(min(payDay, startDate.lengthOfMonth()))

        if (!paymentDate.isAfter(startDate)) {
            paymentDate = paymentDate.plusMonths(1)
            paymentDate = paymentDate.withDayOfMonth(min(payDay, paymentDate.lengthOfMonth()))
        }

        var count = 0
        while (paymentDate.isBefore(endDate)) {
            count++
            paymentDate = paymentDate.plusMonths(1)
            paymentDate = paymentDate.withDayOfMonth(min(payDay, paymentDate.lengthOfMonth()))
        }

        return max(1, count)
    }

    private fun nextPaymentDate(): LocalDate {
        val now = LocalDate.now()
        val payDay = settings.paymentDay

        var paymentDate = now.withDayOfMonth(min(payDay, now.lengthOfMonth()))

        if (!paymentDate.isAfter(now)) {
            paymentDate = paymentDate.plusMonths(1)
            paymentDate = paymentDate.withDayOfMonth(min(payDay, paymentDate.lengthOfMonth()))
        }

        return paymentDate
    }

    private data class CurrentBlock(
        val goalId: String,
        val startPayment: Int,
        val startDate: LocalDate,
        val totalAmount: Double,
        val paymentCount: Int,
        val endPayment: Int,
        val endDate: LocalDate
    )
}
