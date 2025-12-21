package com.xax.CryptoSavingsTracker.presentation.allocations

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AddAllocationUseCase
import com.xax.CryptoSavingsTracker.presentation.common.AmountFormatters
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Data class for displaying an asset with its available balance for allocation.
 */
data class AssetForAllocation(
    val asset: Asset,
    val totalBalance: Double,       // Total manual balance
    val alreadyAllocated: Double,   // Amount already allocated to other goals
    val availableBalance: Double,   // Balance available for new allocations
    val isAlreadyAllocatedToThisGoal: Boolean
)

/**
 * UI State for Add Allocation screen
 */
data class AddAllocationUiState(
    val goal: Goal? = null,
    val availableAssets: List<AssetForAllocation> = emptyList(),
    val selectedAsset: AssetForAllocation? = null,
    val amount: String = "",
    val amountError: String? = null,
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val error: String? = null,
    val isSaved: Boolean = false
)

/**
 * ViewModel for adding a new allocation.
 */
@HiltViewModel
class AddAllocationViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val addAllocationUseCase: AddAllocationUseCase,
    private val goalRepository: GoalRepository,
    private val assetRepository: AssetRepository,
    private val allocationRepository: AllocationRepository,
    private val transactionRepository: TransactionRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository
) : ViewModel() {

    private val goalId: String = checkNotNull(savedStateHandle["goalId"])

    private val _selectedAsset = MutableStateFlow<AssetForAllocation?>(null)
    private val _amount = MutableStateFlow("")
    private val _amountError = MutableStateFlow<String?>(null)
    private val _isSaving = MutableStateFlow(false)
    private val _error = MutableStateFlow<String?>(null)
    private val _isSaved = MutableStateFlow(false)
    private val _availableAssets = MutableStateFlow<List<AssetForAllocation>>(emptyList())
    private val _isLoading = MutableStateFlow(true)

    init {
        loadData()
    }

    val uiState: StateFlow<AddAllocationUiState> = combine(
        goalRepository.getGoalByIdFlow(goalId),
        _availableAssets,
        _selectedAsset,
        _amount,
        _amountError,
        _isLoading,
        _isSaving,
        _error,
        _isSaved
    ) { values ->
        @Suppress("UNCHECKED_CAST")
        AddAllocationUiState(
            goal = values[0] as Goal?,
            availableAssets = values[1] as List<AssetForAllocation>,
            selectedAsset = values[2] as AssetForAllocation?,
            amount = values[3] as String,
            amountError = values[4] as String?,
            isLoading = values[5] as Boolean,
            isSaving = values[6] as Boolean,
            error = values[7] as String?,
            isSaved = values[8] as Boolean
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = AddAllocationUiState()
    )

    private fun loadData() {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val assets = assetRepository.getAllAssets().first()
                val assetsForAllocation = assets.map { asset ->
                    val manualBalance = transactionRepository.getManualBalanceForAsset(asset.id)
                    val onChainBalance = runCatching {
                        if (asset.isCryptoAsset && asset.address != null && asset.chainId != null) {
                            onChainBalanceRepository.getBalance(asset, forceRefresh = false).getOrNull()?.balance ?: 0.0
                        } else {
                            0.0
                        }
                    }.getOrElse { 0.0 }
                    val totalBalance = manualBalance + onChainBalance
                    val allocations = allocationRepository.getAllocationsForAsset(asset.id)
                    val alreadyAllocated = allocations.sumOf { it.amount }
                    val isAllocatedToThisGoal = allocations.any { it.goalId == goalId }

                    AssetForAllocation(
                        asset = asset,
                        totalBalance = totalBalance,
                        alreadyAllocated = alreadyAllocated,
                        availableBalance = totalBalance - alreadyAllocated,
                        isAlreadyAllocatedToThisGoal = isAllocatedToThisGoal
                    )
                }.filter { !it.isAlreadyAllocatedToThisGoal }

                _availableAssets.value = assetsForAllocation
            } catch (e: Exception) {
                _error.value = e.message ?: "Failed to load assets"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun selectAsset(asset: AssetForAllocation) {
        _selectedAsset.value = asset
        _amountError.value = null
    }

    fun updateAmount(value: String) {
        _amount.value = value
        _amountError.value = null
    }

    fun setMaxAmount() {
        _selectedAsset.value?.let { asset ->
            val max = kotlin.math.max(0.0, asset.availableBalance)
            _amount.value = AmountFormatters.formatInputAmount(max, isCrypto = asset.asset.isCryptoAsset)
            _amountError.value = null
        }
    }

    fun saveAllocation() {
        val asset = _selectedAsset.value
        if (asset == null) {
            _error.value = "Please select an asset"
            return
        }

        val amountValue = _amount.value.toDoubleOrNull()
        if (amountValue == null || amountValue <= 0) {
            _amountError.value = "Please enter a valid amount"
            return
        }
        if (amountValue > asset.availableBalance + 0.0000001) {
            _amountError.value = "Amount exceeds available balance (${AmountFormatters.formatDisplayAmount(asset.availableBalance, isCrypto = asset.asset.isCryptoAsset)})"
            return
        }

        viewModelScope.launch {
            _isSaving.value = true
            addAllocationUseCase(
                assetId = asset.asset.id,
                goalId = goalId,
                amount = amountValue
            ).fold(
                onSuccess = {
                    _isSaved.value = true
                },
                onFailure = { e ->
                    _error.value = e.message ?: "Failed to create allocation"
                }
            )
            _isSaving.value = false
        }
    }

    fun clearError() {
        _error.value = null
    }
}
