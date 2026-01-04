package com.xax.CryptoSavingsTracker.domain.model

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.UUID

/**
 * A contribution to a single goal within a scheduled payment.
 */
data class GoalContribution(
    val id: String = UUID.randomUUID().toString(),
    val goalId: String,
    val goalName: String,
    val amount: Double,
    val isGoalStart: Boolean = false,
    val isGoalComplete: Boolean = false,
    val runningTotal: Double
)

/**
 * A single payment on a specific date (may fund multiple goals).
 */
data class ScheduledPayment(
    val id: String = UUID.randomUUID().toString(),
    val paymentDate: LocalDate,
    val paymentNumber: Int,
    val contributions: List<GoalContribution>
) {
    val totalAmount: Double
        get() = contributions.sumOf { it.amount }

    /** Returns formatted payment date (e.g., "Jan 15"). */
    val formattedDate: String
        get() = paymentDate.format(DateTimeFormatter.ofPattern("MMM d"))

    /** Returns full formatted payment date. */
    val formattedDateFull: String
        get() = paymentDate.format(DateTimeFormatter.ofPattern("MMM d, yyyy"))
}

/**
 * The budget calculator preview plan (not persisted).
 */
data class BudgetCalculatorPlan(
    val id: String = UUID.randomUUID().toString(),
    val createdAt: Long = System.currentTimeMillis(),
    val monthlyBudget: Double,
    val currency: String,
    val schedule: List<ScheduledPayment>,
    val isLeveled: Boolean,
    val minimumRequired: Double,
    val goalRemainingById: Map<String, Double> = emptyMap()
) {
    /** Total amount across all scheduled payments. */
    val totalAmount: Double
        get() = schedule.sumOf { it.totalAmount }

    /** Number of months in the plan. */
    val totalMonths: Int
        get() = schedule.size

    /** First payment date. */
    val startDate: LocalDate?
        get() = schedule.firstOrNull()?.paymentDate

    /** Last payment date. */
    val endDate: LocalDate?
        get() = schedule.lastOrNull()?.paymentDate
}

/**
 * Represents a goal's period in the timeline visualization.
 */
data class ScheduledGoalBlock(
    val id: String = UUID.randomUUID().toString(),
    val goalId: String,
    val goalName: String,
    val emoji: String?,
    val startPaymentNumber: Int,
    val endPaymentNumber: Int,
    val startDate: LocalDate,
    val endDate: LocalDate,
    val totalAmount: Double,
    val paymentCount: Int,
    val isComplete: Boolean = false
) {
    /** Formatted date range (e.g., "Jan 2026 - Mar 2026"). */
    val dateRange: String
        get() {
            val formatter = DateTimeFormatter.ofPattern("MMM yyyy")
            return "${startDate.format(formatter)} - ${endDate.format(formatter)}"
        }
}

/**
 * A goal that cannot be met with the current budget.
 */
data class InfeasibleGoal(
    val id: String = UUID.randomUUID().toString(),
    val goalId: String,
    val goalName: String,
    val deadline: LocalDate,
    val requiredMonthly: Double,
    val shortfall: Double,
    val currency: String
)

/**
 * A suggested action to resolve budget infeasibility.
 */
sealed class FeasibilitySuggestion {
    abstract val id: String
    abstract val title: String
    abstract val iconName: String

    data class IncreaseBudget(
        val to: Double,
        val currency: String
    ) : FeasibilitySuggestion() {
        override val id: String = "increase_$to"
        override val title: String = "Increase budget to ${formatCurrency(to, currency)}/mo"
        override val iconName: String = "arrow_upward"
    }

    data class ExtendDeadline(
        val goalId: String,
        val goalName: String,
        val byMonths: Int
    ) : FeasibilitySuggestion() {
        override val id: String = "extend_${goalId}_$byMonths"
        override val title: String = "Extend $goalName by $byMonths month${if (byMonths == 1) "" else "s"}"
        override val iconName: String = "event"
    }

    data class ReduceTarget(
        val goalId: String,
        val goalName: String,
        val to: Double,
        val currency: String
    ) : FeasibilitySuggestion() {
        override val id: String = "reduce_${goalId}_$to"
        override val title: String = "Reduce $goalName target to ${formatCurrency(to, currency)}"
        override val iconName: String = "remove_circle"
    }

    data class EditGoal(
        val goalId: String,
        val goalName: String
    ) : FeasibilitySuggestion() {
        override val id: String = "edit_$goalId"
        override val title: String = "Edit $goalName..."
        override val iconName: String = "edit"
    }

    companion object {
        private fun formatCurrency(amount: Double, currency: String): String {
            return java.text.NumberFormat.getCurrencyInstance().apply {
                this.currency = java.util.Currency.getInstance(currency)
                maximumFractionDigits = 0
            }.format(amount)
        }
    }
}

/**
 * Severity level for budget feasibility.
 */
enum class FeasibilityLevel {
    ACHIEVABLE,
    AT_RISK,
    CRITICAL;

    val iconName: String
        get() = when (this) {
            ACHIEVABLE -> "check_circle"
            AT_RISK -> "warning"
            CRITICAL -> "cancel"
        }
}

/**
 * Result of checking if a budget is sufficient for all goals.
 */
data class FeasibilityResult(
    val isFeasible: Boolean,
    val minimumRequired: Double,
    val currency: String,
    val infeasibleGoals: List<InfeasibleGoal>,
    val suggestions: List<FeasibilitySuggestion>
) {
    val statusDescription: String
        get() = when {
            isFeasible -> "All deadlines achievable"
            infeasibleGoals.size == 1 -> "1 goal at risk"
            else -> "${infeasibleGoals.size} goals at risk"
        }

    val statusLevel: FeasibilityLevel
        get() = when {
            isFeasible -> FeasibilityLevel.ACHIEVABLE
            infeasibleGoals.size == 1 -> FeasibilityLevel.AT_RISK
            else -> FeasibilityLevel.CRITICAL
        }

    companion object {
        val EMPTY = FeasibilityResult(
            isFeasible = true,
            minimumRequired = 0.0,
            currency = "USD",
            infeasibleGoals = emptyList(),
            suggestions = emptyList()
        )
    }
}
