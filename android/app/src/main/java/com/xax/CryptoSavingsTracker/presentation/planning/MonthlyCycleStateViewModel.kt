package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.PlanningSource
import com.xax.CryptoSavingsTracker.domain.model.UiCycleState
import com.xax.CryptoSavingsTracker.domain.usecase.execution.MonthlyCycleStateResolverUseCase
import com.xax.CryptoSavingsTracker.domain.util.MonthLabelUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch

@HiltViewModel
class MonthlyCycleStateViewModel @Inject constructor(
    private val resolverUseCase: MonthlyCycleStateResolverUseCase
) : ViewModel() {
    private val _state = MutableStateFlow<UiCycleState>(
        UiCycleState.Planning(
            monthLabel = MonthLabelUtils.nowUtc(),
            source = PlanningSource.CURRENT_MONTH
        )
    )
    val state: StateFlow<UiCycleState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            resolverUseCase.observeState()
                .catch {
                    _state.value = UiCycleState.Conflict(
                        monthLabel = null,
                        reason = com.xax.CryptoSavingsTracker.domain.model.CycleConflictReason.INVALID_MONTH_LABEL
                    )
                }
                .collect { resolved ->
                    _state.value = resolved
                }
        }
    }
}
