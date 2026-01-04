package com.xax.CryptoSavingsTracker.domain.model

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.min

/**
 * User preferences for monthly planning display and calculations.
 * Matches iOS MonthlyPlanningSettings for feature parity.
 */
@Singleton
class MonthlyPlanningSettings @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    // Observable state for UI reactivity
    private val _settingsChanged = MutableStateFlow(0L)
    val settingsChanged: StateFlow<Long> = _settingsChanged.asStateFlow()

    // MARK: - Display Settings

    /**
     * Currency to display total monthly requirements in
     */
    var displayCurrency: String
        get() = prefs.getString(Keys.DISPLAY_CURRENCY, "USD")?.uppercase() ?: "USD"
        set(value) {
            prefs.edit().putString(Keys.DISPLAY_CURRENCY, value.uppercase()).apply()
            notifyChange()
        }

    /**
     * Currency to display execution remaining amounts in.
     */
    var executionDisplayCurrency: String
        get() = prefs.getString(Keys.EXECUTION_DISPLAY_CURRENCY, displayCurrency)?.uppercase() ?: displayCurrency
        set(value) {
            prefs.edit().putString(Keys.EXECUTION_DISPLAY_CURRENCY, value.uppercase()).apply()
            notifyChange()
        }

    /**
     * Day of month when payments are due (1-28 to avoid month-length issues)
     */
    var paymentDay: Int
        get() = prefs.getInt(Keys.PAYMENT_DAY, 1).coerceIn(1, 28)
        set(value) {
            prefs.edit().putInt(Keys.PAYMENT_DAY, value.coerceIn(1, 28)).apply()
            notifyChange()
        }

    // MARK: - Notification Settings

    /**
     * Whether to show notifications for upcoming payment deadlines
     */
    var notificationsEnabled: Boolean
        get() = prefs.getBoolean(Keys.NOTIFICATIONS_ENABLED, false)
        set(value) {
            prefs.edit().putBoolean(Keys.NOTIFICATIONS_ENABLED, value).apply()
            notifyChange()
        }

    /**
     * How many days before payment day to send reminder notifications
     */
    var notificationDays: Int
        get() = prefs.getInt(Keys.NOTIFICATION_DAYS, 3).coerceIn(1, 7)
        set(value) {
            prefs.edit().putInt(Keys.NOTIFICATION_DAYS, value.coerceIn(1, 7)).apply()
            notifyChange()
        }

    // MARK: - Automation Settings

    /**
     * Automatically start tracking on the 1st of each month
     */
    var autoStartEnabled: Boolean
        get() = prefs.getBoolean(Keys.AUTO_START_ENABLED, false)
        set(value) {
            prefs.edit().putBoolean(Keys.AUTO_START_ENABLED, value).apply()
            notifyChange()
        }

    /**
     * Automatically mark month complete on the last day of the month
     */
    var autoCompleteEnabled: Boolean
        get() = prefs.getBoolean(Keys.AUTO_COMPLETE_ENABLED, false)
        set(value) {
            prefs.edit().putBoolean(Keys.AUTO_COMPLETE_ENABLED, value).apply()
            notifyChange()
        }

    /**
     * Hours available for undo grace period (24, 48, 168 for 7 days, or 0 for no undo)
     */
    var undoGracePeriodHours: Int
        get() = prefs.getInt(Keys.UNDO_GRACE_PERIOD_HOURS, 24).coerceIn(0, 168)
        set(value) {
            prefs.edit().putInt(Keys.UNDO_GRACE_PERIOD_HOURS, value.coerceIn(0, 168)).apply()
            notifyChange()
        }

    // MARK: - Fixed Budget Settings

    /**
     * Whether Fixed Budget mode is enabled (vs Per Goal mode)
     */
    var isFixedBudgetEnabled: Boolean
        get() = prefs.getBoolean(Keys.IS_FIXED_BUDGET_ENABLED, false)
        set(value) {
            prefs.edit().putBoolean(Keys.IS_FIXED_BUDGET_ENABLED, value).apply()
            notifyChange()
        }

    /**
     * User's monthly savings budget amount (null = use calculated minimum)
     */
    var monthlyBudget: Double?
        get() = if (prefs.contains(Keys.MONTHLY_BUDGET)) {
            prefs.getFloat(Keys.MONTHLY_BUDGET, 0f).toDouble()
        } else null
        set(value) {
            if (value != null) {
                prefs.edit().putFloat(Keys.MONTHLY_BUDGET, value.toFloat()).apply()
            } else {
                prefs.edit().remove(Keys.MONTHLY_BUDGET).apply()
            }
            notifyChange()
        }

    /**
     * Currency for the fixed budget
     */
    var budgetCurrency: String
        get() = prefs.getString(Keys.BUDGET_CURRENCY, "USD")?.uppercase() ?: "USD"
        set(value) {
            prefs.edit().putString(Keys.BUDGET_CURRENCY, value.uppercase()).apply()
            notifyChange()
        }

    /**
     * What happens when a goal completes early
     */
    var completionBehavior: CompletionBehavior
        get() {
            val name = prefs.getString(Keys.COMPLETION_BEHAVIOR, CompletionBehavior.FINISH_FASTER.name)
            return try {
                CompletionBehavior.valueOf(name ?: CompletionBehavior.FINISH_FASTER.name)
            } catch (_: IllegalArgumentException) {
                CompletionBehavior.FINISH_FASTER
            }
        }
        set(value) {
            prefs.edit().putString(Keys.COMPLETION_BEHAVIOR, value.name).apply()
            notifyChange()
        }

    /**
     * Whether user has completed the fixed budget onboarding flow
     */
    var hasCompletedFixedBudgetOnboarding: Boolean
        get() = prefs.getBoolean(Keys.HAS_COMPLETED_FIXED_BUDGET_ONBOARDING, false)
        set(value) {
            prefs.edit().putBoolean(Keys.HAS_COMPLETED_FIXED_BUDGET_ONBOARDING, value).apply()
            notifyChange()
        }

    /**
     * Whether user has seen the Fixed Budget intro card (promotional)
     */
    var hasSeenFixedBudgetIntro: Boolean
        get() = prefs.getBoolean(Keys.HAS_SEEN_FIXED_BUDGET_INTRO, false)
        set(value) {
            prefs.edit().putBoolean(Keys.HAS_SEEN_FIXED_BUDGET_INTRO, value).apply()
            notifyChange()
        }

    /**
     * Current planning mode (convenience property)
     */
    var planningMode: PlanningMode
        get() = if (isFixedBudgetEnabled) PlanningMode.FIXED_BUDGET else PlanningMode.PER_GOAL
        set(value) {
            isFixedBudgetEnabled = (value == PlanningMode.FIXED_BUDGET)
        }

    // MARK: - Computed Properties

    /**
     * Next payment deadline based on current date and payment day
     */
    val nextPaymentDate: LocalDate
        get() {
            val now = LocalDate.now()
            val thisMonthPaymentDay = min(paymentDay, now.lengthOfMonth())
            val thisMonthDate = now.withDayOfMonth(thisMonthPaymentDay)

            return if (thisMonthDate.isAfter(now)) {
                thisMonthDate
            } else {
                val nextMonth = now.plusMonths(1)
                val nextMonthPaymentDay = min(paymentDay, nextMonth.lengthOfMonth())
                nextMonth.withDayOfMonth(nextMonthPaymentDay)
            }
        }

    /**
     * Days remaining until next payment
     */
    val daysUntilPayment: Int
        get() = ChronoUnit.DAYS.between(LocalDate.now(), nextPaymentDate).toInt().coerceAtLeast(0)

    /**
     * Formatted display of next payment date
     */
    val nextPaymentFormatted: String
        get() = nextPaymentDate.format(DateTimeFormatter.ofPattern("MMM d, yyyy"))

    /**
     * Current month label (format: "2025-12")
     */
    val currentMonthLabel: String
        get() = LocalDate.now().format(DateTimeFormatter.ofPattern("yyyy-MM"))

    // MARK: - Public Methods

    /**
     * Reset all settings to defaults
     */
    fun resetToDefaults() {
        displayCurrency = "USD"
        paymentDay = 1
        notificationsEnabled = true
        notificationDays = 3
        autoStartEnabled = false
        autoCompleteEnabled = false
        undoGracePeriodHours = 24
        // Fixed Budget settings
        isFixedBudgetEnabled = false
        monthlyBudget = null
        budgetCurrency = "USD"
        completionBehavior = CompletionBehavior.FINISH_FASTER
        hasCompletedFixedBudgetOnboarding = false
    }

    /**
     * Validate payment day for current month
     */
    fun validatePaymentDay(): Boolean = paymentDay in 1..28

    /**
     * Get payment day options with descriptions
     */
    fun getPaymentDayOptions(): List<Pair<Int, String>> {
        val options = mutableListOf<Pair<Int, String>>()

        // Popular options first
        options.add(1 to "1st of every month")
        options.add(15 to "15th of every month")

        // Other options
        for (day in 2..28) {
            if (day != 15) {
                options.add(day to "${day}${day.ordinalSuffix} of every month")
            }
        }

        return options
    }

    /**
     * Get undo grace period options
     */
    fun getUndoGracePeriodOptions(): List<Pair<Int, String>> = listOf(
        0 to "Disabled (no undo)",
        24 to "24 hours",
        48 to "48 hours",
        168 to "7 days"
    )

    private fun notifyChange() {
        _settingsChanged.value = System.currentTimeMillis()
    }

    private val Int.ordinalSuffix: String
        get() = when {
            this % 100 in 11..13 -> "th"
            this % 10 == 1 -> "st"
            this % 10 == 2 -> "nd"
            this % 10 == 3 -> "rd"
            else -> "th"
        }

    private object Keys {
        const val DISPLAY_CURRENCY = "MonthlyPlanning.DisplayCurrency"
        const val EXECUTION_DISPLAY_CURRENCY = "MonthlyPlanning.ExecutionDisplayCurrency"
        const val PAYMENT_DAY = "MonthlyPlanning.PaymentDay"
        const val NOTIFICATIONS_ENABLED = "MonthlyPlanning.NotificationsEnabled"
        const val NOTIFICATION_DAYS = "MonthlyPlanning.NotificationDays"
        const val AUTO_START_ENABLED = "MonthlyPlanning.AutoStartEnabled"
        const val AUTO_COMPLETE_ENABLED = "MonthlyPlanning.AutoCompleteEnabled"
        const val UNDO_GRACE_PERIOD_HOURS = "MonthlyPlanning.UndoGracePeriodHours"
        // Fixed Budget settings
        const val IS_FIXED_BUDGET_ENABLED = "MonthlyPlanning.FixedBudget.IsEnabled"
        const val MONTHLY_BUDGET = "MonthlyPlanning.FixedBudget.MonthlyBudget"
        const val BUDGET_CURRENCY = "MonthlyPlanning.FixedBudget.Currency"
        const val COMPLETION_BEHAVIOR = "MonthlyPlanning.FixedBudget.CompletionBehavior"
        const val HAS_COMPLETED_FIXED_BUDGET_ONBOARDING = "MonthlyPlanning.FixedBudget.HasCompletedOnboarding"
        const val HAS_SEEN_FIXED_BUDGET_INTRO = "MonthlyPlanning.FixedBudget.HasSeenIntro"
    }

    companion object {
        private const val PREFS_NAME = "monthly_planning_settings"
    }
}
