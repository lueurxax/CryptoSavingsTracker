package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.MonthlyRequirement
import com.xax.CryptoSavingsTracker.domain.model.RequirementStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlan
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyGoalPlanService
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
    val flexAdjustment: Double = 1.0,
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
    private val monthlyGoalPlanService: MonthlyGoalPlanService
) : ViewModel() {

    private val _uiState = MutableStateFlow(MonthlyPlanningUiState())
    val uiState: StateFlow<MonthlyPlanningUiState> = _uiState.asStateFlow()

    private val monthLabel: String = MonthLabelUtils.nowUtc()
    private var baseRequirements: List<MonthlyRequirement> = emptyList()
    private var plansByGoalId: Map<String, MonthlyGoalPlan> = emptyMap()

    init {
        loadData()
    }

    fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            try {
                val displayCurrency = "USD" // TODO: Get from user settings
                val requirements = monthlyPlanningService.calculateMonthlyRequirements()
                baseRequirements = requirements

                val syncedPlans = monthlyGoalPlanService.syncPlans(monthLabel, requirements)
                plansByGoalId = syncedPlans.associateBy { it.goalId }

                val rows = buildRows(requirements, syncedPlans.associateBy { it.goalId })
                val baseTotalRequired = calculateTotal(displayCurrency, requirements.map { it.currency to it.requiredMonthly })
                val totalRequired = calculateTotal(
                    displayCurrency,
                    rows.map { it.requirement.currency to it.adjustedRequiredMonthly }
                )
                val paymentDay = monthlyPlanningService.paymentDay

                _uiState.update {
                    it.copy(
                        monthLabel = monthLabel,
                        requirements = rows,
                        baseTotalRequired = baseTotalRequired,
                        totalRequired = totalRequired,
                        displayCurrency = displayCurrency,
                        paymentDay = paymentDay,
                        flexAdjustment = monthlyPlanningService.flexAdjustment,
                        isLoading = false
                    )
                }
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

    fun updateFlexAdjustment(value: Double) {
        viewModelScope.launch {
            val clamped = value.coerceIn(0.0, 1.5)
            monthlyPlanningService.flexAdjustment = clamped
            val updatedPlans = monthlyGoalPlanService.applyFlexAdjustment(monthLabel, clamped)
            plansByGoalId = updatedPlans.associateBy { it.goalId }
            refreshRows()
        }
    }

    fun toggleProtected(goalId: String) {
        viewModelScope.launch {
            val updated = monthlyGoalPlanService.toggleProtected(monthLabel, goalId)
            plansByGoalId = plansByGoalId.toMutableMap().apply { put(goalId, updated) }
            refreshRows()
        }
    }

    fun toggleSkipped(goalId: String) {
        viewModelScope.launch {
            val updated = monthlyGoalPlanService.toggleSkipped(monthLabel, goalId)
            plansByGoalId = plansByGoalId.toMutableMap().apply { put(goalId, updated) }
            refreshRows()
        }
    }

    fun setCustomAmount(goalId: String, amount: Double?) {
        viewModelScope.launch {
            val updated = monthlyGoalPlanService.setCustomAmount(monthLabel, goalId, amount)
            plansByGoalId = plansByGoalId.toMutableMap().apply { put(goalId, updated) }
            refreshRows()
        }
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

    private suspend fun refreshRows() {
        val rows = buildRows(baseRequirements, plansByGoalId)
        val total = calculateTotal(
            _uiState.value.displayCurrency,
            rows.map { it.requirement.currency to it.adjustedRequiredMonthly }
        )
        _uiState.update {
            it.copy(
                requirements = rows,
                totalRequired = total,
                flexAdjustment = monthlyPlanningService.flexAdjustment
            )
        }
    }

    private fun buildRows(
        requirements: List<MonthlyRequirement>,
        plansByGoalId: Map<String, MonthlyGoalPlan>
    ): List<MonthlyRequirementRow> {
        return requirements.map { requirement ->
            val plan = plansByGoalId[requirement.goalId]
            val adjustedRequired = plan?.effectiveAmount ?: requirement.requiredMonthly
            MonthlyRequirementRow(
                requirement = requirement,
                adjustedRequiredMonthly = adjustedRequired,
                isProtected = plan?.isProtected == true,
                isSkipped = plan?.isSkipped == true,
                customAmount = plan?.customAmount
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
