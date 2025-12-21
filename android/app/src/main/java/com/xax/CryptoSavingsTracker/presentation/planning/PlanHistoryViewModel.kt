package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.usecase.execution.UndoExecutionUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class PlanHistoryRow(
    val recordId: String,
    val monthLabel: String,
    val completedAtMillis: Long,
    val totalRequired: Double,
    val totalActual: Double,
    val isUndoAvailable: Boolean
)

data class PlanHistoryUiState(
    val rows: List<PlanHistoryRow> = emptyList(),
    val isUndoing: Boolean = false,
    val error: String? = null,
    val showUndoConfirmationForRecordId: String? = null
)

@HiltViewModel
class PlanHistoryViewModel @Inject constructor(
    executionRecordRepository: ExecutionRecordRepository,
    completedExecutionRepository: CompletedExecutionRepository,
    private val undoExecutionUseCase: UndoExecutionUseCase
) : ViewModel() {

    private val _isUndoing = kotlinx.coroutines.flow.MutableStateFlow(false)
    private val _error = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)
    private val _showUndoConfirmationForRecordId = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)

    val uiState: StateFlow<PlanHistoryUiState> = combine(
        executionRecordRepository.getRecordsByStatus(ExecutionStatus.CLOSED),
        completedExecutionRepository.getAll(),
        _isUndoing,
        _error,
        _showUndoConfirmationForRecordId
    ) { records, completed, isUndoing, error, undoConfirmId ->
        val completedByRecordId = completed.groupBy { it.executionRecordId }
        val now = System.currentTimeMillis()

        val rows = records.mapNotNull { record ->
            val items = completedByRecordId[record.id].orEmpty()
            if (items.isEmpty()) return@mapNotNull null

            val completedAtMillis = items.maxOf { it.completedAtMillis }
            val canUndoUntil = items.minOf { it.canUndoUntilMillis }
            val totalRequired = items.sumOf { it.requiredAmount }
            val totalActual = items.sumOf { it.actualAmount }

            PlanHistoryRow(
                recordId = record.id,
                monthLabel = record.monthLabel,
                completedAtMillis = completedAtMillis,
                totalRequired = totalRequired,
                totalActual = totalActual,
                isUndoAvailable = canUndoUntil > now
            )
        }.sortedByDescending { it.monthLabel }

        PlanHistoryUiState(
            rows = rows,
            isUndoing = isUndoing,
            error = error,
            showUndoConfirmationForRecordId = undoConfirmId
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = PlanHistoryUiState()
    )

    fun requestUndo(recordId: String) {
        _showUndoConfirmationForRecordId.value = recordId
    }

    fun dismissUndo() {
        _showUndoConfirmationForRecordId.value = null
    }

    fun confirmUndo() {
        val recordId = _showUndoConfirmationForRecordId.value ?: return
        viewModelScope.launch {
            _isUndoing.value = true
            undoExecutionUseCase(recordId).fold(
                onSuccess = { _showUndoConfirmationForRecordId.value = null },
                onFailure = { e -> _error.value = e.message ?: "Failed to undo execution" }
            )
            _isUndoing.value = false
        }
    }

    fun clearError() {
        _error.value = null
    }
}
