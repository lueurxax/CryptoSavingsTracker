package com.xax.CryptoSavingsTracker.presentation.assets

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AddAllocationUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationValidationService
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.UpdateAllocationUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionContributionCalculatorUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionSession
import com.xax.CryptoSavingsTracker.domain.usecase.execution.GetExecutionSessionUseCase
import com.xax.CryptoSavingsTracker.presentation.common.AmountFormatters
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class AssetSharingAllocationRow(
    val allocationId: String,
    val goalId: String,
    val goalName: String,
    val amount: Double
)

data class AssetSharingUiState(
    val isLoading: Boolean = true,
    val asset: Asset? = null,
    val totalBalance: Double = 0.0,
    val totalAllocated: Double = 0.0,
    val unallocatedAmount: Double = 0.0,
    val isOverAllocated: Boolean = false,
    val allocations: List<AssetSharingAllocationRow> = emptyList(),
    val activeGoals: List<Goal> = emptyList(),
    val currentGoalId: String? = null,
    val closeMonthSuggestions: Map<String, Double> = emptyMap(),
    val conversionWarning: String? = null,
    val closeMonthWarning: String? = null,
    val error: String? = null,
    val showAddAllocationDialog: Boolean = false,
    val selectedGoalId: String? = null,
    val amountInput: String = "",
    val amountError: String? = null,
    val isSaving: Boolean = false
)

@HiltViewModel
class AssetSharingViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val assetRepository: AssetRepository,
    private val goalRepository: GoalRepository,
    private val allocationRepository: AllocationRepository,
    private val allocationValidationService: AllocationValidationService,
    private val addAllocationUseCase: AddAllocationUseCase,
    private val updateAllocationUseCase: UpdateAllocationUseCase,
    private val executionSessionUseCase: GetExecutionSessionUseCase,
    private val executionContributionCalculator: ExecutionContributionCalculatorUseCase
) : ViewModel() {

    private val assetId: String = checkNotNull(savedStateHandle["assetId"])
    private val currentGoalId: String? = savedStateHandle.get<String>("goalId")
    private val shouldPrefillCloseMonth: Boolean = savedStateHandle.get<Boolean>("prefillCloseMonth") ?: false
    private var hasAppliedPrefill = false
    private var pendingCloseMonthWarning: String? = null

    private val _uiState = MutableStateFlow(AssetSharingUiState())
    val uiState: StateFlow<AssetSharingUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            runCatching {
                val asset = assetRepository.getAssetById(assetId)
                val status = allocationValidationService.getAssetAllocationStatus(assetId)
                val allocations = allocationRepository.getAllocationsForAsset(assetId)
                val allGoals = goalRepository.getAllGoals().first()
                val activeGoals = allGoals.filter { it.lifecycleStatus.rawValue == "active" }
                val sortedActiveGoals = activeGoals.sortedWith(
                    compareBy<Goal> { if (it.id == currentGoalId) 0 else 1 }
                        .thenBy { it.name.lowercase() }
                )

                val goalNameById = allGoals.associate { it.id to it.name }
                val allocationRows = allocations
                    .map { allocation ->
                        AssetSharingAllocationRow(
                            allocationId = allocation.id,
                            goalId = allocation.goalId,
                            goalName = goalNameById[allocation.goalId] ?: "Unknown Goal",
                            amount = allocation.amount
                        )
                    }
                    .sortedWith(
                        compareBy<AssetSharingAllocationRow> { if (it.goalId == currentGoalId) 0 else 1 }
                            .thenBy { it.goalName.lowercase() }
                    )

                val session = executionSessionUseCase.currentExecuting().first()
                val (closeMonthSuggestions, hasConversionWarning) = buildCloseMonthSuggestions(session, asset)

                AssetSharingUiState(
                    isLoading = false,
                    asset = asset,
                    totalBalance = status?.totalBalance ?: 0.0,
                    totalAllocated = status?.totalAllocated ?: 0.0,
                    unallocatedAmount = status?.unallocatedAmount ?: 0.0,
                    isOverAllocated = status?.isOverAllocated ?: false,
                    allocations = allocationRows,
                    activeGoals = sortedActiveGoals,
                    currentGoalId = currentGoalId,
                    closeMonthSuggestions = closeMonthSuggestions,
                    conversionWarning = if (hasConversionWarning) {
                        "Some goals could not be converted with the current exchange rates."
                    } else {
                        null
                    },
                    closeMonthWarning = pendingCloseMonthWarning,
                    error = null,
                    showAddAllocationDialog = false,
                    selectedGoalId = null,
                    amountInput = "",
                    amountError = null,
                    isSaving = false
                )
            }.onSuccess { newState ->
                pendingCloseMonthWarning = null
                _uiState.value = newState
                if (shouldPrefillCloseMonth && !hasAppliedPrefill && currentGoalId != null && newState.asset != null) {
                    hasAppliedPrefill = true
                    addCloseMonthAllocation(currentGoalId)
                }
            }.onFailure { e ->
                _uiState.update { it.copy(isLoading = false, error = e.message ?: "Failed to load") }
            }
        }
    }

    fun showAddAllocation() {
        val state = _uiState.value
        val defaultGoalId = state.currentGoalId ?: state.activeGoals.firstOrNull()?.id
        _uiState.update {
            it.copy(
                showAddAllocationDialog = true,
                selectedGoalId = defaultGoalId,
                amountInput = "",
                amountError = null
            )
        }
    }

    fun dismissAddAllocation() {
        _uiState.update { it.copy(showAddAllocationDialog = false, amountError = null) }
    }

    fun selectGoal(goalId: String) {
        _uiState.update { it.copy(selectedGoalId = goalId, amountError = null) }
    }

    fun setAmountInput(value: String) {
        if (value.isEmpty() || value.matches(Regex("^\\d*\\.?\\d*$"))) {
            _uiState.update { it.copy(amountInput = value, amountError = null) }
        }
    }

    fun setMaxAmount() {
        val max = _uiState.value.unallocatedAmount
        _uiState.update { it.copy(amountInput = AmountFormatters.formatInputAmount(max, isCrypto = _uiState.value.asset?.isCryptoAsset == true)) }
    }

    fun saveAllocation() {
        val state = _uiState.value
        val goalId = state.selectedGoalId ?: run {
            _uiState.update { it.copy(amountError = "Select a goal") }
            return
        }

        val amount = state.amountInput.toDoubleOrNull()
        if (amount == null || amount <= 0.0) {
            _uiState.update { it.copy(amountError = "Enter a valid amount") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, amountError = null) }
            addAllocationUseCase(assetId = assetId, goalId = goalId, amount = amount)
                .onSuccess {
                    _uiState.update { it.copy(isSaving = false, showAddAllocationDialog = false) }
                    refresh()
                }
                .onFailure { e ->
                    _uiState.update { it.copy(isSaving = false, amountError = e.message ?: "Failed to save") }
                }
        }
    }

    fun addCloseMonthAllocation(goalId: String) {
        val suggestion = _uiState.value.closeMonthSuggestions[goalId]
        if (suggestion == null || suggestion <= 0.0) {
            val warning = if (_uiState.value.conversionWarning != null) {
                "Unable to convert close-month amount for this goal."
            } else {
                "No remaining amount to close for this goal."
            }
            _uiState.update { it.copy(closeMonthWarning = warning) }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, closeMonthWarning = null) }

            val status = allocationValidationService.getAssetAllocationStatus(assetId)
            val available = status?.unallocatedAmount ?: 0.0
            if (available <= 0.0) {
                _uiState.update {
                    it.copy(
                        isSaving = false,
                        closeMonthWarning = "No available balance to allocate."
                    )
                }
                return@launch
            }

            val existing = allocationRepository.getAllocationByAssetAndGoal(assetId, goalId)
            val increment = suggestion.coerceAtMost(available)
            if (increment <= 0.0) {
                _uiState.update {
                    it.copy(
                        isSaving = false,
                        closeMonthWarning = "No available balance to allocate."
                    )
                }
                return@launch
            }

            val newAmount = (existing?.amount ?: 0.0) + increment
            val result = if (existing != null) {
                updateAllocationUseCase(existing.copy(amount = newAmount))
            } else {
                addAllocationUseCase(assetId = assetId, goalId = goalId, amount = newAmount)
            }

            result.onSuccess {
                if (increment < suggestion) {
                    pendingCloseMonthWarning = "Allocation was limited by available balance."
                }
                _uiState.update { it.copy(isSaving = false) }
                refresh()
            }.onFailure { e ->
                _uiState.update {
                    it.copy(
                        isSaving = false,
                        closeMonthWarning = e.message ?: "Failed to update allocation."
                    )
                }
            }
        }
    }

    private suspend fun buildCloseMonthSuggestions(
        session: ExecutionSession?,
        asset: Asset?
    ): Pair<Map<String, Double>, Boolean> {
        if (session == null || asset == null) return emptyMap<String, Double>() to false

        val suggestions = mutableMapOf<String, Double>()
        var hasWarning = false

        for (goal in session.goals) {
            val remaining = executionContributionCalculator.remainingToClose(goal)
            if (remaining <= 0.0) continue

            val converted = executionContributionCalculator.convertAmount(
                amount = remaining,
                from = goal.snapshot.currency,
                to = asset.currency
            )

            if (converted != null && converted > 0.0) {
                suggestions[goal.snapshot.goalId] = converted
            } else {
                hasWarning = true
            }
        }

        return suggestions to hasWarning
    }
}
