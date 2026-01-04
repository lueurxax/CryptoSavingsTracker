package com.xax.CryptoSavingsTracker.presentation.execution

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
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
import java.time.LocalDate
import kotlinx.coroutines.ExperimentalCoroutinesApi

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
    val currentFocusGoal: ExecutionFocusGoal? = null,
    val lastRateUpdateMillis: Long? = null
)

data class ExecutionFocusGoal(
    val goalName: String,
    val deadline: LocalDate
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
    val hasWarning: Boolean,
    val rateUpdateMillis: Long?
)

@HiltViewModel
@OptIn(ExperimentalCoroutinesApi::class)
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
    private val goalRepository: GoalRepository
) : ViewModel() {

    private val _isBusy = kotlinx.coroutines.flow.MutableStateFlow(false)
    private val _error = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)
    private val _displayCurrency = kotlinx.coroutines.flow.MutableStateFlow(
        monthlyPlanningSettings.executionDisplayCurrency
    )

    private val sessionFlow = getExecutionSessionUseCase.currentExecuting()
    private val remainingDisplayFlow = sessionFlow.combine(_displayCurrency) { session, currency ->
        session to currency
    }.mapLatest { (session, currency) ->
        buildRemainingDisplay(session, currency)
    }
    private val focusGoalFlow = sessionFlow.combine(goalRepository.getActiveGoals()) { session, goals ->
        if (session == null) return@combine null
        val goalById = goals.associateBy { it.id }
        val candidates = session.activeGoals.mapNotNull { progress ->
            val remaining = progress.plannedAmount - progress.contributed
            if (remaining <= 0.01) return@mapNotNull null
            val goal = goalById[progress.snapshot.goalId] ?: return@mapNotNull null
            ExecutionFocusGoal(goalName = progress.snapshot.goalName, deadline = goal.deadline)
        }
        candidates.minByOrNull { it.deadline }
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

    // Use nested combine to stay within 5-parameter limit
    val uiState: StateFlow<ExecutionUiState> = combine(
        combine(sessionFlow, undoableRecordFlow) { session, undoableRecordId ->
            session to undoableRecordId
        },
        combine(_isBusy, _error, _displayCurrency) { isBusy, error, displayCurrency ->
            Triple(isBusy, error, displayCurrency)
        },
        remainingDisplayFlow,
        focusGoalFlow
    ) { (session, undoableRecordId), (isBusy, error, displayCurrency), remainingDisplay, focusGoal ->
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
            currentFocusGoal = focusGoal,
            lastRateUpdateMillis = remainingDisplay.rateUpdateMillis
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
                hasWarning = false,
                rateUpdateMillis = null
            )
        }

        val remainingByGoal = mutableMapOf<String, Double>()
        val currencyByGoal = mutableMapOf<String, String>()
        val rateCache = mutableMapOf<String, Double>()
        var hasWarning = false
        var didFetchRates = false

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
                didFetchRates = true
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
            hasWarning = hasWarning,
            rateUpdateMillis = if (didFetchRates || rateCache.isNotEmpty()) System.currentTimeMillis() else null
        )
    }

}
