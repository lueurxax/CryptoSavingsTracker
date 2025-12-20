package com.xax.CryptoSavingsTracker.presentation.goals

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.usecase.goal.DeleteGoalUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalProgressUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GoalWithProgress
import com.xax.CryptoSavingsTracker.domain.usecase.goal.UpdateGoalUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI State for Goal Detail screen
 */
data class GoalDetailUiState(
    val goal: Goal? = null,
    val allocatedAmount: Double = 0.0,  // Total allocated (sum of allocations)
    val fundedAmount: Double = 0.0,     // Actual funded amount (min of allocation vs balance, matches iOS)
    val progress: Double = 0.0,
    val progressPercent: Int = 0,
    val isLoading: Boolean = true,
    val error: String? = null,
    val showDeleteConfirmation: Boolean = false,
    val showStatusMenu: Boolean = false,
    val isDeleted: Boolean = false
)

/**
 * ViewModel for Goal Detail screen
 */
@HiltViewModel
class GoalDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val getGoalProgressUseCase: GetGoalProgressUseCase,
    private val updateGoalUseCase: UpdateGoalUseCase,
    private val deleteGoalUseCase: DeleteGoalUseCase
) : ViewModel() {

    private val goalId: String = checkNotNull(savedStateHandle["goalId"])

    private val _showDeleteConfirmation = MutableStateFlow(false)
    private val _showStatusMenu = MutableStateFlow(false)
    private val _isDeleted = MutableStateFlow(false)
    private val _error = MutableStateFlow<String?>(null)

    val uiState: StateFlow<GoalDetailUiState> = combine(
        getGoalProgressUseCase.getProgressFlow(goalId),
        _showDeleteConfirmation,
        _showStatusMenu,
        _isDeleted,
        _error
    ) { goalWithProgress, showDelete, showStatus, isDeleted, error ->
        GoalDetailUiState(
            goal = goalWithProgress?.goal,
            allocatedAmount = goalWithProgress?.allocatedAmount ?: 0.0,
            fundedAmount = goalWithProgress?.fundedAmount ?: 0.0,
            progress = goalWithProgress?.progress ?: 0.0,
            progressPercent = goalWithProgress?.progressPercent ?: 0,
            isLoading = false,
            error = error,
            showDeleteConfirmation = showDelete,
            showStatusMenu = showStatus,
            isDeleted = isDeleted
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = GoalDetailUiState()
    )

    fun showDeleteConfirmation() {
        _showDeleteConfirmation.value = true
    }

    fun dismissDeleteConfirmation() {
        _showDeleteConfirmation.value = false
    }

    fun confirmDelete() {
        viewModelScope.launch {
            deleteGoalUseCase(goalId).fold(
                onSuccess = {
                    _showDeleteConfirmation.value = false
                    _isDeleted.value = true
                },
                onFailure = { e ->
                    _error.value = e.message ?: "Failed to delete goal"
                    _showDeleteConfirmation.value = false
                }
            )
        }
    }

    fun showStatusMenu() {
        _showStatusMenu.value = true
    }

    fun dismissStatusMenu() {
        _showStatusMenu.value = false
    }

    fun updateStatus(status: GoalLifecycleStatus) {
        viewModelScope.launch {
            updateGoalUseCase.updateStatus(goalId, status).fold(
                onSuccess = {
                    _showStatusMenu.value = false
                },
                onFailure = { e ->
                    _error.value = e.message ?: "Failed to update status"
                }
            )
        }
    }

    fun clearError() {
        _error.value = null
    }
}
