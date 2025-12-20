package com.xax.CryptoSavingsTracker.presentation.goals

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.usecase.goal.DeleteGoalUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalsUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.UpdateGoalUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI State for the Goals List screen
 */
data class GoalListUiState(
    val goals: List<Goal> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val selectedFilter: GoalFilter = GoalFilter.ALL,
    val showDeleteConfirmation: Goal? = null
)

/**
 * Filter options for goals
 */
enum class GoalFilter {
    ALL,
    ACTIVE,
    PAUSED,
    COMPLETED,
    CANCELLED
}

/**
 * ViewModel for the Goals List screen
 */
@HiltViewModel
class GoalListViewModel @Inject constructor(
    private val getGoalsUseCase: GetGoalsUseCase,
    private val deleteGoalUseCase: DeleteGoalUseCase,
    private val updateGoalUseCase: UpdateGoalUseCase
) : ViewModel() {

    private val _selectedFilter = MutableStateFlow(GoalFilter.ALL)
    private val _isLoading = MutableStateFlow(true)
    private val _error = MutableStateFlow<String?>(null)
    private val _showDeleteConfirmation = MutableStateFlow<Goal?>(null)

    val uiState: StateFlow<GoalListUiState> = combine(
        getGoalsUseCase(),
        _selectedFilter,
        _isLoading,
        _error,
        _showDeleteConfirmation
    ) { goals, filter, isLoading, error, deleteConfirmation ->
        val filteredGoals = when (filter) {
            GoalFilter.ALL -> goals
            GoalFilter.ACTIVE -> goals.filter { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
            GoalFilter.PAUSED -> goals.filter { it.lifecycleStatus == GoalLifecycleStatus.PAUSED }
            GoalFilter.COMPLETED -> goals.filter { it.lifecycleStatus == GoalLifecycleStatus.COMPLETED }
            GoalFilter.CANCELLED -> goals.filter { it.lifecycleStatus == GoalLifecycleStatus.CANCELLED }
        }

        GoalListUiState(
            goals = filteredGoals.sortedBy { it.deadline },
            isLoading = false,
            error = error,
            selectedFilter = filter,
            showDeleteConfirmation = deleteConfirmation
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = GoalListUiState()
    )

    fun setFilter(filter: GoalFilter) {
        _selectedFilter.value = filter
    }

    fun requestDeleteGoal(goal: Goal) {
        _showDeleteConfirmation.value = goal
    }

    fun dismissDeleteConfirmation() {
        _showDeleteConfirmation.value = null
    }

    fun confirmDeleteGoal() {
        val goal = _showDeleteConfirmation.value ?: return
        viewModelScope.launch {
            deleteGoalUseCase(goal.id).fold(
                onSuccess = {
                    _showDeleteConfirmation.value = null
                },
                onFailure = { e ->
                    _error.value = e.message ?: "Failed to delete goal"
                    _showDeleteConfirmation.value = null
                }
            )
        }
    }

    fun updateGoalStatus(goalId: String, status: GoalLifecycleStatus) {
        viewModelScope.launch {
            updateGoalUseCase.updateStatus(goalId, status).fold(
                onSuccess = { /* Status updated */ },
                onFailure = { e ->
                    _error.value = e.message ?: "Failed to update goal status"
                }
            )
        }
    }

    fun clearError() {
        _error.value = null
    }
}
