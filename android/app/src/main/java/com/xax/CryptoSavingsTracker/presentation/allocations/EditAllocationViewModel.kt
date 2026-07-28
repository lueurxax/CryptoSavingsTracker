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
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.DeleteAllocationUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.UpdateAllocationUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceCompletenessResolver
import com.xax.CryptoSavingsTracker.presentation.common.AmountFormatters
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
    val assetBalance: Double? = null,
    val availableBalance: Double? = null,
    val balanceIssue: String? = null,
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
    private val onChainBalanceRepository: OnChainBalanceRepository,
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
                val manualBalance = transactionRepository.getManualBalanceForAsset(allocation.assetId)
                val balance = asset?.let {
                    AssetBalanceCompletenessResolver.resolve(
                        asset = it,
                        manualBalance = manualBalance,
                        repository = onChainBalanceRepository,
                        forceRefresh = false
                    )
                }
                val assetBalance = balance?.totalBalanceOrNull
                val balanceIssue = balance?.issueOrNull
                    ?: if (asset == null) {
                        "Asset is unavailable. Restore the asset and retry."
                    } else {
                        null
                    }
                val otherAllocations = allocationRepository.getAllocationsForAsset(allocation.assetId)
                    .filter { it.id != allocation.id }
                val availableBalance = assetBalance?.minus(otherAllocations.sumOf { it.amount })

                _uiState.update {
                    it.copy(
                        goal = goal,
                        allocation = allocation,
                        asset = asset,
                        assetBalance = assetBalance,
                        availableBalance = availableBalance?.let { max(0.0, it) },
                        balanceIssue = balanceIssue,
                        amount = AmountFormatters.formatInputAmount(allocation.amount, isCrypto = asset?.isCryptoAsset == true),
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
        val maxAmount = _uiState.value.availableBalance ?: run {
            _uiState.update {
                it.copy(
                    amountError = it.balanceIssue
                        ?: "Asset balance is unavailable. Refresh the wallet balance and retry."
                )
            }
            return
        }
        val isCrypto = _uiState.value.asset?.isCryptoAsset == true
        _uiState.update { it.copy(amount = AmountFormatters.formatInputAmount(maxAmount, isCrypto = isCrypto), amountError = null) }
    }

    fun save() {
        val allocation = _uiState.value.allocation ?: return
        val amountValue = _uiState.value.amount.toDoubleOrNull()
        if (amountValue == null || amountValue <= 0) {
            _uiState.update { it.copy(amountError = "Please enter a valid amount") }
            return
        }
        val availableBalance = _uiState.value.availableBalance
        if (availableBalance == null) {
            _uiState.update {
                it.copy(
                    amountError = it.balanceIssue
                        ?: "Asset balance is unavailable. Refresh the wallet balance and retry."
                )
            }
            return
        }
        if (amountValue > availableBalance + 0.0000001) {
            val isCrypto = _uiState.value.asset?.isCryptoAsset == true
            _uiState.update {
                it.copy(
                    amountError = "Amount exceeds available balance (${AmountFormatters.formatDisplayAmount(availableBalance, isCrypto = isCrypto)})"
                )
            }
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
