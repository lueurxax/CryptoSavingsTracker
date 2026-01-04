package com.xax.CryptoSavingsTracker.domain.model

/**
 * Represents the impact of changes to a goal, comparing before and after states.
 * Used to preview how modifications will affect goal progress and targets.
 */
data class GoalImpact(
    val oldProgress: Double,
    val newProgress: Double,
    val oldDailyTarget: Double,
    val newDailyTarget: Double,
    val oldDaysRemaining: Int,
    val newDaysRemaining: Int,
    val oldTargetAmount: Double,
    val newTargetAmount: Double,
    val significantChange: Boolean = false
) {
    /** Whether the change is positive (progress increased or daily target decreased) */
    val isPositiveChange: Boolean
        get() = newProgress >= oldProgress && newDailyTarget <= oldDailyTarget

    /** Change in progress percentage */
    val progressChange: Double
        get() = newProgress - oldProgress

    /** Change in target amount */
    val targetAmountChange: Double
        get() = newTargetAmount - oldTargetAmount

    /** Change in daily target */
    val dailyTargetChange: Double
        get() = newDailyTarget - oldDailyTarget

    /** Change in days remaining */
    val daysRemainingChange: Int
        get() = newDaysRemaining - oldDaysRemaining

    companion object {
        /**
         * Calculate goal impact from goal changes.
         */
        fun calculate(
            currentAmount: Double,
            oldTargetAmount: Double,
            newTargetAmount: Double,
            oldDaysRemaining: Int,
            newDaysRemaining: Int
        ): GoalImpact {
            val oldProgress = if (oldTargetAmount > 0) (currentAmount / oldTargetAmount).coerceIn(0.0, 1.0) else 0.0
            val newProgress = if (newTargetAmount > 0) (currentAmount / newTargetAmount).coerceIn(0.0, 1.0) else 0.0

            val oldDaily = if (oldDaysRemaining > 0) {
                ((oldTargetAmount - currentAmount).coerceAtLeast(0.0)) / oldDaysRemaining
            } else 0.0

            val newDaily = if (newDaysRemaining > 0) {
                ((newTargetAmount - currentAmount).coerceAtLeast(0.0)) / newDaysRemaining
            } else 0.0

            // Significant change if progress drops >10%, daily target increases >50%, or deadline moves >30 days
            val significant = (oldProgress - newProgress) > 0.1 ||
                    (newDaily - oldDaily) > oldDaily * 0.5 ||
                    kotlin.math.abs(oldDaysRemaining - newDaysRemaining) > 30

            return GoalImpact(
                oldProgress = oldProgress,
                newProgress = newProgress,
                oldDailyTarget = oldDaily,
                newDailyTarget = newDaily,
                oldDaysRemaining = oldDaysRemaining,
                newDaysRemaining = newDaysRemaining,
                oldTargetAmount = oldTargetAmount,
                newTargetAmount = newTargetAmount,
                significantChange = significant
            )
        }
    }
}
