package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.CompletionEventRepository
import com.xax.CryptoSavingsTracker.domain.usecase.execution.UndoExecutionUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class PlanHistoryRow(
    val eventId: String,
    val recordId: String,
    val monthLabel: String,
    val sequence: Int,
    val completedAtMillis: Long,
    val undoneAtMillis: Long?,
    val totalRequired: Double,
    val totalActual: Double,
    val isUndoAvailable: Boolean,
    val isUndone: Boolean
)

data class PlanHistoryMonthGroup(
    val monthLabel: String,
    val latestCompletedAtMillis: Long,
    val summaryRequired: Double,
    val summaryActual: Double,
    val undoRecordId: String?,
    val events: List<PlanHistoryRow>
)

data class PlanHistoryUiState(
    val groups: List<PlanHistoryMonthGroup> = emptyList(),
    val isUndoing: Boolean = false,
    val error: String? = null,
    val showUndoConfirmationForRecordId: String? = null
)

@HiltViewModel
class PlanHistoryViewModel @Inject constructor(
    completionEventRepository: CompletionEventRepository,
    completedExecutionRepository: CompletedExecutionRepository,
    private val undoExecutionUseCase: UndoExecutionUseCase
) : ViewModel() {

    private val _isUndoing = kotlinx.coroutines.flow.MutableStateFlow(false)
    private val _error = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)
    private val _showUndoConfirmationForRecordId = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)

    val uiState: StateFlow<PlanHistoryUiState> = combine(
        completionEventRepository.getAll(),
        completedExecutionRepository.getAll(),
        _isUndoing,
        _error,
        _showUndoConfirmationForRecordId
    ) { events, completed, isUndoing, error, undoConfirmId ->
        val completedByEventId = completed
            .filter { !it.completionEventId.isNullOrBlank() }
            .groupBy { it.completionEventId!! }
        val latestOpenEventByRecordId = events
            .filter { it.undoneAtMillis == null }
            .groupBy { it.executionRecordId }
            .mapValues { (_, value) -> value.maxByOrNull { it.sequence } }
        val now = System.currentTimeMillis()

        val rows = events.mapNotNull { event ->
            val items = completedByEventId[event.id].orEmpty()
            if (items.isEmpty()) return@mapNotNull null

            val canUndoUntil = items.minOf { it.canUndoUntilMillis }
            val totalRequired = items.sumOf { it.requiredAmount }
            val totalActual = items.sumOf { it.actualAmount }
            val isLatestOpen = latestOpenEventByRecordId[event.executionRecordId]?.id == event.id
            val isUndoAvailable = event.undoneAtMillis == null && isLatestOpen && canUndoUntil > now

            PlanHistoryRow(
                eventId = event.id,
                recordId = event.executionRecordId,
                monthLabel = event.monthLabel,
                sequence = event.sequence,
                completedAtMillis = event.completedAtMillis,
                undoneAtMillis = event.undoneAtMillis,
                totalRequired = totalRequired,
                totalActual = totalActual,
                isUndoAvailable = isUndoAvailable,
                isUndone = event.undoneAtMillis != null
            )
        }.sortedWith(
            compareByDescending<PlanHistoryRow> { it.completedAtMillis }
                .thenByDescending { it.sequence }
        )

        val groups = rows
            .groupBy { it.monthLabel }
            .map { (monthLabel, monthRows) ->
                val sortedMonthRows = monthRows.sortedWith(
                    compareByDescending<PlanHistoryRow> { it.completedAtMillis }
                        .thenByDescending { it.sequence }
                )
                val latest = sortedMonthRows.first()
                PlanHistoryMonthGroup(
                    monthLabel = monthLabel,
                    latestCompletedAtMillis = latest.completedAtMillis,
                    summaryRequired = latest.totalRequired,
                    summaryActual = latest.totalActual,
                    undoRecordId = sortedMonthRows.firstOrNull { it.isUndoAvailable }?.recordId,
                    events = sortedMonthRows
                )
            }
            .sortedByDescending { it.monthLabel }

        PlanHistoryUiState(
            groups = groups,
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
