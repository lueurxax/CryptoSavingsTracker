package com.xax.CryptoSavingsTracker.presentation.assets

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainAssetRouteCatalog
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.asset.DeleteAssetUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetsUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceCompleteness
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceCompletenessResolver
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
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
    val manualBalance: Double,
    val totalBalance: Double?,
    val usdValue: Double?,
    val balanceIssue: String?
)

data class AssetListUiState(
    val assets: List<AssetListItem> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val sourceFailure: String? = null,
    val showDeleteConfirmation: Asset? = null
)

/**
 * ViewModel for the Assets List screen
 */
@HiltViewModel
@OptIn(ExperimentalCoroutinesApi::class)
class AssetListViewModel @Inject constructor(
    private val getAssetsUseCase: GetAssetsUseCase,
    private val transactionRepository: TransactionRepository,
    private val exchangeRateRepository: ExchangeRateRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository,
    private val deleteAssetUseCase: DeleteAssetUseCase
) : ViewModel() {

    private data class SourceRead<T>(
        val value: T? = null,
        val failure: String? = null
    )

    private data class AssetSourceUpdate(
        val assets: List<Asset>? = null,
        val transactions: List<com.xax.CryptoSavingsTracker.domain.model.Transaction>? = null,
        val failure: String? = null
    )

    private val _error = MutableStateFlow<String?>(null)
    private val _showDeleteConfirmation = MutableStateFlow<Asset?>(null)
    private val sourceRetryGeneration = MutableStateFlow(0L)

    private val _uiState = MutableStateFlow(AssetListUiState())
    val uiState: StateFlow<AssetListUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            combine(
                sourceRetryGeneration.flatMapLatest { observeAssetSources() },
                _showDeleteConfirmation,
                _error
            ) { sources, deleteConfirmation, error ->
                Triple(sources, deleteConfirmation, error)
            }.collectLatest { (sources, deleteConfirmation, error) ->
                val sourceFailure = sources.failure
                if (sourceFailure != null) {
                    _uiState.value = AssetListUiState(
                        assets = emptyList(),
                        isLoading = false,
                        error = sourceFailure,
                        sourceFailure = sourceFailure,
                        showDeleteConfirmation = deleteConfirmation
                    )
                    return@collectLatest
                }

                val assets = checkNotNull(sources.assets)
                val transactions = checkNotNull(sources.transactions)
                val manualBalanceByAssetId = transactions
                    .filter { it.source == TransactionSource.MANUAL }
                    .groupBy { it.assetId }
                    .mapValues { (_, txs) -> txs.sumOf { it.amount } }

                val legacyQuickAssetIds = assets
                    .filter { asset ->
                        OnChainAssetRouteCatalog.isLegacyQuick(
                            chainId = asset.chainId,
                            currencyOrContract = asset.currency
                        )
                    }
                    .mapTo(mutableSetOf()) { it.id }
                val addressedLegacyQuickAssetIds = assets
                    .filter { asset ->
                        asset.id in legacyQuickAssetIds && !asset.address.isNullOrBlank()
                    }
                    .mapTo(mutableSetOf()) { it.id }
                val currencies = assets
                    .filterNot { it.id in legacyQuickAssetIds }
                    .map { it.currency.uppercase() }
                    .distinct()
                val ratesByCurrency = coroutineScope {
                    currencies.map { currency ->
                        async {
                            currency to runCatching { exchangeRateRepository.fetchRate(currency, "USD") }.getOrNull()
                        }
                    }.awaitAll().toMap()
                }

                val balanceByAssetId = coroutineScope {
                    assets.map { asset ->
                        async {
                            val manualBalance = manualBalanceByAssetId[asset.id] ?: 0.0
                            val completeness = if (asset.id in addressedLegacyQuickAssetIds) {
                                AssetBalanceCompleteness.Unavailable(
                                    manualBalance = manualBalance,
                                    issue = LEGACY_QUICK_UNAVAILABLE_MESSAGE
                                )
                            } else {
                                AssetBalanceCompletenessResolver.resolve(
                                    asset = asset,
                                    manualBalance = manualBalance,
                                    repository = onChainBalanceRepository,
                                    forceRefresh = false
                                )
                            }
                            asset.id to completeness
                        }
                    }.awaitAll().toMap()
                }

                val items = assets
                    .sortedBy { it.currency }
                    .map { asset ->
                        val manualBalance = manualBalanceByAssetId[asset.id] ?: 0.0
                        val balance = checkNotNull(balanceByAssetId[asset.id])
                        val totalBalance = balance.totalBalanceOrNull
                        val rate = if (asset.id in legacyQuickAssetIds) {
                            null
                        } else {
                            ratesByCurrency[asset.currency.uppercase()]
                        }
                        val usdValue = totalBalance?.let { total ->
                            rate
                                ?.takeIf { it.isFinite() && it > 0.0 }
                                ?.let { total * it }
                                ?.takeIf(Double::isFinite)
                        }
                        AssetListItem(
                            asset = asset,
                            manualBalance = manualBalance,
                            totalBalance = totalBalance,
                            usdValue = usdValue,
                            balanceIssue = balance.issueOrNull
                        )
                    }

                _uiState.value = AssetListUiState(
                    assets = items,
                    isLoading = false,
                    error = error ?: if (addressedLegacyQuickAssetIds.isNotEmpty()) {
                        LEGACY_QUICK_UNAVAILABLE_MESSAGE
                    } else {
                        null
                    },
                    sourceFailure = null,
                    showDeleteConfirmation = deleteConfirmation
                )
            }
        }
    }

    private fun observeAssetSources(): Flow<AssetSourceUpdate> = combine(
        getAssetsUseCase().asSourceRead("Asset"),
        transactionRepository.getAllTransactions().asSourceRead("Transaction")
    ) { assets, transactions ->
        val failure = listOfNotNull(assets.failure, transactions.failure)
            .joinToString(" ")
            .takeIf { it.isNotEmpty() }
        if (failure != null) {
            AssetSourceUpdate(failure = failure)
        } else {
            AssetSourceUpdate(
                assets = checkNotNull(assets.value),
                transactions = checkNotNull(transactions.value)
            )
        }
    }

    private fun <T> Flow<T>.asSourceRead(label: String): Flow<SourceRead<T>> =
        map<T, SourceRead<T>> { value -> SourceRead(value = value) }
            .catch { error ->
                emit(
                    SourceRead(
                        failure = "$label data source unavailable: " +
                            (error.message ?: error::class.simpleName.orEmpty())
                    )
                )
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

    fun retry() {
        _uiState.update { it.copy(isLoading = true, error = null, sourceFailure = null) }
        sourceRetryGeneration.update { it + 1L }
    }

    private companion object {
        const val LEGACY_QUICK_UNAVAILABLE_MESSAGE =
            "Legacy QUICK automatic balance is unavailable; the total balance is hidden."
    }
}
