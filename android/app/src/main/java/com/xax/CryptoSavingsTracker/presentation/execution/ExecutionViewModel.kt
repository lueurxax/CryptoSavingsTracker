package com.xax.CryptoSavingsTracker.presentation.execution

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.execution.CompleteExecutionUseCase
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
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ExecutionUiState(
    val session: ExecutionSession? = null,
    val undoableRecordId: String? = null,
    val canUndoStart: Boolean = false,
    val isBusy: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class ExecutionViewModel @Inject constructor(
    private val startExecutionUseCase: StartExecutionUseCase,
    private val getExecutionSessionUseCase: GetExecutionSessionUseCase,
    private val completeExecutionUseCase: CompleteExecutionUseCase,
    private val undoExecutionUseCase: UndoExecutionUseCase,
    private val undoStartExecutionUseCase: UndoStartExecutionUseCase,
    private val completedExecutionRepository: CompletedExecutionRepository
) : ViewModel() {

    private val _isBusy = kotlinx.coroutines.flow.MutableStateFlow(false)
    private val _error = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)

    val uiState: StateFlow<ExecutionUiState> = combine(
        getExecutionSessionUseCase.currentExecuting(),
        completedExecutionRepository.getAll()
            .map { items ->
                val now = System.currentTimeMillis()
                items
                    .filter { it.canUndoUntilMillis > now }
                    .map { it.executionRecordId }
                    .distinct()
                    .firstOrNull()
            }
            .distinctUntilChanged(),
        _isBusy,
        _error
    ) { session, undoableRecordId, isBusy, error ->
        val now = System.currentTimeMillis()
        val canUndoStart = session?.record?.startedAtMillis?.let { startedAt ->
            now < startedAt + UNDO_WINDOW_MILLIS
        } ?: false

        ExecutionUiState(
            session = session,
            undoableRecordId = undoableRecordId,
            canUndoStart = canUndoStart,
            isBusy = isBusy,
            error = error
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = ExecutionUiState()
    )

    fun clearError() {
        _error.value = null
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
}
