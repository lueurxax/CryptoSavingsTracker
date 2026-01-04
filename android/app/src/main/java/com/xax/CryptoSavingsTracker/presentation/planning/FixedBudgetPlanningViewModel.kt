package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.CompletionBehavior
import com.xax.CryptoSavingsTracker.domain.model.FeasibilityResult
import com.xax.CryptoSavingsTracker.domain.model.FeasibilitySuggestion
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.MonthlyPlanningSettings
import com.xax.CryptoSavingsTracker.domain.model.PlanningMode
import com.xax.CryptoSavingsTracker.domain.model.ScheduledGoalBlock
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.usecase.planning.FixedBudgetPlanningUseCase
import kotlinx.coroutines.flow.first
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import javax.inject.Inject

/**
 * Navigation events emitted by the FixedBudgetPlanning ViewModel.
 */
sealed class FixedBudgetNavEvent {
    data class EditGoalDeadline(val goalId: String, val goalName: String, val suggestedMonths: Int) : FixedBudgetNavEvent()
    data class EditGoalTarget(val goalId: String, val goalName: String, val suggestedAmount: Double) : FixedBudgetNavEvent()
}

/**
 * Pending quick fix that needs confirmation.
 */
data class PendingQuickFix(
    val suggestion: FeasibilitySuggestion,
    val goalId: String,
    val goalName: String
) {
    val title: String
        get() = when (suggestion) {
            is FeasibilitySuggestion.ExtendDeadline ->
                "Extend $goalName by ${suggestion.byMonths} month${if (suggestion.byMonths == 1) "" else "s"}"
            is FeasibilitySuggestion.ReduceTarget ->
                "Reduce $goalName target"
            is FeasibilitySuggestion.IncreaseBudget ->
                suggestion.title
        }

    val description: String
        get() = when (suggestion) {
            is FeasibilitySuggestion.ExtendDeadline ->
                "This will move the deadline forward by ${suggestion.byMonths} month${if (suggestion.byMonths == 1) "" else "s"}, giving you more time to reach this goal."
            is FeasibilitySuggestion.ReduceTarget ->
                "This will lower the target amount, making the goal achievable with your current budget."
            is FeasibilitySuggestion.IncreaseBudget ->
                "This will increase your monthly budget."
        }

    val actionButtonLabel: String
        get() = when (suggestion) {
            is FeasibilitySuggestion.ExtendDeadline -> "Extend Deadline"
            is FeasibilitySuggestion.ReduceTarget -> "Reduce Target"
            is FeasibilitySuggestion.IncreaseBudget -> "Increase Budget"
        }
}

/**
 * ViewModel for Fixed Budget Planning screen.
 * Manages state and business logic for the fixed budget planning mode.
 */
@HiltViewModel
class FixedBudgetPlanningViewModel @Inject constructor(
    private val fixedBudgetPlanningUseCase: FixedBudgetPlanningUseCase,
    private val goalRepository: GoalRepository,
    private val settings: MonthlyPlanningSettings
) : ViewModel() {

    private val _uiState = MutableStateFlow(FixedBudgetPlanningUiState())
    val uiState: StateFlow<FixedBudgetPlanningUiState> = _uiState.asStateFlow()

    private val _navEvents = MutableSharedFlow<FixedBudgetNavEvent>()
    val navEvents: SharedFlow<FixedBudgetNavEvent> = _navEvents.asSharedFlow()

    private var goals: List<Goal> = emptyList()

    init {
        loadSettings()
    }

    private fun loadSettings() {
        _uiState.update { state ->
            state.copy(
                monthlyBudget = settings.monthlyBudget ?: 0.0,
                editingBudget = settings.monthlyBudget ?: 0.0,
                currency = settings.budgetCurrency,
                completionBehavior = settings.completionBehavior,
                showSetupSheet = !settings.hasCompletedFixedBudgetOnboarding && (settings.monthlyBudget ?: 0.0) == 0.0
            )
        }
    }

    /**
     * Load goals from repository and refresh calculations.
     */
    fun loadGoalsFromRepository() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            try {
                // Get active goals only
                val allGoals = goalRepository.getAllGoals().first()
                val activeGoals = allGoals.filter { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
                goals = activeGoals
                refreshCalculations()
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message ?: "Failed to load goals") }
            } finally {
                _uiState.update { it.copy(isLoading = false) }
            }
        }
    }

    /**
     * Load goals and refresh calculations.
     */
    fun loadGoals(goals: List<Goal>) {
        this.goals = goals
        viewModelScope.launch {
            refreshCalculations()
        }
    }

    /**
     * Refresh all calculations based on current goals and budget.
     */
    private suspend fun refreshCalculations() {
        if (goals.isEmpty()) return

        val oldBlockCount = _uiState.value.scheduleBlocks.size
        _uiState.update { it.copy(isRecalculating = true) }

        try {
            val currency = _uiState.value.currency
            val budget = _uiState.value.monthlyBudget

            // Calculate minimum and feasibility
            val minimumRequired = fixedBudgetPlanningUseCase.calculateMinimumBudget(goals, currency)
            val feasibilityResult = fixedBudgetPlanningUseCase.checkFeasibility(goals, budget, currency)

            _uiState.update { state ->
                state.copy(
                    minimumRequired = minimumRequired,
                    feasibilityResult = feasibilityResult
                )
            }

            // Generate schedule if budget is set
            if (budget > 0) {
                val plan = fixedBudgetPlanningUseCase.generateSchedule(goals, budget, currency)
                val scheduleBlocks = fixedBudgetPlanningUseCase.buildTimelineBlocks(plan, goals)
                val currentFocus = buildCurrentFocus(plan.schedule.firstOrNull()?.contributions?.firstOrNull())

                _uiState.update { state ->
                    state.copy(
                        scheduleBlocks = scheduleBlocks,
                        schedulePayments = plan.schedule,
                        goalRemainingById = plan.goalRemainingById,
                        currentFocusGoal = currentFocus,
                        currentPaymentNumber = 1
                    )
                }

                // Show toast if schedule changed
                if (scheduleBlocks.size != oldBlockCount && oldBlockCount > 0) {
                    showRecalculationToast("Schedule updated")
                }
            } else {
                _uiState.update { state ->
                    state.copy(
                        scheduleBlocks = emptyList(),
                        schedulePayments = emptyList(),
                        goalRemainingById = emptyMap(),
                        currentFocusGoal = null
                    )
                }
            }
        } finally {
            _uiState.update { it.copy(isRecalculating = false) }
        }
    }

    private fun showRecalculationToast(message: String) {
        _uiState.update { it.copy(toastMessage = message) }
    }

    fun clearToast() {
        _uiState.update { it.copy(toastMessage = null) }
    }

    private fun buildCurrentFocus(
        contribution: com.xax.CryptoSavingsTracker.domain.model.GoalContribution?
    ): CurrentFocusInfo? {
        if (contribution == null) return null

        val goal = goals.find { it.id == contribution.goalId }
        val plan = viewModelScope.let {
            // Find estimated completion from schedule
            val budget = _uiState.value.monthlyBudget
            val currency = _uiState.value.currency
            if (budget > 0) {
                // We need to get the plan again to find completion date
                // This is a simplified approach - in production, store the plan in state
                null
            } else null
        }

        return CurrentFocusInfo(
            goalName = contribution.goalName,
            emoji = goal?.emoji,
            progress = if (goal != null && goal.targetAmount > 0) {
                contribution.runningTotal / goal.targetAmount
            } else 0.0,
            contributed = contribution.runningTotal,
            target = goal?.targetAmount ?: 0.0,
            estimatedCompletion = null // Would need to track from plan
        )
    }

    // MARK: - UI Actions

    fun showBudgetEditor() {
        _uiState.update { it.copy(showBudgetEditor = true) }
    }

    fun hideBudgetEditor() {
        _uiState.update { it.copy(showBudgetEditor = false) }
    }

    fun updateEditingBudget(budget: Double) {
        _uiState.update { it.copy(editingBudget = budget) }
    }

    fun updateCompletionBehavior(behavior: CompletionBehavior) {
        _uiState.update { it.copy(completionBehavior = behavior) }
    }

    fun saveBudget() {
        val newBudget = _uiState.value.editingBudget
        settings.monthlyBudget = newBudget

        _uiState.update { state ->
            state.copy(
                monthlyBudget = newBudget,
                showBudgetEditor = false
            )
        }

        viewModelScope.launch {
            refreshCalculations()
        }
    }

    fun applySuggestion(suggestion: FeasibilitySuggestion) {
        when (suggestion) {
            is FeasibilitySuggestion.IncreaseBudget -> {
                settings.monthlyBudget = suggestion.to
                _uiState.update { state ->
                    state.copy(
                        monthlyBudget = suggestion.to,
                        editingBudget = suggestion.to
                    )
                }
                viewModelScope.launch {
                    refreshCalculations()
                }
            }
            is FeasibilitySuggestion.ExtendDeadline -> {
                // Show confirmation dialog
                _uiState.update { state ->
                    state.copy(
                        pendingQuickFix = PendingQuickFix(
                            suggestion = suggestion,
                            goalId = suggestion.goalId,
                            goalName = suggestion.goalName
                        )
                    )
                }
            }
            is FeasibilitySuggestion.ReduceTarget -> {
                // Show confirmation dialog
                _uiState.update { state ->
                    state.copy(
                        pendingQuickFix = PendingQuickFix(
                            suggestion = suggestion,
                            goalId = suggestion.goalId,
                            goalName = suggestion.goalName
                        )
                    )
                }
            }
        }
    }

    fun dismissQuickFix() {
        _uiState.update { it.copy(pendingQuickFix = null) }
    }

    fun confirmQuickFix() {
        val quickFix = _uiState.value.pendingQuickFix ?: return
        _uiState.update { it.copy(pendingQuickFix = null) }

        viewModelScope.launch {
            val goal = goals.find { it.id == quickFix.goalId } ?: return@launch

            when (val suggestion = quickFix.suggestion) {
                is FeasibilitySuggestion.ExtendDeadline -> {
                    // Update goal deadline
                    val newDeadline = goal.deadline.plusMonths(suggestion.byMonths.toLong())
                    val updatedGoal = goal.copy(deadline = newDeadline)
                    goalRepository.updateGoal(updatedGoal)

                    // Refresh goals list
                    val allGoals = goalRepository.getAllGoals().first()
                    goals = allGoals.filter { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
                    refreshCalculations()
                }

                is FeasibilitySuggestion.ReduceTarget -> {
                    // Update goal target
                    val updatedGoal = goal.copy(targetAmount = suggestion.to)
                    goalRepository.updateGoal(updatedGoal)

                    // Refresh goals list
                    val allGoals = goalRepository.getAllGoals().first()
                    goals = allGoals.filter { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
                    refreshCalculations()
                }

                is FeasibilitySuggestion.IncreaseBudget -> {
                    // Already handled above
                }
            }
        }
    }

    fun completeSetup() {
        val newBudget = _uiState.value.editingBudget
        val newBehavior = _uiState.value.completionBehavior

        settings.monthlyBudget = newBudget
        settings.completionBehavior = newBehavior
        settings.hasCompletedFixedBudgetOnboarding = true

        _uiState.update { state ->
            state.copy(
                monthlyBudget = newBudget,
                showSetupSheet = false
            )
        }

        viewModelScope.launch {
            refreshCalculations()
        }
    }

    fun cancelSetup() {
        settings.planningMode = PlanningMode.PER_GOAL
        _uiState.update { it.copy(showSetupSheet = false) }
    }
}

/**
 * UI state for Fixed Budget Planning screen.
 */
data class FixedBudgetPlanningUiState(
    val monthlyBudget: Double = 0.0,
    val editingBudget: Double = 0.0,
    val currency: String = "USD",
    val minimumRequired: Double = 0.0,
    val feasibilityResult: FeasibilityResult = FeasibilityResult.EMPTY,
    val scheduleBlocks: List<ScheduledGoalBlock> = emptyList(),
    val schedulePayments: List<com.xax.CryptoSavingsTracker.domain.model.ScheduledPayment> = emptyList(),
    val goalRemainingById: Map<String, Double> = emptyMap(),
    val currentFocusGoal: CurrentFocusInfo? = null,
    val currentPaymentNumber: Int = 1,
    val completionBehavior: CompletionBehavior = CompletionBehavior.FINISH_FASTER,
    val showBudgetEditor: Boolean = false,
    val showSetupSheet: Boolean = false,
    val pendingQuickFix: PendingQuickFix? = null,
    val isLoading: Boolean = false,
    val isRecalculating: Boolean = false,
    val toastMessage: String? = null,
    val error: String? = null
)

/**
 * Information about the current goal being funded.
 */
data class CurrentFocusInfo(
    val goalName: String,
    val emoji: String?,
    val progress: Double,
    val contributed: Double,
    val target: Double,
    val estimatedCompletion: LocalDate?
)
