package com.xax.CryptoSavingsTracker.presentation.assets

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.usecase.asset.DeleteAssetUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.transaction.GetTransactionsUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI State for Asset Detail screen
 */
data class AssetDetailUiState(
    val asset: Asset? = null,
    val manualBalance: Double = 0.0,
    val currentBalance: Double = 0.0,
    val currentBalanceUsd: Double? = null,
    val isUsdLoading: Boolean = false,
    val usdError: String? = null,
    val transactionCount: Int = 0,
    val depositCount: Int = 0,
    val withdrawalCount: Int = 0,
    val recentTransactions: List<Transaction> = emptyList(),
    val onChainBalance: OnChainBalance? = null,
    val isOnChainLoading: Boolean = false,
    val onChainError: String? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val showDeleteConfirmation: Boolean = false,
    val isDeleted: Boolean = false
)

/**
 * ViewModel for Asset Detail screen
 */
@HiltViewModel
class AssetDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val getAssetByIdUseCase: GetAssetByIdUseCase,
    private val getTransactionsUseCase: GetTransactionsUseCase,
    private val exchangeRateRepository: ExchangeRateRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository,
    private val deleteAssetUseCase: DeleteAssetUseCase
) : ViewModel() {

    private val assetId: String = checkNotNull(savedStateHandle["assetId"])

    private val _showDeleteConfirmation = MutableStateFlow(false)
    private val _isDeleted = MutableStateFlow(false)
    private val _error = MutableStateFlow<String?>(null)
    private val _onChainBalance = MutableStateFlow<OnChainBalance?>(null)
    private val _isOnChainLoading = MutableStateFlow(false)
    private val _onChainError = MutableStateFlow<String?>(null)
    private val _currentBalanceUsd = MutableStateFlow<Double?>(null)
    private val _isUsdLoading = MutableStateFlow(false)
    private val _usdError = MutableStateFlow<String?>(null)

    private var latestAsset: Asset? = null
    private var latestManualBalance: Double = 0.0
    private var latestUsdKey: String? = null

    private val assetAndTransactions = combine(
        getAssetByIdUseCase.asFlow(assetId),
        getTransactionsUseCase(assetId)
    ) { asset, transactions ->
        asset to transactions
    }

    init {
        viewModelScope.launch {
            assetAndTransactions.collect { (asset, transactions) ->
                latestAsset = asset
                latestManualBalance = transactions
                    .filter { it.source == TransactionSource.MANUAL }
                    .sumOf { it.amount }

                if (asset?.isCryptoAsset == true && asset.address != null && asset.chainId != null) {
                    loadOnChainBalance(asset, forceRefresh = false)
                } else {
                    _onChainBalance.value = null
                    _onChainError.value = null
                    _isOnChainLoading.value = false
                }
                if (asset == null) {
                    _currentBalanceUsd.value = null
                    _usdError.value = null
                    _isUsdLoading.value = false
                    latestUsdKey = null
                }
            }
        }

        viewModelScope.launch {
            combine(
                assetAndTransactions,
                _onChainBalance
            ) { (asset, transactions), onChainBalance ->
                Triple(asset, transactions, onChainBalance)
            }.collect { (asset, transactions, onChainBalance) ->
                if (asset == null) return@collect
                val manualBalance = transactions
                    .filter { it.source == TransactionSource.MANUAL }
                    .sumOf { it.amount }
                val currentBalance = AssetBalanceCalculator.totalBalance(
                    manualBalance = manualBalance,
                    onChainBalance = onChainBalance?.balance,
                    hasOnChain = asset.isCryptoAsset && asset.address != null && asset.chainId != null
                )
                loadUsdBalanceIfNeeded(currency = asset.currency, balance = currentBalance)
            }
        }
    }

    private val onChainState = combine(
        _onChainBalance,
        _isOnChainLoading,
        _onChainError
    ) { balance, isLoading, error ->
        Triple(balance, isLoading, error)
    }

    private val usdState = combine(
        _currentBalanceUsd,
        _isUsdLoading,
        _usdError
    ) { usd, isLoading, error ->
        Triple(usd, isLoading, error)
    }

    private val uiFlags = combine(
        _showDeleteConfirmation,
        _isDeleted,
        _error
    ) { showDelete, isDeleted, error ->
        Triple(showDelete, isDeleted, error)
    }

    val uiState: StateFlow<AssetDetailUiState> = combine(
        assetAndTransactions,
        onChainState,
        usdState,
        uiFlags
    ) { (asset, transactions), (onChainBalance, isOnChainLoading, onChainError), (manualBalanceUsd, isUsdLoading, usdError), (showDelete, isDeleted, error) ->
        val sorted = transactions.sortedByDescending { it.dateMillis }
        val manualBalance = transactions
            .filter { it.source == TransactionSource.MANUAL }
            .sumOf { it.amount }
        val currentBalance = if (asset != null) {
            AssetBalanceCalculator.totalBalance(
                manualBalance = manualBalance,
                onChainBalance = onChainBalance?.balance,
                hasOnChain = asset.isCryptoAsset && asset.address != null && asset.chainId != null
            )
        } else {
            0.0
        }
        AssetDetailUiState(
            asset = asset,
            manualBalance = manualBalance,
            currentBalance = currentBalance,
            currentBalanceUsd = manualBalanceUsd,
            isUsdLoading = isUsdLoading,
            usdError = usdError,
            transactionCount = transactions.size,
            depositCount = transactions.count { it.isDeposit },
            withdrawalCount = transactions.count { !it.isDeposit },
            recentTransactions = sorted.take(5),
            onChainBalance = onChainBalance,
            isOnChainLoading = isOnChainLoading,
            onChainError = onChainError,
            isLoading = false,
            error = error,
            showDeleteConfirmation = showDelete,
            isDeleted = isDeleted
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = AssetDetailUiState()
    )

    fun refreshOnChainBalance() {
        val asset = latestAsset ?: return
        if (!asset.isCryptoAsset || asset.address == null || asset.chainId == null) return
        loadOnChainBalance(asset, forceRefresh = true)
    }

    fun refreshUsdBalance() {
        val asset = latestAsset ?: return
        val currentBalance = AssetBalanceCalculator.totalBalance(
            manualBalance = latestManualBalance,
            onChainBalance = _onChainBalance.value?.balance,
            hasOnChain = asset.isCryptoAsset && asset.address != null && asset.chainId != null
        )
        latestUsdKey = null
        loadUsdBalance(currency = asset.currency, balance = currentBalance, forceRefresh = true)
    }

    private fun loadOnChainBalance(asset: Asset, forceRefresh: Boolean) {
        viewModelScope.launch {
            _isOnChainLoading.value = true
            _onChainError.value = null
            onChainBalanceRepository.getBalance(asset, forceRefresh = forceRefresh).fold(
                onSuccess = { balance ->
                    _onChainBalance.value = balance
                    _isOnChainLoading.value = false
                },
                onFailure = { e ->
                    _onChainError.value = e.message ?: "Failed to fetch on-chain balance"
                    _isOnChainLoading.value = false
                }
            )
        }
    }

    private fun loadUsdBalanceIfNeeded(currency: String, balance: Double) {
        val key = "${currency.uppercase()}:${String.format("%.8f", balance)}"
        if (key == latestUsdKey) return
        latestUsdKey = key
        loadUsdBalance(currency = currency, balance = balance, forceRefresh = false)
    }

    private fun loadUsdBalance(currency: String, balance: Double, forceRefresh: Boolean) {
        if (balance == 0.0) {
            _currentBalanceUsd.value = 0.0
            _usdError.value = null
            _isUsdLoading.value = false
            return
        }

        viewModelScope.launch {
            _isUsdLoading.value = true
            _usdError.value = null
            runCatching {
                if (forceRefresh) {
                    exchangeRateRepository.clearCache()
                }
                val rate = exchangeRateRepository.fetchRate(currency, "USD")
                balance * rate
            }.onSuccess { usd ->
                _currentBalanceUsd.value = usd
                _isUsdLoading.value = false
            }.onFailure { e ->
                _usdError.value = e.message ?: "Failed to fetch USD rate"
                _isUsdLoading.value = false
            }
        }
    }

    fun showDeleteConfirmation() {
        _showDeleteConfirmation.value = true
    }

    fun dismissDeleteConfirmation() {
        _showDeleteConfirmation.value = false
    }

    fun confirmDelete() {
        viewModelScope.launch {
            deleteAssetUseCase(assetId).fold(
                onSuccess = {
                    _showDeleteConfirmation.value = false
                    _isDeleted.value = true
                },
                onFailure = { e ->
                    _error.value = e.message ?: "Failed to delete asset"
                    _showDeleteConfirmation.value = false
                }
            )
        }
    }

    fun clearError() {
        _error.value = null
    }
}
