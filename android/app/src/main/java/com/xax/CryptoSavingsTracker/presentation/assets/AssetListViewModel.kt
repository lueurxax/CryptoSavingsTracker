package com.xax.CryptoSavingsTracker.presentation.assets

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.asset.DeleteAssetUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetsUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import javax.inject.Inject

/**
 * UI State for the Assets List screen
 */
data class AssetListItem(
    val asset: Asset,
    val totalBalance: Double,
    val usdValue: Double?
)

data class AssetListUiState(
    val assets: List<AssetListItem> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val showDeleteConfirmation: Asset? = null
)

/**
 * ViewModel for the Assets List screen
 */
@HiltViewModel
class AssetListViewModel @Inject constructor(
    private val getAssetsUseCase: GetAssetsUseCase,
    private val transactionRepository: TransactionRepository,
    private val exchangeRateRepository: ExchangeRateRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository,
    private val deleteAssetUseCase: DeleteAssetUseCase
) : ViewModel() {

    private val _error = MutableStateFlow<String?>(null)
    private val _showDeleteConfirmation = MutableStateFlow<Asset?>(null)

    private val _uiState = MutableStateFlow(AssetListUiState())
    val uiState: StateFlow<AssetListUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            combine(
                getAssetsUseCase().catch { emit(emptyList()) },
                transactionRepository.getAllTransactions().catch { emit(emptyList()) },
                _showDeleteConfirmation,
                _error
            ) { assets, transactions, deleteConfirmation, error ->
                Quadruple(assets, transactions, deleteConfirmation, error)
            }.collectLatest { (assets, transactions, deleteConfirmation, error) ->
                val manualBalanceByAssetId = transactions
                    .filter { it.source == TransactionSource.MANUAL }
                    .groupBy { it.assetId }
                    .mapValues { (_, txs) -> txs.sumOf { it.amount } }

                val currencies = assets.map { it.currency.uppercase() }.distinct()
                val ratesByCurrency = coroutineScope {
                    currencies.map { currency ->
                        async {
                            currency to runCatching { exchangeRateRepository.fetchRate(currency, "USD") }.getOrNull()
                        }
                    }.awaitAll().toMap()
                }

                val onChainBalanceByAssetId = coroutineScope {
                    assets.map { asset ->
                        async {
                            if (!asset.chainId.isNullOrBlank() && !asset.address.isNullOrBlank()) {
                                asset.id to onChainBalanceRepository.getBalance(asset, forceRefresh = false).getOrNull()?.balance
                            } else {
                                asset.id to null
                            }
                        }
                    }.awaitAll().toMap()
                }

                val items = assets
                    .sortedBy { it.currency }
                    .map { asset ->
                        val manualBalance = manualBalanceByAssetId[asset.id] ?: 0.0
                        val onChainBalance = onChainBalanceByAssetId[asset.id] ?: 0.0
                        val totalBalance = AssetBalanceCalculator.totalBalance(
                            manualBalance = manualBalance,
                            onChainBalance = onChainBalance,
                            hasOnChain = !asset.chainId.isNullOrBlank() && !asset.address.isNullOrBlank()
                        )
                        val rate = ratesByCurrency[asset.currency.uppercase()]
                        val usdValue = rate?.let { totalBalance * it }
                        AssetListItem(asset = asset, totalBalance = totalBalance, usdValue = usdValue)
                    }

                _uiState.value = AssetListUiState(
                    assets = items,
                    isLoading = false,
                    error = error,
                    showDeleteConfirmation = deleteConfirmation
                )
            }
        }
    }

    fun requestDeleteAsset(asset: Asset) {
        _showDeleteConfirmation.value = asset
    }

    fun dismissDeleteConfirmation() {
        _showDeleteConfirmation.value = null
    }

    fun confirmDeleteAsset() {
        val asset = _showDeleteConfirmation.value ?: return
        viewModelScope.launch {
            deleteAssetUseCase(asset.id).fold(
                onSuccess = {
                    _showDeleteConfirmation.value = null
                },
                onFailure = { e ->
                    _error.value = e.message ?: "Failed to delete asset"
                    _showDeleteConfirmation.value = null
                }
            )
        }
    }

    fun clearError() {
        _error.value = null
    }
}

private data class Quadruple<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)
