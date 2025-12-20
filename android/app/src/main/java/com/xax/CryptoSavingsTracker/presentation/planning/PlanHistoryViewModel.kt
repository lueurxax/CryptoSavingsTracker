package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
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
    val rows: List<PlanHistoryRow> = emptyList()
)

@HiltViewModel
class PlanHistoryViewModel @Inject constructor(
    executionRecordRepository: ExecutionRecordRepository,
    completedExecutionRepository: CompletedExecutionRepository
) : ViewModel() {

    val uiState: StateFlow<PlanHistoryUiState> = combine(
        executionRecordRepository.getRecordsByStatus(ExecutionStatus.CLOSED),
        completedExecutionRepository.getAll()
    ) { records, completed ->
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

        PlanHistoryUiState(rows = rows)
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = PlanHistoryUiState()
    )
}
