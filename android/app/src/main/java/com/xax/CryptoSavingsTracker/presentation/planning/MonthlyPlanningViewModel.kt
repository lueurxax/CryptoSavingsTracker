package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.MonthlyRequirement
import com.xax.CryptoSavingsTracker.domain.model.RequirementStatus
import com.xax.CryptoSavingsTracker.domain.usecase.planning.MonthlyPlanningService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI State for Monthly Planning screen
 */
data class MonthlyPlanningUiState(
    val requirements: List<MonthlyRequirement> = emptyList(),
    val totalRequired: Double = 0.0,
    val displayCurrency: String = "USD",
    val paymentDay: Int = 1,
    val isLoading: Boolean = true,
    val error: String? = null,
    val showSettingsDialog: Boolean = false
) {
    val completedCount: Int
        get() = requirements.count { it.status == RequirementStatus.COMPLETED }

    val activeCount: Int
        get() = requirements.count { it.status != RequirementStatus.COMPLETED }

    val criticalCount: Int
        get() = requirements.count { it.status == RequirementStatus.CRITICAL }

    val attentionCount: Int
        get() = requirements.count { it.status == RequirementStatus.ATTENTION }
}

/**
 * ViewModel for Monthly Planning screen.
 */
@HiltViewModel
class MonthlyPlanningViewModel @Inject constructor(
    private val monthlyPlanningService: MonthlyPlanningService
) : ViewModel() {

    private val _uiState = MutableStateFlow(MonthlyPlanningUiState())
    val uiState: StateFlow<MonthlyPlanningUiState> = _uiState.asStateFlow()

    init {
        loadData()
    }

    fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            try {
                val requirements = monthlyPlanningService.calculateMonthlyRequirements()
                val displayCurrency = "USD" // TODO: Get from user settings
                val totalRequired = monthlyPlanningService.calculateTotalRequired(displayCurrency)
                val paymentDay = monthlyPlanningService.paymentDay

                _uiState.update {
                    it.copy(
                        requirements = requirements,
                        totalRequired = totalRequired,
                        displayCurrency = displayCurrency,
                        paymentDay = paymentDay,
                        isLoading = false
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load monthly requirements"
                    )
                }
            }
        }
    }

    fun showSettings() {
        _uiState.update { it.copy(showSettingsDialog = true) }
    }

    fun dismissSettings() {
        _uiState.update { it.copy(showSettingsDialog = false) }
    }

    fun updatePaymentDay(day: Int) {
        monthlyPlanningService.paymentDay = day
        _uiState.update { it.copy(paymentDay = day, showSettingsDialog = false) }
        loadData() // Recalculate with new payment day
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
