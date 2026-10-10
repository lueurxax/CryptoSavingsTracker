package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.ExecutionRecord
import com.xax.CryptoSavingsTracker.domain.usecase.execution.CompleteExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionGoalProgress
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionSession
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionActionCopyCatalog
import com.xax.CryptoSavingsTracker.domain.usecase.execution.GetExecutionSessionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.StartExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.UndoExecutionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.UndoStartExecutionUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject
import java.util.Locale

/**
 * UI State for Monthly Execution screen.
 */
data class MonthlyExecutionUiState(
    val record: ExecutionRecord? = null,
    val goalProgress: List<ExecutionGoalProgress> = emptyList(),
    val overallProgress: Double = 0.0,
    val totalPlanned: Double? = null,
    val totalContributed: Double? = null,
    val totalsCurrency: String? = null,
    val fulfilledCount: Int = 0,
    val totalGoals: Int = 0,
    val isProgressAvailable: Boolean = false,
    val canComplete: Boolean = false,
    val recoveryRequired: Boolean = false,
    val showUndoBanner: Boolean = false,
    val undoExpiresAt: Long? = null,
    val undoTimeRemaining: String = "",
    val isLoading: Boolean = true,
    val isProcessing: Boolean = false,
    val error: String? = null,
    val showCompleteConfirmDialog: Boolean = false,
    val completedSuccessfully: Boolean = false
) {
    /** Null prevents the header from adding amounts with different units. */
    val summaryCurrency: String?
        get() = goalProgress.map { it.snapshot.currency.trim().uppercase(Locale.ROOT) }.distinct().singleOrNull()

    /** Goals that are not yet fulfilled */
    val activeGoals: List<ExecutionGoalProgress>
        get() = goalProgress.filter { !it.isFulfilled && !it.snapshot.isSkipped }

    /** Goals that are fulfilled */
    val completedGoals: List<ExecutionGoalProgress>
        get() = goalProgress.filter { it.isFulfilled }

    /** Skipped goals */
    val skippedGoals: List<ExecutionGoalProgress>
        get() = goalProgress.filter { it.snapshot.isSkipped }

    /** Whether all active goals are fulfilled */
    val allFulfilled: Boolean
        get() = isProgressAvailable && activeGoals.isEmpty() && completedGoals.isNotEmpty()

    /** Month label from record */
    val monthLabel: String
        get() = record?.monthLabel ?: ""
}

/**
 * ViewModel for Monthly Execution tracking screen.
 * Handles progress display, completion, and undo functionality.
 */
@HiltViewModel
class MonthlyExecutionViewModel @Inject constructor(
    private val getExecutionSessionUseCase: GetExecutionSessionUseCase,
    private val startExecutionUseCase: StartExecutionUseCase,
    private val completeExecutionUseCase: CompleteExecutionUseCase,
    private val undoExecutionUseCase: UndoExecutionUseCase,
    private val undoStartExecutionUseCase: UndoStartExecutionUseCase
) : ViewModel() {

    private val _uiState = MutableStateFlow(MonthlyExecutionUiState())
    val uiState: StateFlow<MonthlyExecutionUiState> = _uiState.asStateFlow()

    init {
        observeCurrentSession()
        startUndoCountdownTimer()
    }

    /**
     * Observe the current execution session and update UI state.
     */
    private fun observeCurrentSession() {
        viewModelScope.launch {
            getExecutionSessionUseCase.currentExecuting().collect { session ->
                if (session == null) {
                    _uiState.update {
                        it.copy(
                            record = null,
                            goalProgress = emptyList(),
                            overallProgress = 0.0,
                            totalPlanned = null,
                            totalContributed = null,
                            totalsCurrency = null,
                            fulfilledCount = 0,
                            totalGoals = 0,
                            isProgressAvailable = false,
                            canComplete = false,
                            recoveryRequired = false,
                            showUndoBanner = false,
                            undoExpiresAt = null,
                            undoTimeRemaining = "",
                            showCompleteConfirmDialog = false,
                            isLoading = false
                        )
                    }
                } else {
                    updateFromSession(session)
                }
            }
        }
    }

    /**
     * Update UI state from execution session.
     */
    private fun updateFromSession(session: ExecutionSession) {
        val record = session.record
        val recoveryRequired = !session.isProgressAvailable
        val showUndo = record.canUndo() || recoveryRequired

        _uiState.update {
            it.copy(
                record = record,
                goalProgress = if (session.isProgressAvailable) session.goals else emptyList(),
                overallProgress = if (session.isProgressAvailable) session.overallProgress else 0.0,
                totalPlanned = if (session.isProgressAvailable) session.totalPlanned else null,
                totalContributed = if (session.isProgressAvailable) session.totalContributed else null,
                totalsCurrency = if (session.isProgressAvailable) session.totalsCurrency else null,
                fulfilledCount = if (session.isProgressAvailable) session.fulfilledCount else 0,
                totalGoals = if (session.isProgressAvailable) session.goals.size else 0,
                isProgressAvailable = session.isProgressAvailable,
                canComplete = session.isProgressAvailable && session.conversionError == null,
                recoveryRequired = recoveryRequired,
                showUndoBanner = showUndo,
                undoExpiresAt = record.canUndoUntilMillis,
                undoTimeRemaining = if (recoveryRequired) "" else it.undoTimeRemaining,
                showCompleteConfirmDialog = if (recoveryRequired) false else it.showCompleteConfirmDialog,
                isLoading = false
            )
        }
    }

    /**
     * Countdown timer for undo banner.
     */
    private fun startUndoCountdownTimer() {
        viewModelScope.launch {
            while (true) {
                delay(1000L) // Update every second
                if (_uiState.value.recoveryRequired) {
                    _uiState.update {
                        it.copy(showUndoBanner = true, undoTimeRemaining = "")
                    }
                    continue
                }
                val expiresAt = _uiState.value.undoExpiresAt
                if (expiresAt != null) {
                    val remaining = expiresAt - System.currentTimeMillis()
                    if (remaining > 0) {
                        _uiState.update {
                            it.copy(undoTimeRemaining = formatTimeRemaining(remaining))
                        }
                    } else {
                        _uiState.update {
                            it.copy(showUndoBanner = false, undoTimeRemaining = "")
                        }
                    }
                }
            }
        }
    }

    /**
     * Format milliseconds to human-readable time.
     */
    private fun formatTimeRemaining(millis: Long): String {
        val seconds = millis / 1000
        val minutes = seconds / 60
        val hours = minutes / 60
        val days = hours / 24

        return when {
            days > 0 -> "${days}d ${hours % 24}h"
            hours > 0 -> "${hours}h ${minutes % 60}m"
            minutes > 0 -> "${minutes}m ${seconds % 60}s"
            else -> "${seconds}s"
        }
    }

    /**
     * Start execution tracking for current month.
     */
    fun startExecution(monthLabel: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isProcessing = true, error = null) }
            startExecutionUseCase(monthLabel)
                .onSuccess {
                    _uiState.update { it.copy(isProcessing = false) }
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(
                            isProcessing = false,
                            error = e.message ?: "Failed to start execution"
                        )
                    }
                }
        }
    }

    /**
     * Show confirmation dialog before completing.
     */
    fun showCompleteConfirmation() {
        _uiState.update {
            if (it.canComplete) {
                it.copy(showCompleteConfirmDialog = true)
            } else {
                it.copy(
                    showCompleteConfirmDialog = false,
                    error = ExecutionActionCopyCatalog.progressUnavailable()
                )
            }
        }
    }

    /**
     * Dismiss completion confirmation dialog.
     */
    fun dismissCompleteConfirmation() {
        _uiState.update { it.copy(showCompleteConfirmDialog = false) }
    }

    /**
     * Complete the current month's execution.
     */
    fun completeExecution() {
        val state = _uiState.value
        val recordId = state.record?.id ?: return
        if (!state.canComplete) {
            _uiState.update {
                it.copy(
                    showCompleteConfirmDialog = false,
                    error = ExecutionActionCopyCatalog.progressUnavailable()
                )
            }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isProcessing = true, showCompleteConfirmDialog = false, error = null) }
            completeExecutionUseCase(recordId)
                .onSuccess {
                    _uiState.update {
                        it.copy(
                            isProcessing = false,
                            completedSuccessfully = true
                        )
                    }
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(
                            isProcessing = false,
                            error = e.message ?: "Failed to complete execution"
                        )
                    }
                }
        }
    }

    /**
     * Undo the start of execution (return to planning).
     */
    fun undoStart() {
        val recordId = _uiState.value.record?.id ?: return

        viewModelScope.launch {
            _uiState.update { it.copy(isProcessing = true, error = null) }
            undoStartExecutionUseCase(recordId)
                .onSuccess {
                    _uiState.update { it.copy(isProcessing = false) }
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(
                            isProcessing = false,
                            error = e.message ?: "Failed to undo start"
                        )
                    }
                }
        }
    }

    /**
     * Undo a completed execution (reopen for more contributions).
     */
    fun undoCompletion() {
        val recordId = _uiState.value.record?.id ?: return

        viewModelScope.launch {
            _uiState.update { it.copy(isProcessing = true, error = null) }
            undoExecutionUseCase(recordId)
                .onSuccess {
                    _uiState.update { it.copy(isProcessing = false) }
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(
                            isProcessing = false,
                            error = e.message ?: "Failed to undo completion"
                        )
                    }
                }
        }
    }

    /**
     * Clear error message.
     */
    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    /**
     * Clear completed successfully flag.
     */
    fun clearCompletedSuccessfully() {
        _uiState.update { it.copy(completedSuccessfully = false) }
    }

    /**
     * Refresh execution data.
     */
    fun refresh() {
        if (_uiState.value.record == null) return
        _uiState.update { it.copy(isLoading = true) }
        getExecutionSessionUseCase.refresh()
    }
}
