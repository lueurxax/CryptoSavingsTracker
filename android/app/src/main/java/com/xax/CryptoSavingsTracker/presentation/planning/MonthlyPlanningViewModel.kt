package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.MonthlyRequirement
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlan
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanGoalSettings
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanSettings
import com.xax.CryptoSavingsTracker.domain.model.RequirementStatus
import com.xax.CryptoSavingsTracker.domain.repository.MonthlyPlanRepository
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningService
import com.xax.CryptoSavingsTracker.domain.util.MonthLabelUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class MonthlyRequirementRow(
    val requirement: MonthlyRequirement,
    val adjustedRequiredMonthly: Double,
    val isProtected: Boolean,
    val isSkipped: Boolean,
    val customAmount: Double?
) {
    val goalId: String get() = requirement.goalId

    fun formattedAdjustedRequiredMonthly(): String {
        return "${requirement.currency} ${String.format("%,.0f", adjustedRequiredMonthly)}"
    }
}

/**
 * UI State for Monthly Planning screen
 */
data class MonthlyPlanningUiState(
    val monthLabel: String = "",
    val requirements: List<MonthlyRequirementRow> = emptyList(),
    val baseTotalRequired: Double = 0.0,
    val totalRequired: Double = 0.0,
    val displayCurrency: String = "USD",
    val paymentDay: Int = 1,
    val flexPercentage: Double = 1.0,
    val isLoading: Boolean = true,
    val error: String? = null,
    val showSettingsDialog: Boolean = false
) {
    val completedCount: Int
        get() = requirements.count { it.requirement.status == RequirementStatus.COMPLETED }

    val activeCount: Int
        get() = requirements.count { it.requirement.status != RequirementStatus.COMPLETED }

    val criticalCount: Int
        get() = requirements.count { it.requirement.status == RequirementStatus.CRITICAL }

    val attentionCount: Int
        get() = requirements.count { it.requirement.status == RequirementStatus.ATTENTION }
}

/**
 * ViewModel for Monthly Planning screen.
 */
@HiltViewModel
class MonthlyPlanningViewModel @Inject constructor(
    private val monthlyPlanningService: MonthlyPlanningService,
    private val monthlyPlanRepository: MonthlyPlanRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(MonthlyPlanningUiState())
    val uiState: StateFlow<MonthlyPlanningUiState> = _uiState.asStateFlow()

    private val monthLabel: String = MonthLabelUtils.nowUtc()
    private var baseRequirements: List<MonthlyRequirement> = emptyList()
    private var plan: MonthlyPlan? = null

    init {
        loadData()
    }

    fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            try {
                val displayCurrency = "USD" // TODO: Get from user settings
                val currentPlan = monthlyPlanRepository.getOrCreatePlan(monthLabel)
                val requirements = monthlyPlanningService.calculateMonthlyRequirements()
                baseRequirements = requirements
                plan = currentPlan

                val rows = buildRows(requirements, currentPlan)
                val baseTotalRequired = calculateTotal(displayCurrency, requirements.map { it.currency to it.requiredMonthly })
                val totalRequired = calculateTotal(
                    displayCurrency,
                    rows.map { it.requirement.currency to it.adjustedRequiredMonthly }
                )
                val planWithTotals = currentPlan.copy(totalRequired = totalRequired)
                val paymentDay = monthlyPlanningService.paymentDay

                _uiState.update {
                    it.copy(
                        monthLabel = monthLabel,
                        requirements = rows,
                        baseTotalRequired = baseTotalRequired,
                        totalRequired = totalRequired,
                        displayCurrency = displayCurrency,
                        paymentDay = paymentDay,
                        flexPercentage = planWithTotals.flexPercentage,
                        isLoading = false
                    )
                }
                plan = planWithTotals
                monthlyPlanRepository.upsertPlan(planWithTotals)
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load monthly requirements"
                    )
                }
            }
        }
    }

    fun updateFlexPercentage(value: Double) {
        val existing = plan ?: return
        val clamped = value.coerceIn(0.0, 1.5)
        updatePlan(existing.copy(flexPercentage = clamped))
    }

    fun toggleProtected(goalId: String) {
        val existing = plan ?: return
        val current = existing.settings.perGoal[goalId] ?: MonthlyPlanGoalSettings()
        val updated = current.copy(isProtected = !current.isProtected, isSkipped = false)
        updateGoalSettings(goalId, updated)
    }

    fun toggleSkipped(goalId: String) {
        val existing = plan ?: return
        val current = existing.settings.perGoal[goalId] ?: MonthlyPlanGoalSettings()
        val updated = current.copy(isSkipped = !current.isSkipped, isProtected = false, customAmount = null)
        updateGoalSettings(goalId, updated)
    }

    fun setCustomAmount(goalId: String, amount: Double?) {
        val existing = plan ?: return
        val current = existing.settings.perGoal[goalId] ?: MonthlyPlanGoalSettings()
        val updated = current.copy(customAmount = amount, isSkipped = false)
        updateGoalSettings(goalId, updated)
    }

    fun showSettings() {
        _uiState.update { it.copy(showSettingsDialog = true) }
    }

    fun dismissSettings() {
        _uiState.update { it.copy(showSettingsDialog = false) }
    }

    fun updatePaymentDay(day: Int) {
        monthlyPlanningService.paymentDay = day
        _uiState.update { it.copy(paymentDay = day, showSettingsDialog = false) }
        loadData() // Recalculate with new payment day
    }

    private fun updateGoalSettings(goalId: String, settings: MonthlyPlanGoalSettings) {
        val existing = plan ?: return
        val updatedMap = existing.settings.perGoal.toMutableMap().apply {
            if (settings == MonthlyPlanGoalSettings()) {
                remove(goalId)
            } else {
                put(goalId, settings)
            }
        }.toMap()

        updatePlan(existing.copy(settings = MonthlyPlanSettings(perGoal = updatedMap)))
    }

    private fun updatePlan(updated: MonthlyPlan) {
        viewModelScope.launch {
            val rows = buildRows(baseRequirements, updated)
            val total = calculateTotal(
                _uiState.value.displayCurrency,
                rows.map { it.requirement.currency to it.adjustedRequiredMonthly }
            )
            val updatedWithTotals = updated.copy(totalRequired = total)
            plan = updatedWithTotals

            _uiState.update {
                it.copy(
                    requirements = rows,
                    totalRequired = total,
                    flexPercentage = updatedWithTotals.flexPercentage
                )
            }
            monthlyPlanRepository.upsertPlan(updatedWithTotals)
        }
    }

    private fun buildRows(
        requirements: List<MonthlyRequirement>,
        plan: MonthlyPlan
    ): List<MonthlyRequirementRow> {
        return requirements.map { requirement ->
            val settings = plan.settings.perGoal[requirement.goalId] ?: MonthlyPlanGoalSettings()
            val adjustedRequired = when {
                settings.isSkipped -> 0.0
                settings.customAmount != null -> settings.customAmount
                settings.isProtected -> requirement.requiredMonthly
                else -> requirement.requiredMonthly * plan.flexPercentage
            }
            MonthlyRequirementRow(
                requirement = requirement,
                adjustedRequiredMonthly = adjustedRequired,
                isProtected = settings.isProtected,
                isSkipped = settings.isSkipped,
                customAmount = settings.customAmount
            )
        }.sortedBy { it.requirement.goalName }
    }

    private suspend fun calculateTotal(displayCurrency: String, amounts: List<Pair<String, Double>>): Double {
        var total = 0.0
        for ((currency, amount) in amounts) {
            total += monthlyPlanningService.convertAmount(amount = amount, fromCurrency = currency, toCurrency = displayCurrency)
        }
        return total
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
