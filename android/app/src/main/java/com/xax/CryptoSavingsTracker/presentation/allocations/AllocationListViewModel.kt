package com.xax.CryptoSavingsTracker.presentation.allocations

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
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
    val assetBalance: Double,          // Best-known balance (manual + on-chain if available)
    val assetTotalAllocated: Double,   // Total allocated from this asset across all goals
    val assetDisplayName: String,
    val isAssetOverAllocated: Boolean  // True if asset's total allocations exceed balance
) {
    val fundedAmount: Double
        get() {
            val total = assetTotalAllocated
            val balance = assetBalance
            if (total <= 0.0 || balance <= 0.0) return 0.0
            val ratio = if (balance >= total) 1.0 else balance / total
            return allocation.amount.coerceAtLeast(0.0) * ratio
        }

    val isUnderfunded: Boolean
        get() = fundedAmount + 0.0000001 < allocation.amount
}

/**
 * UI State for Allocation List screen
 */
data class AllocationListUiState(
    val goal: Goal? = null,
    val allocations: List<AllocationWithDetails> = emptyList(),
    val totalAllocated: Double = 0.0, // Value in goal currency
    val totalFunded: Double = 0.0,    // Value in goal currency
    val hasOverAllocatedAssets: Boolean = false,
    val hasMissingExchangeRates: Boolean = false,
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
    private val transactionRepository: TransactionRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository,
    private val exchangeRateRepository: ExchangeRateRepository
) : ViewModel() {

    private val goalId: String = checkNotNull(savedStateHandle["goalId"])

    private val _error = MutableStateFlow<String?>(null)
    private val _showDeleteConfirmation = MutableStateFlow<Allocation?>(null)
    private val _allocationsWithDetails = MutableStateFlow<List<AllocationWithDetails>>(emptyList())
    private val _totals = MutableStateFlow(AllocationTotals())

    init {
        loadAllocationsWithDetails()
    }

    val uiState: StateFlow<AllocationListUiState> = combine(
        goalRepository.getGoalByIdFlow(goalId),
        _allocationsWithDetails,
        _totals,
        _error,
        _showDeleteConfirmation
    ) { goal, allocations, totals, error, deleteConfirmation ->
        AllocationListUiState(
            goal = goal,
            allocations = allocations,
            totalAllocated = totals.totalAllocatedInGoalCurrency,
            totalFunded = totals.totalFundedInGoalCurrency,
            hasOverAllocatedAssets = allocations.any { it.isAssetOverAllocated },
            isLoading = false,
            hasMissingExchangeRates = totals.hasMissingExchangeRates,
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
                val goal = goalRepository.getGoalById(goalId)
                val withDetails = allocations.map { allocation ->
                    val asset = assetRepository.getAssetById(allocation.assetId)
                    val manualBalance = transactionRepository.getManualBalanceForAsset(allocation.assetId)
                    val onChainBalance = runCatching {
                        if (asset?.isCryptoAsset == true && asset.address != null && asset.chainId != null) {
                            onChainBalanceRepository.getBalance(asset, forceRefresh = false).getOrNull()?.balance ?: 0.0
                        } else {
                            0.0
                        }
                    }.getOrElse { 0.0 }
                    val balance = manualBalance + onChainBalance

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
                _totals.value = calculateTotals(goal, withDetails)
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

    private suspend fun calculateTotals(
        goal: Goal?,
        allocations: List<AllocationWithDetails>
    ): AllocationTotals {
        val goalCurrency = goal?.currency ?: return AllocationTotals()
        var allocated = 0.0
        var funded = 0.0
        var missingRates = false

        for (item in allocations) {
            val assetCurrency = item.asset?.currency ?: goalCurrency
            val allocationAmount = item.allocation.amount
            val fundedAmount = item.fundedAmount

            val allocatedValue = convertOrNull(allocationAmount, assetCurrency, goalCurrency)
            val fundedValue = convertOrNull(fundedAmount, assetCurrency, goalCurrency)

            if (allocatedValue == null || fundedValue == null) {
                missingRates = true
                continue
            }

            allocated += allocatedValue
            funded += fundedValue
        }

        return AllocationTotals(
            totalAllocatedInGoalCurrency = allocated,
            totalFundedInGoalCurrency = funded,
            hasMissingExchangeRates = missingRates
        )
    }

    private suspend fun convertOrNull(amount: Double, from: String, to: String): Double? {
        if (from.equals(to, ignoreCase = true)) return amount
        val rate = runCatching { exchangeRateRepository.fetchRate(from, to) }.getOrNull()
        return rate?.let { amount * it }
    }
}

private data class AllocationTotals(
    val totalAllocatedInGoalCurrency: Double = 0.0,
    val totalFundedInGoalCurrency: Double = 0.0,
    val hasMissingExchangeRates: Boolean = false
)
