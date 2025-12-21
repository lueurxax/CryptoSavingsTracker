package com.xax.CryptoSavingsTracker.presentation.goals

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationValidationService
import com.xax.CryptoSavingsTracker.domain.usecase.goal.DeleteGoalUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalProgressUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GoalWithProgress
import com.xax.CryptoSavingsTracker.domain.usecase.goal.UpdateGoalUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI State for the Goals List screen
 */
data class GoalListUiState(
    val goals: List<GoalWithProgress> = emptyList(),
    val unallocatedAssets: List<UnallocatedAssetWarning> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val selectedFilter: GoalFilter = GoalFilter.ALL,
    val showDeleteConfirmation: Goal? = null
)

/**
 * Filter options for goals (matches iOS GoalLifecycleStatus)
 */
enum class GoalFilter {
    ALL,
    ACTIVE,
    FINISHED,
    CANCELLED,
    DELETED
}

/**
 * ViewModel for the Goals List screen
 */
@HiltViewModel
@OptIn(ExperimentalCoroutinesApi::class)
class GoalListViewModel @Inject constructor(
    private val getGoalProgressUseCase: GetGoalProgressUseCase,
    private val deleteGoalUseCase: DeleteGoalUseCase,
    private val updateGoalUseCase: UpdateGoalUseCase,
    private val allocationValidationService: AllocationValidationService
) : ViewModel() {

    private val _selectedFilter = MutableStateFlow(GoalFilter.ALL)
    private val _error = MutableStateFlow<String?>(null)
    private val _showDeleteConfirmation = MutableStateFlow<Goal?>(null)

    private val goalsWithProgressFlow: StateFlow<List<GoalWithProgress>> = getGoalProgressUseCase()
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = emptyList()
        )

    private val unallocatedAssetsFlow: StateFlow<List<UnallocatedAssetWarning>> = goalsWithProgressFlow
        .mapLatest {
            val statuses = allocationValidationService.getAllAssetAllocationStatuses()
            UnallocatedAssetsMapper.fromStatuses(statuses)
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = emptyList()
        )

    val uiState: StateFlow<GoalListUiState> = combine(
        goalsWithProgressFlow,
        unallocatedAssetsFlow,
        _selectedFilter,
        _error,
        _showDeleteConfirmation
    ) { goalsWithProgress, unallocatedAssets, filter, error, deleteConfirmation ->
        val filteredGoals = when (filter) {
            GoalFilter.ALL -> goalsWithProgress.filter { it.goal.lifecycleStatus != GoalLifecycleStatus.DELETED }
            GoalFilter.ACTIVE -> goalsWithProgress.filter { it.goal.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
            GoalFilter.FINISHED -> goalsWithProgress.filter { it.goal.lifecycleStatus == GoalLifecycleStatus.FINISHED }
            GoalFilter.CANCELLED -> goalsWithProgress.filter { it.goal.lifecycleStatus == GoalLifecycleStatus.CANCELLED }
            GoalFilter.DELETED -> goalsWithProgress.filter { it.goal.lifecycleStatus == GoalLifecycleStatus.DELETED }
        }

        GoalListUiState(
            goals = filteredGoals.sortedBy { it.goal.deadline },
            unallocatedAssets = unallocatedAssets,
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
