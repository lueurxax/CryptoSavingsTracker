package com.xax.CryptoSavingsTracker.presentation.transactions

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.transaction.DeleteTransactionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.transaction.GetTransactionsUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceCompleteness
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceCompletenessResolver
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class TransactionListState(
    val transactions: List<Transaction> = emptyList(),
    val assetCurrency: String = "",
    val assetName: String = "",
    val isCryptoAsset: Boolean = false,
    val cachedOnChainBalance: Double? = null,
    val isBalanceResolved: Boolean = false,
    val balanceIssue: String? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val totalBalance: Double? = null,
    val depositCount: Int = 0,
    val withdrawalCount: Int = 0
)

@HiltViewModel
class TransactionListViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val getTransactionsUseCase: GetTransactionsUseCase,
    private val getAssetByIdUseCase: GetAssetByIdUseCase,
    private val deleteTransactionUseCase: DeleteTransactionUseCase,
    private val onChainBalanceRepository: OnChainBalanceRepository
) : ViewModel() {

    private val assetId: String = checkNotNull(savedStateHandle["assetId"])

    private val _state = MutableStateFlow(TransactionListState())
    val state: StateFlow<TransactionListState> = _state.asStateFlow()

    init {
        loadAsset()
        loadTransactions()
    }

    private fun loadAsset() {
        viewModelScope.launch {
            try {
                val asset = getAssetByIdUseCase(assetId)
                if (asset != null) {
                    val existingManual = _state.value.transactions
                        .filter { it.source == TransactionSource.MANUAL }
                        .sumOf { it.amount }
                    val balance = AssetBalanceCompletenessResolver.resolve(
                        asset = asset,
                        manualBalance = existingManual,
                        repository = onChainBalanceRepository,
                        forceRefresh = false
                    )
                    val cachedOnChain = (balance as? AssetBalanceCompleteness.Complete)
                        ?.onChainBalance
                        ?: if (balance is AssetBalanceCompleteness.Complete) 0.0 else null
                    _state.update { current ->
                        val latestManualBalance = current.transactions
                            .filter { it.source == TransactionSource.MANUAL }
                            .sumOf { it.amount }
                        val totalBalance = if (
                            balance.issueOrNull == null &&
                            latestManualBalance.isFinite()
                        ) {
                            (latestManualBalance + (cachedOnChain ?: 0.0))
                                .takeIf(Double::isFinite)
                        } else {
                            null
                        }
                        current.copy(
                            assetCurrency = asset.currency,
                            assetName = asset.displayName(),
                            isCryptoAsset = asset.isCryptoAsset,
                            cachedOnChainBalance = cachedOnChain,
                            isBalanceResolved = true,
                            balanceIssue = balance.issueOrNull,
                            totalBalance = totalBalance
                        )
                    }
                }
            } catch (e: Exception) {
                _state.update { it.copy(error = "Failed to load asset: ${e.message}") }
            }
        }
    }

    private fun loadTransactions() {
        viewModelScope.launch {
            getTransactionsUseCase(assetId).collect { transactions ->
                val sortedTransactions = transactions.sortedByDescending { it.dateMillis }
                val manualBalance = transactions
                    .filter { it.source == TransactionSource.MANUAL }
                    .sumOf { it.amount }
                val depositCount = transactions.count { it.isDeposit }
                val withdrawalCount = transactions.count { !it.isDeposit }

                _state.update { current ->
                    val totalBalance = if (
                        current.isBalanceResolved &&
                        current.balanceIssue == null &&
                        manualBalance.isFinite()
                    ) {
                        (manualBalance + (current.cachedOnChainBalance ?: 0.0))
                            .takeIf(Double::isFinite)
                    } else {
                        null
                    }
                    current.copy(
                        transactions = sortedTransactions,
                        isLoading = false,
                        totalBalance = totalBalance,
                        depositCount = depositCount,
                        withdrawalCount = withdrawalCount
                    )
                }
            }
        }
    }

    fun deleteTransaction(transaction: Transaction) {
        viewModelScope.launch {
            try {
                deleteTransactionUseCase(transaction.id)
            } catch (e: Exception) {
                _state.update { it.copy(error = "Failed to delete transaction: ${e.message}") }
            }
        }
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }

    fun getAssetId(): String = assetId
}
