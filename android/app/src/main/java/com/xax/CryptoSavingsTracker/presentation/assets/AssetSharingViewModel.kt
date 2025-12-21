package com.xax.CryptoSavingsTracker.presentation.assets

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AddAllocationUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationValidationService
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
    private val addAllocationUseCase: AddAllocationUseCase
) : ViewModel() {

    private val assetId: String = checkNotNull(savedStateHandle["assetId"])

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
                    .sortedBy { it.goalName.lowercase() }

                AssetSharingUiState(
                    isLoading = false,
                    asset = asset,
                    totalBalance = status?.totalBalance ?: 0.0,
                    totalAllocated = status?.totalAllocated ?: 0.0,
                    unallocatedAmount = status?.unallocatedAmount ?: 0.0,
                    isOverAllocated = status?.isOverAllocated ?: false,
                    allocations = allocationRows,
                    activeGoals = activeGoals,
                    error = null,
                    showAddAllocationDialog = false,
                    selectedGoalId = null,
                    amountInput = "",
                    amountError = null,
                    isSaving = false
                )
            }.onSuccess { newState ->
                _uiState.value = newState
            }.onFailure { e ->
                _uiState.update { it.copy(isLoading = false, error = e.message ?: "Failed to load") }
            }
        }
    }

    fun showAddAllocation() {
        val state = _uiState.value
        val defaultGoalId = state.activeGoals.firstOrNull()?.id
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
}
