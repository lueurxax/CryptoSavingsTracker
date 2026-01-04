package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.BudgetCalculatorPlan
import com.xax.CryptoSavingsTracker.domain.model.FeasibilityResult
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
import com.xax.CryptoSavingsTracker.domain.model.MonthlyRequirement
import com.xax.CryptoSavingsTracker.domain.model.RequirementStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyGoalPlan
import com.xax.CryptoSavingsTracker.domain.model.ScheduledGoalBlock
import com.xax.CryptoSavingsTracker.domain.usecase.execution.GetExecutionSessionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.planning.AdjustmentSimulation
import com.xax.CryptoSavingsTracker.domain.usecase.planning.BudgetCalculatorUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyGoalPlanService
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningService
import com.xax.CryptoSavingsTracker.domain.usecase.planning.RedistributionStrategy
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.util.MonthLabelUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject
import java.time.LocalDate

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
    val budgetAmount: Double? = null,
    val budgetCurrency: String = "USD",
    val budgetFeasibility: FeasibilityResult = FeasibilityResult.EMPTY,
    val budgetPreviewPlan: BudgetCalculatorPlan? = null,
    val budgetPreviewTimeline: List<ScheduledGoalBlock> = emptyList(),
    val isBudgetPreviewLoading: Boolean = false,
    val budgetPreviewError: String? = null,
    val budgetFocusGoalName: String? = null,
    val budgetFocusGoalDeadline: LocalDate? = null,
    val showBudgetSheet: Boolean = false,
    val showBudgetMigrationNotice: Boolean = false,
    val showBudgetRecalculationPrompt: Boolean = false,
    val isBudgetAppliedForMonth: Boolean = false,
    val budgetMinimum: Double? = null,
    val isBudgetMinimumLoading: Boolean = false,
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
    private val settings: MonthlyPlanningSettings,
    private val budgetCalculatorUseCase: BudgetCalculatorUseCase,
    private val goalRepository: GoalRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(MonthlyPlanningUiState())
    val uiState: StateFlow<MonthlyPlanningUiState> = _uiState.asStateFlow()

    private val monthLabel: String = MonthLabelUtils.nowUtc()
    private var baseRequirements: List<MonthlyRequirement> = emptyList()
    private var plansByGoalId: Map<String, MonthlyGoalPlan> = emptyMap()
    private var activeGoals: List<Goal> = emptyList()
    private var isApplyingBudgetMigration = false

    init {
        observeActiveExecution()
        loadData()
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
            loadDataInternal()
        }
    }

    private suspend fun loadDataInternal() {
        _uiState.update { it.copy(isLoading = true, error = null) }

        try {
            val displayCurrency = monthlyPlanningService.displayCurrency
            val requirements = monthlyPlanningService.calculateMonthlyRequirements()
            baseRequirements = requirements
            activeGoals = goalRepository.getAllGoals().first()
                .filter { it.lifecycleStatus == com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus.ACTIVE }

            val syncedPlans = monthlyGoalPlanService.syncPlans(monthLabel, requirements)
            plansByGoalId = syncedPlans.associateBy { it.goalId }

            val rows = buildRows(requirements, syncedPlans.associateBy { it.goalId })
            val baseTotalRequired = calculateTotal(displayCurrency, requirements.map { it.currency to it.requiredMonthly })
            val totalRequired = calculateTotal(
                displayCurrency,
                rows.map { it.requirement.currency to it.adjustedRequiredMonthly }
            )
            val paymentDay = monthlyPlanningService.paymentDay
            val skippedIds = syncedPlans.filter { it.isSkipped }.map { it.goalId }.toSet()
            val eligibleGoals = activeGoals.filter { !skippedIds.contains(it.id) }
            val budgetAmount = settings.monthlyBudget
            val budgetCurrency = settings.budgetCurrency
            val feasibility = if (budgetAmount != null && budgetAmount > 0 && eligibleGoals.isNotEmpty()) {
                budgetCalculatorUseCase.checkFeasibility(eligibleGoals, budgetAmount, budgetCurrency)
            } else {
                FeasibilityResult.EMPTY
            }
            val budgetSignature = if (eligibleGoals.isNotEmpty()) buildBudgetSignature(eligibleGoals) else ""
            val shouldPromptBudget = budgetAmount != null &&
                settings.budgetAppliedMonthLabel != null &&
                (settings.budgetAppliedMonthLabel != monthLabel ||
                    settings.budgetAppliedSignature != budgetSignature)
            val goalById = activeGoals.associateBy { it.id }
            val focusGoal = if (budgetAmount != null && budgetAmount > 0) {
                syncedPlans
                    .filter { !it.isSkipped && (it.customAmount ?: 0.0) > 0.01 }
                    .mapNotNull { plan -> goalById[plan.goalId] }
                    .minByOrNull { it.deadline }
            } else {
                null
            }

            _uiState.update {
                it.copy(
                    monthLabel = monthLabel,
                    requirements = rows,
                    baseTotalRequired = baseTotalRequired,
                    totalRequired = totalRequired,
                    displayCurrency = displayCurrency,
                    paymentDay = paymentDay,
                    flexAdjustment = monthlyPlanningService.flexAdjustment,
                    budgetAmount = budgetAmount,
                    budgetCurrency = budgetCurrency,
                    budgetFeasibility = feasibility,
                    showBudgetRecalculationPrompt = shouldPromptBudget,
                    isBudgetAppliedForMonth = budgetAmount != null && settings.budgetAppliedMonthLabel == monthLabel,
                    budgetFocusGoalName = focusGoal?.name,
                    budgetFocusGoalDeadline = focusGoal?.deadline,
                    isLoading = false
                )
            }

            handleBudgetMigrationIfNeeded(budgetAmount, budgetCurrency, eligibleGoals)
        } catch (e: Exception) {
            _uiState.update {
                it.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load monthly requirements"
                )
            }
        }
    }

    fun showBudgetSheet() {
        _uiState.update { it.copy(showBudgetSheet = true) }
    }

    fun dismissBudgetSheet() {
        _uiState.update { it.copy(showBudgetSheet = false) }
    }

    fun dismissBudgetMigrationNotice() {
        settings.hasSeenBudgetMigrationNotice = true
        _uiState.update { it.copy(showBudgetMigrationNotice = false) }
    }

    fun acknowledgeBudgetRecalculationPrompt() {
        val signature = buildBudgetSignature(activeGoals)
        settings.budgetAppliedMonthLabel = monthLabel
        settings.budgetAppliedSignature = signature
        _uiState.update { it.copy(showBudgetRecalculationPrompt = false) }
    }

    fun previewBudget(amount: Double, currency: String) {
        viewModelScope.launch {
            if (amount <= 0 || activeGoals.isEmpty()) {
                _uiState.update {
                    it.copy(
                        budgetPreviewPlan = null,
                        budgetPreviewTimeline = emptyList(),
                        budgetPreviewError = null,
                        budgetFeasibility = FeasibilityResult.EMPTY,
                        isBudgetPreviewLoading = false
                    )
                }
                return@launch
            }

            _uiState.update { it.copy(isBudgetPreviewLoading = true, budgetPreviewError = null) }
            val eligibleGoals = activeGoals.filter { goal ->
                val plan = plansByGoalId[goal.id]
                plan?.isSkipped != true
            }
            val feasibility = budgetCalculatorUseCase.checkFeasibility(eligibleGoals, amount, currency)
            val plan = budgetCalculatorUseCase.generateSchedule(eligibleGoals, amount, currency)
            val timeline = budgetCalculatorUseCase.buildTimelineBlocks(plan, eligibleGoals)

            _uiState.update {
                it.copy(
                    budgetFeasibility = feasibility,
                    budgetPreviewPlan = plan,
                    budgetPreviewTimeline = timeline,
                    isBudgetPreviewLoading = false
                )
            }
        }
    }

    fun applyBudgetPlan(amount: Double, currency: String) {
        viewModelScope.launch {
            if (amount <= 0 || activeGoals.isEmpty()) return@launch
            val eligibleGoals = activeGoals.filter { goal ->
                val plan = plansByGoalId[goal.id]
                plan?.isSkipped != true
            }
            val plan = budgetCalculatorUseCase.generateSchedule(eligibleGoals, amount, currency)
            val applied = applyBudgetPlanInternal(amount, currency, plan)
            if (applied) {
                dismissBudgetSheet()
            }
        }
    }

    fun applyBudgetSuggestion(
        suggestion: com.xax.CryptoSavingsTracker.domain.model.FeasibilitySuggestion,
        currentBudget: Double,
        currency: String
    ) {
        viewModelScope.launch {
            when (suggestion) {
                is com.xax.CryptoSavingsTracker.domain.model.FeasibilitySuggestion.IncreaseBudget -> return@launch
                is com.xax.CryptoSavingsTracker.domain.model.FeasibilitySuggestion.ExtendDeadline -> {
                    val goal = goalRepository.getGoalById(suggestion.goalId) ?: return@launch
                    val updated = goal.copy(deadline = goal.deadline.plusMonths(suggestion.byMonths.toLong()))
                    goalRepository.updateGoal(updated)
                }
                is com.xax.CryptoSavingsTracker.domain.model.FeasibilitySuggestion.ReduceTarget -> {
                    val goal = goalRepository.getGoalById(suggestion.goalId) ?: return@launch
                    val updated = goal.copy(targetAmount = suggestion.to)
                    goalRepository.updateGoal(updated)
                }
                is com.xax.CryptoSavingsTracker.domain.model.FeasibilitySuggestion.EditGoal -> return@launch
            }

            loadDataInternal()
            if (currentBudget > 0) {
                previewBudget(currentBudget, currency)
            }
        }
    }

    fun updateFlexAdjustment(value: Double) {
        viewModelScope.launch {
            val clamped = value.coerceIn(0.0, 1.5)
            val strategy = _uiState.value.selectedStrategy
            val usePlanBaseline = settings.budgetAppliedMonthLabel == monthLabel && settings.monthlyBudget != null
            val flexRequirements = if (usePlanBaseline) null else baseRequirements
            monthlyPlanningService.flexAdjustment = clamped
            val updatedPlans = monthlyGoalPlanService.applyFlexAdjustment(
                monthLabel = monthLabel,
                adjustment = clamped,
                strategy = strategy,
                requirements = flexRequirements
            )
            plansByGoalId = updatedPlans.associateBy { it.goalId }

            // Run simulation to get impact analysis
            val simulation = monthlyGoalPlanService.simulateFlexAdjustment(
                monthLabel = monthLabel,
                adjustment = clamped,
                strategy = strategy,
                requirements = flexRequirements ?: baseRequirements
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
                val usePlanBaseline = settings.budgetAppliedMonthLabel == monthLabel && settings.monthlyBudget != null
                val flexRequirements = if (usePlanBaseline) null else baseRequirements
                val updatedPlans = monthlyGoalPlanService.applyFlexAdjustment(
                    monthLabel = monthLabel,
                    adjustment = adjustment,
                    strategy = strategy,
                    requirements = flexRequirements
                )
                plansByGoalId = updatedPlans.associateBy { it.goalId }

                val simulation = monthlyGoalPlanService.simulateFlexAdjustment(
                    monthLabel = monthLabel,
                    adjustment = adjustment,
                    strategy = strategy,
                    requirements = flexRequirements ?: baseRequirements
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
        loadBudgetMinimum(settings.budgetCurrency)
    }

    fun dismissSettings() {
        _uiState.update { it.copy(showSettingsDialog = false) }
    }

    fun loadBudgetMinimum(currency: String) {
        viewModelScope.launch {
            val eligibleGoals = activeGoals.filter { goal ->
                plansByGoalId[goal.id]?.isSkipped != true
            }
            if (eligibleGoals.isEmpty()) {
                _uiState.update { it.copy(budgetMinimum = null, isBudgetMinimumLoading = false) }
                return@launch
            }
            _uiState.update { it.copy(isBudgetMinimumLoading = true) }
            val minimum = budgetCalculatorUseCase.calculateMinimumBudget(eligibleGoals, currency)
            _uiState.update {
                it.copy(
                    budgetMinimum = if (minimum > 0) minimum else null,
                    isBudgetMinimumLoading = false
                )
            }
        }
    }

    fun updatePaymentDay(day: Int) {
        updatePlanningSettings(
            day = day,
            displayCurrency = _uiState.value.displayCurrency,
            budgetAmount = settings.monthlyBudget,
            budgetCurrency = settings.budgetCurrency
        )
    }

    fun updatePlanningSettings(
        day: Int,
        displayCurrency: String,
        budgetAmount: Double?,
        budgetCurrency: String
    ) {
        val normalizedCurrency = displayCurrency.trim().uppercase().ifBlank { "USD" }
        val normalizedBudgetCurrency = budgetCurrency.trim().uppercase().ifBlank { "USD" }
        monthlyPlanningService.paymentDay = day
        monthlyPlanningService.displayCurrency = normalizedCurrency
        settings.monthlyBudget = budgetAmount
        settings.budgetCurrency = normalizedBudgetCurrency
        _uiState.update {
            it.copy(
                paymentDay = day,
                displayCurrency = normalizedCurrency,
                budgetAmount = budgetAmount,
                budgetCurrency = normalizedBudgetCurrency,
                showSettingsDialog = false
            )
        }
        loadData()
    }

    private suspend fun handleBudgetMigrationIfNeeded(
        budgetAmount: Double?,
        budgetCurrency: String,
        eligibleGoals: List<Goal>
    ) {
        if (budgetAmount == null || budgetAmount <= 0) return
        if (settings.budgetAppliedMonthLabel != null) return
        if (eligibleGoals.isEmpty()) return
        if (isApplyingBudgetMigration) return

        isApplyingBudgetMigration = true
        val plan = budgetCalculatorUseCase.generateSchedule(eligibleGoals, budgetAmount, budgetCurrency)
        val applied = applyBudgetPlanInternal(budgetAmount, budgetCurrency, plan)
        if (applied && !settings.hasSeenBudgetMigrationNotice) {
            _uiState.update { it.copy(showBudgetMigrationNotice = true) }
        }
        isApplyingBudgetMigration = false
    }

    private suspend fun applyBudgetPlanInternal(
        amount: Double,
        currency: String,
        plan: BudgetCalculatorPlan
    ): Boolean {
        if (plansByGoalId.isEmpty()) return false

        val contributionMap = plan.schedule.firstOrNull()?.contributions
            ?.associate { it.goalId to it.amount }
            ?: emptyMap()

        val customAmounts = mutableMapOf<String, Double>()
        for (planItem in plansByGoalId.values) {
            if (planItem.isSkipped) continue
            val plannedAmount = contributionMap[planItem.goalId] ?: 0.0
            val converted = if (plannedAmount <= 0.0) {
                0.0
            } else {
                monthlyPlanningService.convertAmount(
                    amount = plannedAmount,
                    fromCurrency = currency,
                    toCurrency = planItem.currency
                )
            }
            customAmounts[planItem.goalId] = converted
        }

        val updatedPlans = monthlyGoalPlanService.applyCustomAmounts(monthLabel, customAmounts)
        plansByGoalId = updatedPlans.associateBy { it.goalId }

        val goalById = activeGoals.associateBy { it.id }
        val focusGoalName = updatedPlans
            .filter { !it.isSkipped && (it.customAmount ?: 0.0) > 0.01 }
            .mapNotNull { plan -> goalById[plan.goalId] }
            .minByOrNull { it.deadline }
            ?.name

        settings.monthlyBudget = amount
        settings.budgetCurrency = currency
        settings.budgetAppliedMonthLabel = monthLabel
        settings.budgetAppliedSignature = buildBudgetSignature(activeGoals)
        monthlyPlanningService.flexAdjustment = 1.0

        _uiState.update {
            it.copy(
                budgetAmount = amount,
                budgetCurrency = currency,
                isBudgetAppliedForMonth = true,
                budgetFocusGoalName = focusGoalName
            )
        }
        refreshRows()
        return true
    }

    private fun buildBudgetSignature(goals: List<Goal>): String {
        return goals
            .sortedBy { it.id }
            .joinToString(separator = ";") { goal ->
                "${goal.id}|${goal.currency}|${goal.targetAmount}|${goal.deadline}"
            }
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
