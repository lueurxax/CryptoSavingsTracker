package com.xax.CryptoSavingsTracker.presentation.allocations

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.DeleteAllocationUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.GetAllocationsForGoalUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject
import kotlin.math.abs

/**
 * Data class for displaying an allocation with its asset details.
 */
data class AllocationWithDetails(
    val allocation: Allocation,
    val asset: Asset?,
    val assetBalance: Double,          // Current manual balance
    val assetTotalAllocated: Double,   // Total allocated from this asset across all goals
    val assetDisplayName: String,
    val isAssetOverAllocated: Boolean  // True if asset's total allocations exceed balance
) {
    val fundedAmount: Double
        get() = minOf(allocation.amount, assetBalance)

    val isUnderfunded: Boolean
        get() = allocation.amount > assetBalance
}

/**
 * UI State for Allocation List screen
 */
data class AllocationListUiState(
    val goal: Goal? = null,
    val allocations: List<AllocationWithDetails> = emptyList(),
    val totalAllocated: Double = 0.0,
    val totalFunded: Double = 0.0,
    val hasOverAllocatedAssets: Boolean = false,
    val isLoading: Boolean = true,
    val error: String? = null,
    val showDeleteConfirmation: Allocation? = null
)

/**
 * ViewModel for managing allocations for a specific goal.
 */
@HiltViewModel
class AllocationListViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val getAllocationsForGoalUseCase: GetAllocationsForGoalUseCase,
    private val deleteAllocationUseCase: DeleteAllocationUseCase,
    private val goalRepository: GoalRepository,
    private val assetRepository: AssetRepository,
    private val allocationRepository: AllocationRepository,
    private val transactionRepository: TransactionRepository
) : ViewModel() {

    private val goalId: String = checkNotNull(savedStateHandle["goalId"])

    private val _error = MutableStateFlow<String?>(null)
    private val _showDeleteConfirmation = MutableStateFlow<Allocation?>(null)
    private val _allocationsWithDetails = MutableStateFlow<List<AllocationWithDetails>>(emptyList())

    init {
        loadAllocationsWithDetails()
    }

    val uiState: StateFlow<AllocationListUiState> = combine(
        goalRepository.getGoalByIdFlow(goalId),
        _allocationsWithDetails,
        _error,
        _showDeleteConfirmation
    ) { goal, allocations, error, deleteConfirmation ->
        AllocationListUiState(
            goal = goal,
            allocations = allocations,
            totalAllocated = allocations.sumOf { it.allocation.amount },
            totalFunded = allocations.sumOf { it.fundedAmount },
            hasOverAllocatedAssets = allocations.any { it.isAssetOverAllocated },
            isLoading = false,
            error = error,
            showDeleteConfirmation = deleteConfirmation
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = AllocationListUiState()
    )

    private fun loadAllocationsWithDetails() {
        viewModelScope.launch {
            getAllocationsForGoalUseCase(goalId).collect { allocations ->
                val withDetails = allocations.map { allocation ->
                    val asset = assetRepository.getAssetById(allocation.assetId)
                    val balance = transactionRepository.getManualBalanceForAsset(allocation.assetId)

                    // Get total allocations for this asset across all goals
                    val allAssetAllocations = allocationRepository.getAllocationsForAsset(allocation.assetId)
                    val totalAllocatedFromAsset = allAssetAllocations.sumOf { it.amount }
                    val isOverAllocated = totalAllocatedFromAsset > balance + 0.0000001

                    AllocationWithDetails(
                        allocation = allocation,
                        asset = asset,
                        assetBalance = balance,
                        assetTotalAllocated = totalAllocatedFromAsset,
                        assetDisplayName = asset?.displayName() ?: "Unknown Asset",
                        isAssetOverAllocated = isOverAllocated
                    )
                }
                _allocationsWithDetails.value = withDetails
            }
        }
    }

    fun requestDeleteAllocation(allocation: Allocation) {
        _showDeleteConfirmation.value = allocation
    }

    fun dismissDeleteConfirmation() {
        _showDeleteConfirmation.value = null
    }

    fun confirmDeleteAllocation() {
        val allocation = _showDeleteConfirmation.value ?: return
        viewModelScope.launch {
            deleteAllocationUseCase(
                allocationId = allocation.id,
                assetId = allocation.assetId,
                goalId = allocation.goalId
            ).fold(
                onSuccess = {
                    _showDeleteConfirmation.value = null
                },
                onFailure = { e ->
                    _error.value = e.message ?: "Failed to delete allocation"
                    _showDeleteConfirmation.value = null
                }
            )
        }
    }

    fun clearError() {
        _error.value = null
    }
}
