package com.xax.CryptoSavingsTracker.presentation.execution

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.GoalContribution
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
import com.xax.CryptoSavingsTracker.domain.model.PlanningMode
import com.xax.CryptoSavingsTracker.domain.model.ScheduledGoalBlock
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetsUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.CompleteExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionContributionCalculatorUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionGoalProgress
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionSession
import com.xax.CryptoSavingsTracker.domain.usecase.execution.GetExecutionSessionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.StartExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.UndoExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.UndoStartExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.planning.FixedBudgetPlanningUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject
import kotlin.math.max

data class ExecutionUiState(
    val session: ExecutionSession? = null,
    val undoableRecordId: String? = null,
    val canUndoStart: Boolean = false,
    val isBusy: Boolean = false,
    val error: String? = null,
    val displayCurrency: String = "USD",
    val remainingByGoalId: Map<String, Double> = emptyMap(),
    val remainingCurrencyByGoalId: Map<String, String> = emptyMap(),
    val totalRemainingDisplay: Double? = null,
    val hasRateConversionWarning: Boolean = false,
    // Fixed Budget Mode context
    val isFixedBudgetMode: Boolean = false,
    val monthlyBudget: Double = 0.0,
    val budgetCurrency: String = "USD",
    val budgetProgress: Double = 0.0, // Progress toward monthly budget (0-100)
    val currentScheduledGoal: FixedBudgetGoalInfo? = null,
    val nextUpGoal: FixedBudgetGoalInfo? = null,
    val scheduleBlocks: List<ScheduledGoalBlock> = emptyList()
)

/**
 * Info about a goal in the fixed budget schedule.
 */
data class FixedBudgetGoalInfo(
    val goalId: String,
    val goalName: String,
    val emoji: String?,
    val progress: Double, // 0-100
    val contributed: Double,
    val target: Double,
    val paymentsRemaining: Int
)

data class ExecutionAssetOption(
    val assetId: String,
    val currency: String,
    val displayName: String,
    val isShared: Boolean
)

private data class RemainingDisplayState(
    val remainingByGoal: Map<String, Double>,
    val remainingCurrencyByGoal: Map<String, String>,
    val totalRemaining: Double?,
    val hasWarning: Boolean
)

@HiltViewModel
class ExecutionViewModel @Inject constructor(
    private val startExecutionUseCase: StartExecutionUseCase,
    private val getExecutionSessionUseCase: GetExecutionSessionUseCase,
    private val completeExecutionUseCase: CompleteExecutionUseCase,
    private val undoExecutionUseCase: UndoExecutionUseCase,
    private val undoStartExecutionUseCase: UndoStartExecutionUseCase,
    private val completedExecutionRepository: CompletedExecutionRepository,
    private val monthlyPlanningSettings: MonthlyPlanningSettings,
    private val executionContributionCalculator: ExecutionContributionCalculatorUseCase,
    private val getAssetsUseCase: GetAssetsUseCase,
    private val allocationRepository: AllocationRepository,
    private val fixedBudgetPlanningUseCase: FixedBudgetPlanningUseCase,
    private val goalRepository: GoalRepository
) : ViewModel() {

    private val _isBusy = kotlinx.coroutines.flow.MutableStateFlow(false)
    private val _error = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)
    private val _displayCurrency = kotlinx.coroutines.flow.MutableStateFlow(
        monthlyPlanningSettings.executionDisplayCurrency
    )

    // Fixed Budget Mode state
    private val _fixedBudgetState = kotlinx.coroutines.flow.MutableStateFlow(FixedBudgetExecutionState())

    private val sessionFlow = getExecutionSessionUseCase.currentExecuting()
    private val remainingDisplayFlow = sessionFlow.combine(_displayCurrency) { session, currency ->
        session to currency
    }.mapLatest { (session, currency) ->
        buildRemainingDisplay(session, currency)
    }

    // Extract undoable record flow as a separate property
    private val undoableRecordFlow = completedExecutionRepository.getAll()
        .map { items ->
            val now = System.currentTimeMillis()
            items
                .filter { it.canUndoUntilMillis > now }
                .map { it.executionRecordId }
                .distinct()
                .firstOrNull()
        }
        .distinctUntilChanged()

    init {
        // Load fixed budget context when settings change
        viewModelScope.launch {
            loadFixedBudgetContext()
        }
    }

    // Use nested combine to stay within 5-parameter limit
    val uiState: StateFlow<ExecutionUiState> = combine(
        combine(sessionFlow, undoableRecordFlow) { session, undoableRecordId ->
            session to undoableRecordId
        },
        combine(_isBusy, _error, _displayCurrency) { isBusy, error, displayCurrency ->
            Triple(isBusy, error, displayCurrency)
        },
        remainingDisplayFlow,
        _fixedBudgetState
    ) { (session, undoableRecordId), (isBusy, error, displayCurrency), remainingDisplay, fixedBudgetState ->
        val now = System.currentTimeMillis()
        val canUndoStart = session?.record?.startedAtMillis?.let { startedAt ->
            now < startedAt + UNDO_WINDOW_MILLIS
        } ?: false

        ExecutionUiState(
            session = session,
            undoableRecordId = undoableRecordId,
            canUndoStart = canUndoStart,
            isBusy = isBusy,
            error = error,
            displayCurrency = displayCurrency,
            remainingByGoalId = remainingDisplay.remainingByGoal,
            remainingCurrencyByGoalId = remainingDisplay.remainingCurrencyByGoal,
            totalRemainingDisplay = remainingDisplay.totalRemaining,
            hasRateConversionWarning = remainingDisplay.hasWarning,
            // Fixed Budget Mode context
            isFixedBudgetMode = fixedBudgetState.isEnabled,
            monthlyBudget = fixedBudgetState.monthlyBudget,
            budgetCurrency = fixedBudgetState.currency,
            budgetProgress = fixedBudgetState.budgetProgress,
            currentScheduledGoal = fixedBudgetState.currentGoal,
            nextUpGoal = fixedBudgetState.nextUpGoal,
            scheduleBlocks = fixedBudgetState.scheduleBlocks
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = ExecutionUiState()
    )

    fun clearError() {
        _error.value = null
    }

    fun updateDisplayCurrency(currency: String) {
        val normalized = currency.trim().uppercase().ifBlank { "USD" }
        monthlyPlanningSettings.executionDisplayCurrency = normalized
        _displayCurrency.value = normalized
    }

    fun remainingToClose(goal: ExecutionGoalProgress): Double {
        return max(0.0, goal.plannedAmount - goal.contributed)
    }

    suspend fun loadAssetOptions(goalId: String): List<ExecutionAssetOption> {
        val assets = getAssetsUseCase().first()
        if (assets.isEmpty()) return emptyList()

        val allocationsForGoal = allocationRepository.getAllocationsForGoal(goalId)
        val allocatedAssetIds = allocationsForGoal.map { it.assetId }.toSet()

        val options = assets.map { asset ->
            val allocationsForAsset = allocationRepository.getAllocationsForAsset(asset.id)
            ExecutionAssetOption(
                assetId = asset.id,
                currency = asset.currency,
                displayName = asset.displayName(),
                isShared = allocationsForAsset.size > 1
            )
        }

        val (preferred, remaining) = options.partition { allocatedAssetIds.contains(it.assetId) }
        return preferred + remaining.sortedBy { it.displayName.lowercase() }
    }

    suspend fun suggestedContributionAmount(
        goal: ExecutionGoalProgress,
        assetCurrency: String
    ): Double? {
        val remaining = executionContributionCalculator.remainingToClose(goal)
        if (remaining <= 0.0) return null
        return executionContributionCalculator.convertAmount(
            amount = remaining,
            from = goal.snapshot.currency,
            to = assetCurrency
        )
    }

    fun startExecution() {
        viewModelScope.launch {
            _isBusy.value = true
            startExecutionUseCase().fold(
                onSuccess = { /* session flow updates */ },
                onFailure = { e -> _error.value = e.message ?: "Failed to start execution" }
            )
            _isBusy.value = false
        }
    }

    fun completeExecution() {
        val recordId = uiState.value.session?.record?.id ?: return
        viewModelScope.launch {
            _isBusy.value = true
            completeExecutionUseCase(recordId).fold(
                onSuccess = { /* session ends */ },
                onFailure = { e -> _error.value = e.message ?: "Failed to complete execution" }
            )
            _isBusy.value = false
        }
    }

    fun undoLastCompletion() {
        val recordId = uiState.value.undoableRecordId ?: return
        viewModelScope.launch {
            _isBusy.value = true
            undoExecutionUseCase(recordId).fold(
                onSuccess = { /* record reopens */ },
                onFailure = { e -> _error.value = e.message ?: "Failed to undo execution" }
            )
            _isBusy.value = false
        }
    }

    fun undoStartExecution() {
        val recordId = uiState.value.session?.record?.id ?: return
        viewModelScope.launch {
            _isBusy.value = true
            undoStartExecutionUseCase(recordId).fold(
                onSuccess = { /* record goes back to draft */ },
                onFailure = { e -> _error.value = e.message ?: "Failed to undo start" }
            )
            _isBusy.value = false
        }
    }

    private companion object {
        const val UNDO_WINDOW_MILLIS: Long = 24L * 60L * 60L * 1000L
    }

    private suspend fun buildRemainingDisplay(
        session: ExecutionSession?,
        displayCurrency: String
    ): RemainingDisplayState {
        if (session == null) {
            return RemainingDisplayState(
                remainingByGoal = emptyMap(),
                remainingCurrencyByGoal = emptyMap(),
                totalRemaining = null,
                hasWarning = false
            )
        }

        val remainingByGoal = mutableMapOf<String, Double>()
        val currencyByGoal = mutableMapOf<String, String>()
        val rateCache = mutableMapOf<String, Double>()
        var hasWarning = false

        for (goal in session.goals) {
            val remaining = max(0.0, goal.plannedAmount - goal.contributed)
            if (remaining <= 0.0) {
                remainingByGoal[goal.snapshot.goalId] = 0.0
                currencyByGoal[goal.snapshot.goalId] = displayCurrency
                continue
            }

            if (goal.snapshot.currency.equals(displayCurrency, ignoreCase = true)) {
                remainingByGoal[goal.snapshot.goalId] = remaining
                currencyByGoal[goal.snapshot.goalId] = displayCurrency
                continue
            }

            val key = "${goal.snapshot.currency.uppercase()}->${displayCurrency.uppercase()}"
            val rate = rateCache[key] ?: runCatching {
                executionContributionCalculator.convertAmount(1.0, goal.snapshot.currency, displayCurrency)
            }.getOrNull()?.also { rateCache[key] = it } ?: 0.0

            if (rate > 0) {
                remainingByGoal[goal.snapshot.goalId] = remaining * rate
                currencyByGoal[goal.snapshot.goalId] = displayCurrency
            } else {
                remainingByGoal[goal.snapshot.goalId] = remaining
                currencyByGoal[goal.snapshot.goalId] = goal.snapshot.currency
                hasWarning = true
            }
        }

        val totalRemaining = if (!hasWarning && currencyByGoal.values.all { it.equals(displayCurrency, true) }) {
            remainingByGoal.values.sum()
        } else {
            null
        }

        return RemainingDisplayState(
            remainingByGoal = remainingByGoal,
            remainingCurrencyByGoal = currencyByGoal,
            totalRemaining = totalRemaining,
            hasWarning = hasWarning
        )
    }

    /**
     * Load fixed budget context for execution display.
     * Shows current scheduled goal, progress toward monthly budget, and next-up goal.
     */
    private suspend fun loadFixedBudgetContext() {
        val isEnabled = monthlyPlanningSettings.planningMode == PlanningMode.FIXED_BUDGET
        if (!isEnabled) {
            _fixedBudgetState.value = FixedBudgetExecutionState()
            return
        }

        val budget = monthlyPlanningSettings.monthlyBudget ?: 0.0
        val currency = monthlyPlanningSettings.budgetCurrency

        if (budget <= 0) {
            _fixedBudgetState.value = FixedBudgetExecutionState(isEnabled = true, currency = currency)
            return
        }

        try {
            // Get active goals and generate schedule
            val goals = goalRepository.getAllGoals().first()
                .filter { it.lifecycleStatus == com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus.ACTIVE }

            if (goals.isEmpty()) {
                _fixedBudgetState.value = FixedBudgetExecutionState(
                    isEnabled = true,
                    monthlyBudget = budget,
                    currency = currency
                )
                return
            }

            // Generate the schedule
            val plan = fixedBudgetPlanningUseCase.generateSchedule(goals, budget, currency)
            val scheduleBlocks = fixedBudgetPlanningUseCase.buildTimelineBlocks(plan, goals)

            // Find current goal being funded (first incomplete goal in schedule)
            val currentContribution = plan.schedule.firstOrNull()?.contributions?.firstOrNull()
            val currentGoalInfo = currentContribution?.let { contribution ->
                val goal = goals.find { it.id == contribution.goalId }
                goal?.let {
                    FixedBudgetGoalInfo(
                        goalId = it.id,
                        goalName = it.name,
                        emoji = it.emoji,
                        progress = if (it.targetAmount > 0) (contribution.runningTotal / it.targetAmount * 100).coerceIn(0.0, 100.0) else 0.0,
                        contributed = contribution.runningTotal,
                        target = it.targetAmount,
                        paymentsRemaining = scheduleBlocks.find { block -> block.goalId == it.id }?.paymentCount ?: 0
                    )
                }
            }

            // Find next-up goal (second goal in schedule, if any)
            val nextContribution = plan.schedule.firstOrNull()?.contributions?.getOrNull(1)
                ?: plan.schedule.getOrNull(1)?.contributions?.firstOrNull()
            val nextUpGoalInfo = nextContribution?.let { contribution ->
                val goal = goals.find { it.id == contribution.goalId }
                goal?.let {
                    FixedBudgetGoalInfo(
                        goalId = it.id,
                        goalName = it.name,
                        emoji = it.emoji,
                        progress = if (it.targetAmount > 0) (contribution.runningTotal / it.targetAmount * 100).coerceIn(0.0, 100.0) else 0.0,
                        contributed = contribution.runningTotal,
                        target = it.targetAmount,
                        paymentsRemaining = scheduleBlocks.find { block -> block.goalId == it.id }?.paymentCount ?: 0
                    )
                }
            }

            // Calculate budget progress (contributed this month vs monthly budget)
            val totalContributed = uiState.value.session?.totalContributed ?: 0.0
            val budgetProgress = if (budget > 0) (totalContributed / budget * 100).coerceIn(0.0, 100.0) else 0.0

            _fixedBudgetState.value = FixedBudgetExecutionState(
                isEnabled = true,
                monthlyBudget = budget,
                currency = currency,
                budgetProgress = budgetProgress,
                currentGoal = currentGoalInfo,
                nextUpGoal = nextUpGoalInfo,
                scheduleBlocks = scheduleBlocks
            )
        } catch (e: Exception) {
            // Silently fail - just don't show fixed budget context
            _fixedBudgetState.value = FixedBudgetExecutionState(
                isEnabled = true,
                monthlyBudget = budget,
                currency = currency
            )
        }
    }

    /**
     * Refresh fixed budget context (call after contribution changes).
     */
    fun refreshFixedBudgetContext() {
        viewModelScope.launch {
            loadFixedBudgetContext()
        }
    }
}

/**
 * Internal state for fixed budget mode in execution.
 */
private data class FixedBudgetExecutionState(
    val isEnabled: Boolean = false,
    val monthlyBudget: Double = 0.0,
    val currency: String = "USD",
    val budgetProgress: Double = 0.0,
    val currentGoal: FixedBudgetGoalInfo? = null,
    val nextUpGoal: FixedBudgetGoalInfo? = null,
    val scheduleBlocks: List<ScheduledGoalBlock> = emptyList()
)
