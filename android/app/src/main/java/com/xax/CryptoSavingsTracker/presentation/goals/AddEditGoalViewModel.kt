package com.xax.CryptoSavingsTracker.presentation.goals

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.ReminderFrequency
import com.xax.CryptoSavingsTracker.domain.usecase.goal.AddGoalUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.UpdateGoalUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import javax.inject.Inject

/**
 * UI State for Add/Edit Goal screen
 */
data class AddEditGoalUiState(
    val isLoading: Boolean = false,
    val isEditMode: Boolean = false,
    val goalId: String? = null,
    val name: String = "",
    val currency: String = "USD",
    val targetAmount: String = "",
    val deadline: LocalDate = LocalDate.now().plusMonths(6),
    val startDate: LocalDate = LocalDate.now(),
    val reminderEnabled: Boolean = false,
    val reminderFrequency: ReminderFrequency? = null,
    val notes: String = "",
    val nameError: String? = null,
    val targetAmountError: String? = null,
    val deadlineError: String? = null,
    val isSaved: Boolean = false,
    val error: String? = null
)

/**
 * Available currencies for selection
 */
val availableCurrencies = listOf(
    "USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "CNY", "INR", "BRL"
)

/**
 * ViewModel for Add/Edit Goal screen
 */
@HiltViewModel
class AddEditGoalViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val addGoalUseCase: AddGoalUseCase,
    private val updateGoalUseCase: UpdateGoalUseCase,
    private val getGoalByIdUseCase: GetGoalByIdUseCase
) : ViewModel() {

    private val goalId: String? = savedStateHandle["goalId"]

    private val _uiState = MutableStateFlow(AddEditGoalUiState())
    val uiState: StateFlow<AddEditGoalUiState> = _uiState.asStateFlow()

    private var originalGoal: Goal? = null

    init {
        goalId?.let { id ->
            loadGoal(id)
        }
    }

    private fun loadGoal(id: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            val goal = getGoalByIdUseCase(id)
            if (goal != null) {
                originalGoal = goal
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        isEditMode = true,
                        goalId = goal.id,
                        name = goal.name,
                        currency = goal.currency,
                        targetAmount = goal.targetAmount.toString(),
                        deadline = goal.deadline,
                        startDate = goal.startDate,
                        reminderEnabled = goal.reminderEnabled,
                        reminderFrequency = goal.reminderFrequency,
                        notes = goal.notes ?: ""
                    )
                }
            } else {
                _uiState.update {
                    it.copy(isLoading = false, error = "Goal not found")
                }
            }
        }
    }

    fun updateName(name: String) {
        _uiState.update { it.copy(name = name, nameError = null) }
    }

    fun updateCurrency(currency: String) {
        _uiState.update { it.copy(currency = currency) }
    }

    fun updateTargetAmount(amount: String) {
        // Only allow valid numeric input
        if (amount.isEmpty() || amount.matches(Regex("^\\d*\\.?\\d*$"))) {
            _uiState.update { it.copy(targetAmount = amount, targetAmountError = null) }
        }
    }

    fun updateDeadline(deadline: LocalDate) {
        _uiState.update { it.copy(deadline = deadline, deadlineError = null) }
    }

    fun updateStartDate(startDate: LocalDate) {
        _uiState.update { it.copy(startDate = startDate) }
    }

    fun updateReminderEnabled(enabled: Boolean) {
        _uiState.update {
            it.copy(
                reminderEnabled = enabled,
                reminderFrequency = if (enabled && it.reminderFrequency == null) {
                    ReminderFrequency.WEEKLY
                } else if (!enabled) {
                    null
                } else {
                    it.reminderFrequency
                }
            )
        }
    }

    fun updateReminderFrequency(frequency: ReminderFrequency?) {
        _uiState.update { it.copy(reminderFrequency = frequency) }
    }

    fun updateNotes(notes: String) {
        _uiState.update { it.copy(notes = notes) }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun saveGoal() {
        val state = _uiState.value

        // Validation
        var hasErrors = false

        if (state.name.isBlank()) {
            _uiState.update { it.copy(nameError = "Name is required") }
            hasErrors = true
        }

        val targetAmount = state.targetAmount.toDoubleOrNull()
        if (targetAmount == null || targetAmount <= 0) {
            _uiState.update { it.copy(targetAmountError = "Enter a valid amount greater than 0") }
            hasErrors = true
        }

        if (state.deadline.isBefore(state.startDate)) {
            _uiState.update { it.copy(deadlineError = "Deadline must be after start date") }
            hasErrors = true
        }

        if (hasErrors) return

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            val result = if (state.isEditMode && originalGoal != null) {
                val updatedGoal = originalGoal!!.copy(
                    name = state.name.trim(),
                    currency = state.currency,
                    targetAmount = targetAmount!!,
                    deadline = state.deadline,
                    startDate = state.startDate,
                    reminderEnabled = state.reminderEnabled,
                    reminderFrequency = if (state.reminderEnabled) state.reminderFrequency else null,
                    notes = state.notes.trim().takeIf { it.isNotEmpty() }
                )
                updateGoalUseCase(updatedGoal)
            } else {
                addGoalUseCase(
                    name = state.name.trim(),
                    currency = state.currency,
                    targetAmount = targetAmount!!,
                    deadline = state.deadline,
                    startDate = state.startDate,
                    reminderEnabled = state.reminderEnabled,
                    reminderFrequency = if (state.reminderEnabled) state.reminderFrequency else null,
                    notes = state.notes.trim().takeIf { it.isNotEmpty() }
                )
            }

            result.fold(
                onSuccess = {
                    _uiState.update { it.copy(isLoading = false, isSaved = true) }
                },
                onFailure = { e ->
                    _uiState.update {
                        it.copy(isLoading = false, error = e.message ?: "Failed to save goal")
                    }
                }
            )
        }
    }
}
