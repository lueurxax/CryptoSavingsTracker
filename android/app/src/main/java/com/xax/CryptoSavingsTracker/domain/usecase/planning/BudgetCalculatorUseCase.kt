package com.xax.CryptoSavingsTracker.domain.usecase.planning

import com.xax.CryptoSavingsTracker.domain.model.BudgetCalculatorPlan
import com.xax.CryptoSavingsTracker.domain.model.FeasibilityResult
import com.xax.CryptoSavingsTracker.domain.model.FeasibilitySuggestion
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalContribution
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.InfeasibleGoal
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
import com.xax.CryptoSavingsTracker.domain.model.ScheduledGoalBlock
import com.xax.CryptoSavingsTracker.domain.model.ScheduledPayment
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalProgressUseCase
import java.time.LocalDate
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/**
 * Use case for computing budget calculator previews with optimal contribution sequencing.
 * Mirrors iOS BudgetCalculatorService behavior.
 */
@Singleton
class BudgetCalculatorUseCase @Inject constructor(
    private val exchangeRateRepository: ExchangeRateRepository,
    private val getGoalProgressUseCase: GetGoalProgressUseCase,
    private val settings: MonthlyPlanningSettings
) {
    private var cachedPlan: BudgetCalculatorPlan? = null
    private var cacheGoalIds: Set<String> = emptySet()
    private var cacheBudget: Double = 0.0
    private var cacheCurrency: String = ""
    private var lastCacheUpdate: Long = 0
    private val cacheExpiration: Long = 300_000

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

    suspend fun checkFeasibility(goals: List<Goal>, budget: Double, currency: String): FeasibilityResult {
        if (goals.isEmpty()) return FeasibilityResult.EMPTY

        val minimumRequired = calculateMinimumBudget(goals, currency)
        val isFeasible = budget >= minimumRequired && budget > 0

        val infeasibleGoals = mutableListOf<InfeasibleGoal>()
        val suggestions = mutableListOf<FeasibilitySuggestion>()
        var addedGoalSuggestions = false

        if (!isFeasible) {
            val activeGoals = goals
                .filter { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
                .sortedBy { it.deadline }
            var cumulativeRemaining = 0.0

            for (goal in activeGoals) {
                val remainingInGoalCurrency = calculateRemaining(goal)
                var remaining = remainingInGoalCurrency
                var conversionRate: Double? = null
                if (!goal.currency.equals(currency, ignoreCase = true)) {
                    val converted = convertAmount(remaining, goal.currency, currency)
                    conversionRate = if (remaining > 0) converted / remaining else null
                    remaining = converted
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

                    if (!addedGoalSuggestions && budget > 0) {
                        val monthsNeeded = ceil(cumulativeRemaining / budget).toInt()
                        val extensionMonths = max(0, monthsNeeded - months)
                        if (extensionMonths > 0) {
                            suggestions.add(
                                FeasibilitySuggestion.ExtendDeadline(
                                    goalId = goal.id,
                                    goalName = goal.name,
                                    byMonths = extensionMonths
                                )
                            )
                        }

                        val reductionBudget = shortfall * months.toDouble()
                        val reductionGoalCurrency = conversionRate?.let { reductionBudget / it } ?: reductionBudget
                        val currentTotal = max(0.0, goal.targetAmount - remainingInGoalCurrency)
                        val proposedTarget = max(currentTotal, goal.targetAmount - reductionGoalCurrency)
                        if (proposedTarget < goal.targetAmount) {
                            suggestions.add(
                                FeasibilitySuggestion.ReduceTarget(
                                    goalId = goal.id,
                                    goalName = goal.name,
                                    to = proposedTarget,
                                    currency = currency  // Use display currency, not goal's original currency
                                )
                            )
                        }

                        suggestions.add(
                            FeasibilitySuggestion.EditGoal(
                                goalId = goal.id,
                                goalName = goal.name
                            )
                        )
                        addedGoalSuggestions = true
                    }
                }
            }

            if (infeasibleGoals.isNotEmpty()) {
                suggestions.add(FeasibilitySuggestion.IncreaseBudget(minimumRequired, currency))
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

    suspend fun generateSchedule(goals: List<Goal>, budget: Double, currency: String): BudgetCalculatorPlan {
        val goalIds = goals.map { it.id }.toSet()
        val now = System.currentTimeMillis()
        if (cachedPlan != null &&
            cacheGoalIds == goalIds &&
            abs(cacheBudget - budget) < 0.01 &&
            cacheCurrency.equals(currency, ignoreCase = true) &&
            now - lastCacheUpdate < cacheExpiration
        ) {
            return cachedPlan!!
        }

        val activeGoals = goals
            .filter { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
            .sortedBy { it.deadline }

        if (activeGoals.isEmpty()) {
            return BudgetCalculatorPlan(
                monthlyBudget = budget,
                currency = currency,
                schedule = emptyList(),
                isLeveled = true,
                minimumRequired = 0.0,
                goalRemainingById = emptyMap()
            )
        }

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

        if (budget <= 0.0) {
            val minimumRequired = calculateMinimumBudget(goals, currency)
            return BudgetCalculatorPlan(
                monthlyBudget = budget,
                currency = currency,
                schedule = emptyList(),
                isLeveled = false,
                minimumRequired = minimumRequired,
                goalRemainingById = goalRemaining
            )
        }

        val payments = mutableListOf<ScheduledPayment>()
        var paymentNumber = 1
        var paymentDate = nextPaymentDate()
        val goalRunningTotals = activeGoals.associate { it.id to 0.0 }.toMutableMap()
        val remainingByGoal = goalRemaining.toMutableMap()

        var safetyCounter = 0
        while (remainingByGoal.values.any { it > 0.01 } && safetyCounter < 600) {
            safetyCounter += 1
            val startTotals = goalRunningTotals.toMap()
            val paymentAllocations = mutableMapOf<String, Double>()
            var remainingBudget = budget

            for (goal in activeGoals) {
                if (paymentDate.isAfter(goal.deadline)) continue
                val remaining = remainingByGoal[goal.id] ?: 0.0
                if (remaining <= 0.01) continue
                val amount = min(remainingBudget, remaining)
                if (amount <= 0.01) continue
                paymentAllocations[goal.id] = (paymentAllocations[goal.id] ?: 0.0) + amount
                goalRunningTotals[goal.id] = (goalRunningTotals[goal.id] ?: 0.0) + amount
                remainingByGoal[goal.id] = max(0.0, remaining - amount)
                remainingBudget -= amount
                if (remainingBudget <= 0.01) break
            }

            if (paymentAllocations.isEmpty()) break

            val contributions = activeGoals.mapNotNull { goal ->
                val amount = paymentAllocations[goal.id] ?: return@mapNotNull null
                if (amount <= 0.01) return@mapNotNull null
                val startingTotal = startTotals[goal.id] ?: 0.0
                val newTotal = goalRunningTotals[goal.id] ?: 0.0
                GoalContribution(
                    goalId = goal.id,
                    goalName = goalNames[goal.id] ?: goal.name,
                    amount = amount,
                    isGoalStart = startingTotal <= 0.01,
                    isGoalComplete = (remainingByGoal[goal.id] ?: 0.0) <= 0.01,
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

            paymentNumber += 1
            paymentDate = paymentDate.plusMonths(1)
        }

        val minimumRequired = calculateMinimumBudget(goals, currency)
        val plan = BudgetCalculatorPlan(
            monthlyBudget = budget,
            currency = currency,
            schedule = payments,
            isLeveled = abs(budget - minimumRequired) < 0.01,
            minimumRequired = minimumRequired,
            goalRemainingById = goalRemaining
        )

        cachedPlan = plan
        cacheGoalIds = goalIds
        cacheBudget = budget
        cacheCurrency = currency
        lastCacheUpdate = System.currentTimeMillis()

        return plan
    }

    fun buildTimelineBlocks(plan: BudgetCalculatorPlan, goals: List<Goal>): List<ScheduledGoalBlock> {
        val deadlines = goals.associate { it.id to it.deadline }
        val summaries = mutableMapOf<String, TimelineSummary>()

        for (payment in plan.schedule) {
            for (contribution in payment.contributions) {
                val deadline = deadlines[contribution.goalId] ?: continue
                if (payment.paymentDate.isAfter(deadline)) continue
                val existing = summaries[contribution.goalId]
                if (existing == null) {
                    summaries[contribution.goalId] = TimelineSummary(
                        goalName = contribution.goalName,
                        startPayment = payment.paymentNumber,
                        endPayment = payment.paymentNumber,
                        startDate = payment.paymentDate,
                        endDate = payment.paymentDate,
                        totalAmount = contribution.amount,
                        paymentCount = 1
                    )
                } else {
                    summaries[contribution.goalId] = existing.copy(
                        endPayment = payment.paymentNumber,
                        endDate = payment.paymentDate,
                        totalAmount = existing.totalAmount + contribution.amount,
                        paymentCount = existing.paymentCount + 1
                    )
                }
            }
        }

        return summaries.entries
            .sortedBy { it.value.startPayment }
            .map { entry ->
                val goal = goals.firstOrNull { it.id == entry.key }
                ScheduledGoalBlock(
                    goalId = entry.key,
                    goalName = entry.value.goalName,
                    emoji = goal?.emoji,
                    startPaymentNumber = entry.value.startPayment,
                    endPaymentNumber = entry.value.endPayment,
                    startDate = entry.value.startDate,
                    endDate = entry.value.endDate,
                    totalAmount = entry.value.totalAmount,
                    paymentCount = entry.value.endPayment - entry.value.startPayment + 1
                )
            }
    }

    private data class TimelineSummary(
        val goalName: String,
        val startPayment: Int,
        val endPayment: Int,
        val startDate: LocalDate,
        val endDate: LocalDate,
        val totalAmount: Double,
        val paymentCount: Int
    )

    private suspend fun calculateRemaining(goal: Goal): Double {
        val progress = getGoalProgressUseCase.getProgress(goal.id)
        val fundedAmount = progress?.fundedAmount ?: 0.0
        return max(0.0, goal.targetAmount - fundedAmount)
    }

    private suspend fun convertAmount(amount: Double, from: String, to: String): Double {
        return if (from.equals(to, ignoreCase = true)) {
            amount
        } else {
            val rate = exchangeRateRepository.fetchRate(from, to)
            amount * rate
        }
    }

    private fun calculateMonthsRemaining(startDate: LocalDate, endDate: LocalDate): Int {
        val paymentDay = settings.paymentDay
        var paymentDate = LocalDate.of(startDate.year, startDate.month, paymentDay)
        if (!paymentDate.isAfter(startDate)) {
            paymentDate = paymentDate.plusMonths(1)
        }

        var count = 0
        while (paymentDate.isBefore(endDate)) {
            count += 1
            paymentDate = paymentDate.plusMonths(1)
        }
        return max(1, count)
    }

    private fun nextPaymentDate(): LocalDate {
        val today = LocalDate.now()
        val paymentDay = settings.paymentDay
        var paymentDate = LocalDate.of(today.year, today.month, paymentDay)
        if (!paymentDate.isAfter(today)) {
            paymentDate = paymentDate.plusMonths(1)
        }
        return paymentDate
    }
}
