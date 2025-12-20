package com.xax.CryptoSavingsTracker.presentation.allocations

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.DeleteAllocationUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.UpdateAllocationUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject
import kotlin.math.max

data class EditAllocationUiState(
    val goal: Goal? = null,
    val allocation: Allocation? = null,
    val asset: Asset? = null,
    val assetBalance: Double = 0.0,
    val availableBalance: Double = 0.0,
    val amount: String = "",
    val amountError: String? = null,
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val error: String? = null,
    val isSaved: Boolean = false,
    val showDeleteConfirmation: Boolean = false
)

@HiltViewModel
class EditAllocationViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val goalRepository: GoalRepository,
    private val allocationRepository: AllocationRepository,
    private val assetRepository: AssetRepository,
    private val transactionRepository: TransactionRepository,
    private val updateAllocationUseCase: UpdateAllocationUseCase,
    private val deleteAllocationUseCase: DeleteAllocationUseCase
) : ViewModel() {

    private val goalId: String = checkNotNull(savedStateHandle["goalId"])
    private val allocationId: String = checkNotNull(savedStateHandle["allocationId"])

    private val _uiState = MutableStateFlow(EditAllocationUiState())
    val uiState: StateFlow<EditAllocationUiState> = _uiState.asStateFlow()

    init {
        loadData()
    }

    fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val goal = goalRepository.getGoalById(goalId)
                val allocation = allocationRepository.getAllocationById(allocationId)

                if (allocation == null) {
                    _uiState.update { it.copy(goal = goal, isLoading = false, error = "Allocation not found") }
                    return@launch
                }

                val asset = assetRepository.getAssetById(allocation.assetId)
                val assetBalance = transactionRepository.getManualBalanceForAsset(allocation.assetId)
                val otherAllocations = allocationRepository.getAllocationsForAsset(allocation.assetId)
                    .filter { it.id != allocation.id }
                val availableBalance = assetBalance - otherAllocations.sumOf { it.amount }

                _uiState.update {
                    it.copy(
                        goal = goal,
                        allocation = allocation,
                        asset = asset,
                        assetBalance = assetBalance,
                        availableBalance = max(0.0, availableBalance),
                        amount = String.format("%.2f", allocation.amount),
                        isLoading = false
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(isLoading = false, error = e.message ?: "Failed to load allocation")
                }
            }
        }
    }

    fun updateAmount(value: String) {
        _uiState.update { it.copy(amount = value, amountError = null) }
    }

    fun setMaxAmount() {
        val maxAmount = _uiState.value.availableBalance
        _uiState.update { it.copy(amount = String.format("%.2f", maxAmount), amountError = null) }
    }

    fun save() {
        val allocation = _uiState.value.allocation ?: return
        val amountValue = _uiState.value.amount.toDoubleOrNull()
        if (amountValue == null || amountValue <= 0) {
            _uiState.update { it.copy(amountError = "Please enter a valid amount") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null) }
            updateAllocationUseCase(allocation.copy(amount = amountValue)).fold(
                onSuccess = {
                    _uiState.update { it.copy(isSaving = false, isSaved = true) }
                },
                onFailure = { e ->
                    _uiState.update { it.copy(isSaving = false, error = e.message ?: "Failed to update allocation") }
                }
            )
        }
    }

    fun requestDelete() {
        _uiState.update { it.copy(showDeleteConfirmation = true) }
    }

    fun dismissDelete() {
        _uiState.update { it.copy(showDeleteConfirmation = false) }
    }

    fun confirmDelete() {
        val allocation = _uiState.value.allocation ?: return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null) }
            deleteAllocationUseCase(
                allocationId = allocation.id,
                assetId = allocation.assetId,
                goalId = allocation.goalId
            ).fold(
                onSuccess = {
                    _uiState.update { it.copy(isSaving = false, isSaved = true, showDeleteConfirmation = false) }
                },
                onFailure = { e ->
                    _uiState.update {
                        it.copy(
                            isSaving = false,
                            showDeleteConfirmation = false,
                            error = e.message ?: "Failed to delete allocation"
                        )
                    }
                }
            )
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
