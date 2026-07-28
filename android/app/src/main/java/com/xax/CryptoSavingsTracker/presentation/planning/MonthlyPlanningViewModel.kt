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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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
    val baseTotalRequired: Double? = null,
    val totalRequired: Double? = null,
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
    val budgetMinimumError: String? = null,
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
    private val planningMutationMutex = Mutex()
    private var loadDataJob: Job? = null
    private var loadDataGeneration: Long = 0L
    private var budgetPreviewJob: Job? = null
    private var budgetPreviewGeneration: Long = 0
    private var budgetMinimumJob: Job? = null
    private var budgetMinimumGeneration: Long = 0
    private var latestBudgetMinimumCurrency: String? = null

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
        startLoadData()
    }

    private fun startLoadData(): Job {
        val generation = ++loadDataGeneration
        loadDataJob?.cancel()
        return viewModelScope.launch {
            loadDataInternal(generation)
        }.also { job ->
            loadDataJob = job
        }
    }

    private fun launchPlanMutation(block: suspend () -> Unit) {
        loadDataGeneration += 1
        loadDataJob?.cancel()
        loadDataJob = null
        _uiState.update { it.copy(isLoading = false) }
        viewModelScope.launch {
            planningMutationMutex.withLock {
                block()
            }
        }
    }

    private suspend fun loadDataInternal(generation: Long) {
        if (generation != loadDataGeneration) return
        _uiState.update {
            it.copy(
                isLoading = true,
                baseTotalRequired = null,
                totalRequired = null,
                error = null
            )
        }

        try {
            val displayCurrency = monthlyPlanningService.displayCurrency
            val paymentDay = monthlyPlanningService.paymentDay
            val flexAdjustment = monthlyPlanningService.flexAdjustment
            val budgetAmount = settings.monthlyBudget
            val budgetCurrency = settings.budgetCurrency
            val budgetAppliedMonthLabel = settings.budgetAppliedMonthLabel
            val budgetAppliedSignature = settings.budgetAppliedSignature
            val requirements = monthlyPlanningService.calculateMonthlyRequirements()
            if (generation != loadDataGeneration) return
            val loadedActiveGoals = goalRepository.getAllGoals().first()
                .filter { it.lifecycleStatus == com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus.ACTIVE }
            if (generation != loadDataGeneration) return

            val syncedPlans = planningMutationMutex.withLock {
                if (generation != loadDataGeneration) {
                    throw CancellationException("Monthly planning load was superseded")
                }
                monthlyGoalPlanService.syncPlans(monthLabel, requirements)
            }
            if (generation != loadDataGeneration) return

            val rows = buildRows(requirements, syncedPlans.associateBy { it.goalId })
            val baseTotalRequired = calculateTotal(displayCurrency, requirements.map { it.currency to it.requiredMonthly })
            if (generation != loadDataGeneration) return
            val totalRequired = calculateTotal(
                displayCurrency,
                rows.map { it.requirement.currency to it.adjustedRequiredMonthly }
            )
            if (generation != loadDataGeneration) return
            val skippedIds = syncedPlans.filter { it.isSkipped }.map { it.goalId }.toSet()
            val eligibleGoals = loadedActiveGoals.filter { !skippedIds.contains(it.id) }
            val feasibility = if (budgetAmount != null && budgetAmount > 0 && eligibleGoals.isNotEmpty()) {
                budgetCalculatorUseCase.checkFeasibility(eligibleGoals, budgetAmount, budgetCurrency)
            } else {
                FeasibilityResult.EMPTY
            }
            if (generation != loadDataGeneration) return
            val budgetSignature = if (eligibleGoals.isNotEmpty()) buildBudgetSignature(eligibleGoals) else ""
            val shouldPromptBudget = budgetAmount != null &&
                budgetAppliedMonthLabel != null &&
                (budgetAppliedMonthLabel != monthLabel ||
                    budgetAppliedSignature != budgetSignature)
            val goalById = loadedActiveGoals.associateBy { it.id }
            val focusGoal = if (budgetAmount != null && budgetAmount > 0) {
                syncedPlans
                    .filter { !it.isSkipped && (it.customAmount ?: 0.0) > 0.01 }
                    .mapNotNull { plan -> goalById[plan.goalId] }
                    .minByOrNull { it.deadline }
            } else {
                null
            }

            if (generation != loadDataGeneration) return
            baseRequirements = requirements
            activeGoals = loadedActiveGoals
            plansByGoalId = syncedPlans.associateBy { it.goalId }
            _uiState.update {
                it.copy(
                    monthLabel = monthLabel,
                    requirements = rows,
                    baseTotalRequired = baseTotalRequired,
                    totalRequired = totalRequired,
                    displayCurrency = displayCurrency,
                    paymentDay = paymentDay,
                    flexAdjustment = flexAdjustment,
                    budgetAmount = budgetAmount,
                    budgetCurrency = budgetCurrency,
                    budgetFeasibility = feasibility,
                    showBudgetRecalculationPrompt = shouldPromptBudget,
                    isBudgetAppliedForMonth = budgetAmount != null && budgetAppliedMonthLabel == monthLabel,
                    budgetFocusGoalName = focusGoal?.name,
                    budgetFocusGoalDeadline = focusGoal?.deadline,
                    isLoading = false
                )
            }

            if (generation == loadDataGeneration) {
                handleBudgetMigrationIfNeeded(
                    generation = generation,
                    budgetAmount = budgetAmount,
                    budgetCurrency = budgetCurrency,
                    budgetAppliedMonthLabel = budgetAppliedMonthLabel,
                    eligibleGoals = eligibleGoals,
                    sourcePlansByGoalId = syncedPlans.associateBy { it.goalId },
                    sourceGoals = loadedActiveGoals
                )
            }
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (e: Exception) {
            if (generation != loadDataGeneration) return
            _uiState.update {
                it.copy(
                    isLoading = false,
                    baseTotalRequired = null,
                    totalRequired = null,
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
        val requestGeneration = ++budgetPreviewGeneration
        budgetPreviewJob?.cancel()

        if (!amount.isFinite() || amount <= 0 || activeGoals.isEmpty()) {
            budgetPreviewJob = null
            _uiState.update {
                it.copy(
                    budgetPreviewPlan = null,
                    budgetPreviewTimeline = emptyList(),
                    budgetPreviewError = null,
                    budgetFeasibility = FeasibilityResult.EMPTY,
                    isBudgetPreviewLoading = false
                )
            }
            return
        }

        _uiState.update { it.copy(isBudgetPreviewLoading = true, budgetPreviewError = null) }
        budgetPreviewJob = viewModelScope.launch {
            try {
                val eligibleGoals = activeGoals.filter { goal ->
                    val plan = plansByGoalId[goal.id]
                    plan?.isSkipped != true
                }
                val feasibility = budgetCalculatorUseCase.checkFeasibility(
                    eligibleGoals,
                    amount,
                    currency
                )
                val plan = budgetCalculatorUseCase.generateSchedule(
                    eligibleGoals,
                    amount,
                    currency
                )
                val timeline = budgetCalculatorUseCase.buildTimelineBlocks(plan, eligibleGoals)
                if (requestGeneration != budgetPreviewGeneration) return@launch
                _uiState.update {
                    it.copy(
                        budgetFeasibility = feasibility,
                        budgetPreviewPlan = plan,
                        budgetPreviewTimeline = timeline,
                        isBudgetPreviewLoading = false,
                        budgetPreviewError = null
                    )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (requestGeneration != budgetPreviewGeneration) return@launch
                _uiState.update {
                    it.copy(
                        budgetFeasibility = FeasibilityResult.EMPTY,
                        budgetPreviewPlan = null,
                        budgetPreviewTimeline = emptyList(),
                        isBudgetPreviewLoading = false,
                        budgetPreviewError = error.message
                            ?: "Budget preview is unavailable. Refresh rates and retry."
                    )
                }
            }
        }
    }

    fun applyBudgetPlan(amount: Double, currency: String) {
        if (!amount.isPersistablePositiveFloat() || activeGoals.isEmpty()) {
            _uiState.update { it.copy(error = "Budget amount is invalid or too large") }
            return
        }
        launchPlanMutation {
            runCatching {
                val eligibleGoals = activeGoals.filter { goal ->
                    val plan = plansByGoalId[goal.id]
                    plan?.isSkipped != true
                }
                val feasibility = budgetCalculatorUseCase.checkFeasibility(
                    eligibleGoals,
                    amount,
                    currency
                )
                _uiState.update { it.copy(budgetFeasibility = feasibility) }
                if (!feasibility.isFeasible) {
                    _uiState.update {
                        it.copy(
                            error = "Budget is no longer feasible. Increase it or adjust goal deadlines."
                        )
                    }
                    return@runCatching false
                }
                val plan = budgetCalculatorUseCase.generateSchedule(eligibleGoals, amount, currency)
                applyBudgetPlanLocked(amount, currency, plan)
            }.onSuccess { applied ->
                if (applied) {
                    dismissBudgetSheet()
                }
            }.onFailure { error ->
                _uiState.update {
                    it.copy(
                        error = error.message
                            ?: "Unable to convert the budget. Refresh rates and retry."
                    )
                }
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

            val replacementLoad = startLoadData()
            replacementLoad.join()
            if (replacementLoad === loadDataJob && currentBudget > 0) {
                previewBudget(currentBudget, currency)
            }
        }
    }

    fun updateFlexAdjustment(value: Double) {
        if (!value.isFinite()) {
            _uiState.update { it.copy(error = "Flex adjustment must be finite") }
            return
        }
        launchPlanMutation {
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
        launchPlanMutation {
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
        launchPlanMutation {
            val updated = monthlyGoalPlanService.toggleProtected(monthLabel, goalId)
            plansByGoalId = plansByGoalId.toMutableMap().apply { put(goalId, updated) }
            refreshRows()
        }
    }

    fun toggleSkipped(goalId: String) {
        launchPlanMutation {
            val updated = monthlyGoalPlanService.toggleSkipped(monthLabel, goalId)
            plansByGoalId = plansByGoalId.toMutableMap().apply { put(goalId, updated) }
            refreshRows()
        }
    }

    fun setCustomAmount(goalId: String, amount: Double?) {
        if (amount != null && (!amount.isFinite() || amount < 0.0)) {
            _uiState.update { it.copy(error = "Custom amount must be finite and non-negative") }
            return
        }
        launchPlanMutation {
            runCatching {
                monthlyGoalPlanService.setCustomAmount(monthLabel, goalId, amount)
            }.onSuccess { updated ->
                plansByGoalId = plansByGoalId.toMutableMap().apply { put(goalId, updated) }
                refreshRows()
            }.onFailure { error ->
                _uiState.update {
                    it.copy(error = error.message ?: "Unable to save custom amount")
                }
            }
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
        val normalizedCurrency = currency.trim().uppercase().ifBlank { "USD" }
        val requestGeneration = ++budgetMinimumGeneration
        latestBudgetMinimumCurrency = normalizedCurrency
        budgetMinimumJob?.cancel()
        budgetMinimumJob = viewModelScope.launch {
            val eligibleGoals = activeGoals.filter { goal ->
                plansByGoalId[goal.id]?.isSkipped != true
            }
            if (eligibleGoals.isEmpty()) {
                if (
                    requestGeneration != budgetMinimumGeneration ||
                    normalizedCurrency != latestBudgetMinimumCurrency
                ) {
                    return@launch
                }
                _uiState.update {
                    it.copy(
                        budgetMinimum = null,
                        isBudgetMinimumLoading = false,
                        budgetMinimumError = null
                    )
                }
                return@launch
            }
            _uiState.update {
                it.copy(
                    budgetMinimum = null,
                    isBudgetMinimumLoading = true,
                    budgetMinimumError = null
                )
            }
            runCatching {
                budgetCalculatorUseCase.calculateMinimumBudget(eligibleGoals, normalizedCurrency)
                    .also { minimum ->
                        check(minimum.isFinite() && minimum >= 0.0) {
                            "Calculated minimum is invalid"
                        }
                    }
            }.onSuccess { minimum ->
                if (
                    requestGeneration != budgetMinimumGeneration ||
                    normalizedCurrency != latestBudgetMinimumCurrency
                ) {
                    return@onSuccess
                }
                _uiState.update {
                    it.copy(
                        budgetMinimum = if (minimum > 0) minimum else null,
                        isBudgetMinimumLoading = false,
                        budgetMinimumError = null
                    )
                }
            }.onFailure { error ->
                if (
                    requestGeneration != budgetMinimumGeneration ||
                    normalizedCurrency != latestBudgetMinimumCurrency
                ) {
                    return@onFailure
                }
                _uiState.update {
                    it.copy(
                        budgetMinimum = null,
                        isBudgetMinimumLoading = false,
                        budgetMinimumError = error.message
                            ?: "Calculated minimum is unavailable. Refresh rates and retry."
                    )
                }
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
        if (budgetAmount != null && !budgetAmount.isPersistablePositiveFloat()) {
            _uiState.update { it.copy(error = "Monthly budget is invalid or too large") }
            return
        }
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
        generation: Long,
        budgetAmount: Double?,
        budgetCurrency: String,
        budgetAppliedMonthLabel: String?,
        eligibleGoals: List<Goal>,
        sourcePlansByGoalId: Map<String, MonthlyGoalPlan>,
        sourceGoals: List<Goal>
    ) {
        if (budgetAmount == null || !budgetAmount.isPersistablePositiveFloat()) return
        if (budgetAppliedMonthLabel != null) return
        if (eligibleGoals.isEmpty()) return

        val plan = budgetCalculatorUseCase.generateSchedule(
            eligibleGoals,
            budgetAmount,
            budgetCurrency
        )
        if (generation != loadDataGeneration) return
        val applied = planningMutationMutex.withLock {
            if (generation != loadDataGeneration) {
                false
            } else {
                applyBudgetPlanLocked(
                    amount = budgetAmount,
                    currency = budgetCurrency,
                    plan = plan,
                    expectedLoadGeneration = generation,
                    sourcePlansByGoalId = sourcePlansByGoalId,
                    sourceGoals = sourceGoals
                )
            }
        }
        if (
            applied &&
            generation == loadDataGeneration &&
            !settings.hasSeenBudgetMigrationNotice
        ) {
            _uiState.update { it.copy(showBudgetMigrationNotice = true) }
        }
    }

    private suspend fun applyBudgetPlanLocked(
        amount: Double,
        currency: String,
        plan: BudgetCalculatorPlan,
        expectedLoadGeneration: Long? = null,
        sourcePlansByGoalId: Map<String, MonthlyGoalPlan> = plansByGoalId,
        sourceGoals: List<Goal> = activeGoals
    ): Boolean {
        check(amount.isFinite() && amount > 0.0) {
            "Budget amount is invalid"
        }
        if (sourcePlansByGoalId.isEmpty()) return false

        val contributionMap = plan.schedule.firstOrNull()?.contributions
            ?.associate { it.goalId to it.amount }
            ?: emptyMap()

        val customAmounts = mutableMapOf<String, Double>()
        for (planItem in sourcePlansByGoalId.values) {
            if (planItem.isSkipped) continue
            val plannedAmount = contributionMap[planItem.goalId] ?: 0.0
            check(plannedAmount.isFinite() && plannedAmount >= 0.0) {
                "Budget contribution for ${planItem.goalId} is invalid"
            }
            val converted = if (plannedAmount <= 0.0) {
                0.0
            } else {
                monthlyPlanningService.convertAmount(
                    amount = plannedAmount,
                    fromCurrency = currency,
                    toCurrency = planItem.currency
                )
            }
            check(
                converted.isFinite() &&
                    (plannedAmount == 0.0 || converted > 0.0)
            ) {
                "Converted budget contribution for ${planItem.goalId} is invalid"
            }
            customAmounts[planItem.goalId] = converted
        }

        if (
            expectedLoadGeneration != null &&
            expectedLoadGeneration != loadDataGeneration
        ) {
            return false
        }

        val updatedPlans = monthlyGoalPlanService.applyCustomAmounts(
            monthLabel,
            customAmounts
        )
        plansByGoalId = updatedPlans.associateBy { it.goalId }

        val goalById = sourceGoals.associateBy { it.id }
        val focusGoalName = updatedPlans
            .filter { !it.isSkipped && (it.customAmount ?: 0.0) > 0.01 }
            .mapNotNull { updatedPlan -> goalById[updatedPlan.goalId] }
            .minByOrNull { it.deadline }
            ?.name

        settings.monthlyBudget = amount
        settings.budgetCurrency = currency
        settings.budgetAppliedMonthLabel = monthLabel
        settings.budgetAppliedSignature = buildBudgetSignature(sourceGoals)
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
        runCatching {
            calculateTotal(
                _uiState.value.displayCurrency,
                rows.map { it.requirement.currency to it.adjustedRequiredMonthly }
            )
        }.onSuccess { total ->
            _uiState.update {
                it.copy(
                    requirements = rows,
                    totalRequired = total,
                    flexAdjustment = monthlyPlanningService.flexAdjustment,
                    error = null
                )
            }
        }.onFailure { error ->
            _uiState.update {
                it.copy(
                    requirements = rows,
                    totalRequired = null,
                    flexAdjustment = monthlyPlanningService.flexAdjustment,
                    error = error.message
                        ?: "Monthly total is unavailable. Refresh rates and retry."
                )
            }
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

private fun Double.isPersistablePositiveFloat(): Boolean {
    if (!isFinite() || this <= 0.0) return false
    val persisted = toFloat()
    return persisted.isFinite() && persisted > 0f
}
