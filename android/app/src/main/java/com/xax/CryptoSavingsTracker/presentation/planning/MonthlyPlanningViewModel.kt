package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
import com.xax.CryptoSavingsTracker.domain.model.MonthlyRequirement
import com.xax.CryptoSavingsTracker.domain.model.PlanningMode
import com.xax.CryptoSavingsTracker.domain.model.RequirementStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlan
import com.xax.CryptoSavingsTracker.domain.usecase.execution.GetExecutionSessionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.planning.AdjustmentSimulation
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyGoalPlanService
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningService
import com.xax.CryptoSavingsTracker.domain.usecase.planning.RedistributionStrategy
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
    val planningMode: PlanningMode = PlanningMode.PER_GOAL,
    val monthLabel: String = "",
    val activeExecutionMonthLabel: String? = null,
    val activeExecutionStartedAtMillis: Long? = null,
    val requirements: List<MonthlyRequirementRow> = emptyList(),
    val baseTotalRequired: Double = 0.0,
    val totalRequired: Double = 0.0,
    val displayCurrency: String = "USD",
    val paymentDay: Int = 1,
    val flexAdjustment: Double = 1.0,
    val selectedStrategy: RedistributionStrategy = RedistributionStrategy.BALANCED,
    val simulationResult: AdjustmentSimulation? = null,
    val showStrategyPicker: Boolean = false,
    val isLoading: Boolean = true,
    val error: String? = null,
    val showSettingsDialog: Boolean = false,
    val hasSeenFixedBudgetIntro: Boolean = true
) {
    val completedCount: Int
        get() = requirements.count { it.requirement.status == RequirementStatus.COMPLETED }

    val activeCount: Int
        get() = requirements.count { it.requirement.status != RequirementStatus.COMPLETED }

    val criticalCount: Int
        get() = requirements.count { it.requirement.status == RequirementStatus.CRITICAL }

    val attentionCount: Int
        get() = requirements.count { it.requirement.status == RequirementStatus.ATTENTION }

    /** Number of high-risk goals from simulation */
    val highRiskCount: Int
        get() = simulationResult?.riskAnalysis?.count { it.value == com.xax.CryptoSavingsTracker.domain.usecase.planning.RiskLevel.HIGH } ?: 0

    /** Total months of delay estimated across all goals */
    val totalDelayMonths: Int
        get() = simulationResult?.delayEstimates?.values?.sum() ?: 0
}

/**
 * ViewModel for Monthly Planning screen.
 */
@HiltViewModel
class MonthlyPlanningViewModel @Inject constructor(
    private val monthlyPlanningService: MonthlyPlanningService,
    private val monthlyGoalPlanService: MonthlyGoalPlanService,
    private val getExecutionSessionUseCase: GetExecutionSessionUseCase,
    private val settings: MonthlyPlanningSettings
) : ViewModel() {

    private val _uiState = MutableStateFlow(MonthlyPlanningUiState())
    val uiState: StateFlow<MonthlyPlanningUiState> = _uiState.asStateFlow()

    private val monthLabel: String = MonthLabelUtils.nowUtc()
    private var baseRequirements: List<MonthlyRequirement> = emptyList()
    private var plansByGoalId: Map<String, MonthlyGoalPlan> = emptyMap()

    init {
        loadPlanningMode()
        loadIntroState()
        observeActiveExecution()
        loadData()
    }

    private fun loadPlanningMode() {
        _uiState.update { it.copy(planningMode = settings.planningMode) }
    }

    private fun loadIntroState() {
        _uiState.update { it.copy(hasSeenFixedBudgetIntro = settings.hasSeenFixedBudgetIntro) }
    }

    fun dismissFixedBudgetIntro() {
        settings.hasSeenFixedBudgetIntro = true
        _uiState.update { it.copy(hasSeenFixedBudgetIntro = true) }
    }

    fun tryFixedBudgetMode() {
        settings.hasSeenFixedBudgetIntro = true
        settings.planningMode = PlanningMode.FIXED_BUDGET
        _uiState.update {
            it.copy(
                hasSeenFixedBudgetIntro = true,
                planningMode = PlanningMode.FIXED_BUDGET
            )
        }
    }

    fun setPlanningMode(mode: PlanningMode) {
        settings.planningMode = mode
        _uiState.update { it.copy(planningMode = mode) }
    }

    private fun observeActiveExecution() {
        viewModelScope.launch {
            getExecutionSessionUseCase.currentExecuting().collect { session ->
                _uiState.update {
                    it.copy(
                        activeExecutionMonthLabel = session?.record?.monthLabel,
                        activeExecutionStartedAtMillis = session?.record?.startedAtMillis
                    )
                }
            }
        }
    }

    fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            try {
                val displayCurrency = monthlyPlanningService.displayCurrency
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
            val strategy = _uiState.value.selectedStrategy
            monthlyPlanningService.flexAdjustment = clamped
            val updatedPlans = monthlyGoalPlanService.applyFlexAdjustment(
                monthLabel = monthLabel,
                adjustment = clamped,
                strategy = strategy,
                requirements = baseRequirements
            )
            plansByGoalId = updatedPlans.associateBy { it.goalId }

            // Run simulation to get impact analysis
            val simulation = monthlyGoalPlanService.simulateFlexAdjustment(
                monthLabel = monthLabel,
                adjustment = clamped,
                strategy = strategy,
                requirements = baseRequirements
            )
            _uiState.update { it.copy(simulationResult = simulation) }
            refreshRows()
        }
    }

    fun updateStrategy(strategy: RedistributionStrategy) {
        viewModelScope.launch {
            _uiState.update { it.copy(selectedStrategy = strategy, showStrategyPicker = false) }
            // Reapply flex adjustment with new strategy
            val adjustment = _uiState.value.flexAdjustment
            if (adjustment != 1.0) {
                val updatedPlans = monthlyGoalPlanService.applyFlexAdjustment(
                    monthLabel = monthLabel,
                    adjustment = adjustment,
                    strategy = strategy,
                    requirements = baseRequirements
                )
                plansByGoalId = updatedPlans.associateBy { it.goalId }

                val simulation = monthlyGoalPlanService.simulateFlexAdjustment(
                    monthLabel = monthLabel,
                    adjustment = adjustment,
                    strategy = strategy,
                    requirements = baseRequirements
                )
                _uiState.update { it.copy(simulationResult = simulation) }
                refreshRows()
            }
        }
    }

    fun showStrategyPicker() {
        _uiState.update { it.copy(showStrategyPicker = true) }
    }

    fun dismissStrategyPicker() {
        _uiState.update { it.copy(showStrategyPicker = false) }
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
        updatePlanningSettings(day = day, displayCurrency = _uiState.value.displayCurrency)
    }

    fun updatePlanningSettings(day: Int, displayCurrency: String) {
        val normalizedCurrency = displayCurrency.trim().uppercase().ifBlank { "USD" }
        monthlyPlanningService.paymentDay = day
        monthlyPlanningService.displayCurrency = normalizedCurrency
        _uiState.update {
            it.copy(
                paymentDay = day,
                displayCurrency = normalizedCurrency,
                showSettingsDialog = false
            )
        }
        loadData()
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
