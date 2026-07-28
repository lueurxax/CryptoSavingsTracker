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
import com.xax.CryptoSavingsTracker.domain.repository.OnChainTransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.asset.DeleteAssetUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceCompletenessResolver
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
    val currentBalance: Double? = null,
    val balanceIssue: String? = null,
    val currentBalanceUsd: Double? = null,
    val isUsdLoading: Boolean = false,
    val usdError: String? = null,
    val manualTransactionCount: Int = 0,
    val manualDepositCount: Int = 0,
    val manualWithdrawalCount: Int = 0,
    val recentManualTransactions: List<Transaction> = emptyList(),
    val recentOnChainTransactions: List<Transaction> = emptyList(),
    val onChainBalance: OnChainBalance? = null,
    val isOnChainLoading: Boolean = false,
    val onChainError: String? = null,
    val isOnChainTransactionsLoading: Boolean = false,
    val onChainTransactionsError: String? = null,
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
    private val onChainTransactionRepository: OnChainTransactionRepository,
    private val deleteAssetUseCase: DeleteAssetUseCase
) : ViewModel() {

    private data class UsdBalanceRequest(
        val currency: String,
        val balance: Double,
        val key: String
    )

    private val assetId: String = checkNotNull(savedStateHandle["assetId"])

    private val _showDeleteConfirmation = MutableStateFlow(false)
    private val _isDeleted = MutableStateFlow(false)
    private val _error = MutableStateFlow<String?>(null)
    private val _onChainBalance = MutableStateFlow<OnChainBalance?>(null)
    private val _isOnChainLoading = MutableStateFlow(false)
    private val _onChainError = MutableStateFlow<String?>(null)
    private val _isOnChainTransactionsLoading = MutableStateFlow(false)
    private val _onChainTransactionsError = MutableStateFlow<String?>(null)
    private val _currentBalanceUsd = MutableStateFlow<Double?>(null)
    private val _isUsdLoading = MutableStateFlow(false)
    private val _usdError = MutableStateFlow<String?>(null)

    private var latestAsset: Asset? = null
    private var latestManualBalance: Double = 0.0
    private var latestUsdKey: String? = null
    private var latestOnChainKey: String? = null
    private var onChainBalanceGeneration: Long = 0L
    private var onChainTransactionsGeneration: Long = 0L
    private var usdBalanceGeneration: Long = 0L
    private var isForcedOnChainBalanceLoadInProgress: Boolean = false
    private var isForcedUsdBalanceLoadInProgress: Boolean = false
    private var activeForcedUsdKey: String? = null
    private var pendingUsdBalanceRequest: UsdBalanceRequest? = null

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

                if (asset != null && !asset.address.isNullOrBlank() && !asset.chainId.isNullOrBlank()) {
                    val onChainKey = "${asset.chainId}:${asset.address}:${asset.currency}"
                    if (latestOnChainKey != onChainKey) {
                        latestOnChainKey = onChainKey
                        refreshOnChainTransactions(asset = asset, forceRefresh = false)
                        loadOnChainBalance(asset, forceRefresh = false)
                    } else if (!isForcedOnChainBalanceLoadInProgress) {
                        loadOnChainBalance(asset, forceRefresh = false)
                    }
                } else {
                    onChainBalanceGeneration += 1
                    onChainTransactionsGeneration += 1
                    isForcedOnChainBalanceLoadInProgress = false
                    _onChainBalance.value = null
                    _onChainError.value = null
                    _isOnChainLoading.value = false
                    _isOnChainTransactionsLoading.value = false
                    _onChainTransactionsError.value = null
                    latestOnChainKey = null
                }
                if (asset == null) {
                    invalidateUsdBalance()
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
                val balance = AssetBalanceCompletenessResolver.resolveSnapshot(
                    asset = asset,
                    manualBalance = manualBalance,
                    providerBalance = onChainBalance
                )
                val currentBalance = balance.totalBalanceOrNull
                if (currentBalance != null) {
                    loadUsdBalanceIfNeeded(currency = asset.currency, balance = currentBalance)
                } else {
                    invalidateUsdBalance()
                }
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

    private val onChainTransactionsState = combine(
        _isOnChainTransactionsLoading,
        _onChainTransactionsError
    ) { isLoading, error ->
        isLoading to error
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
        onChainTransactionsState,
        usdState,
        uiFlags
    ) { (asset, transactions), (onChainBalance, isOnChainLoading, onChainError), (isOnChainTxLoading, onChainTxError), (manualBalanceUsd, isUsdLoading, usdError), (showDelete, isDeleted, error) ->
        val manualTransactions = transactions.filter { it.source == TransactionSource.MANUAL }
        val onChainTransactions = transactions.filter { it.source == TransactionSource.ON_CHAIN }
        val manualSorted = manualTransactions.sortedByDescending { it.dateMillis }
        val onChainSorted = onChainTransactions.sortedByDescending { it.dateMillis }
        val manualBalance = manualTransactions.sumOf { it.amount }
        val balance = asset?.let {
            AssetBalanceCompletenessResolver.resolveSnapshot(
                asset = it,
                manualBalance = manualBalance,
                providerBalance = onChainBalance
            )
        }
        AssetDetailUiState(
            asset = asset,
            manualBalance = manualBalance,
            currentBalance = balance?.totalBalanceOrNull,
            balanceIssue = balance?.issueOrNull,
            currentBalanceUsd = manualBalanceUsd,
            isUsdLoading = isUsdLoading,
            usdError = usdError,
            manualTransactionCount = manualTransactions.size,
            manualDepositCount = manualTransactions.count { it.isDeposit },
            manualWithdrawalCount = manualTransactions.count { !it.isDeposit },
            recentManualTransactions = manualSorted.take(5),
            recentOnChainTransactions = onChainSorted.take(5),
            onChainBalance = onChainBalance,
            isOnChainLoading = isOnChainLoading,
            onChainError = onChainError,
            isOnChainTransactionsLoading = isOnChainTxLoading,
            onChainTransactionsError = onChainTxError,
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
        if (asset.address.isNullOrBlank() || asset.chainId.isNullOrBlank()) return
        refreshOnChainTransactions(asset = asset, forceRefresh = true)
        loadOnChainBalance(asset, forceRefresh = true)
    }

    fun refreshUsdBalance() {
        val asset = latestAsset ?: return
        val balance = AssetBalanceCompletenessResolver.resolveSnapshot(
            asset = asset,
            manualBalance = latestManualBalance,
            providerBalance = _onChainBalance.value
        )
        val currentBalance = balance.totalBalanceOrNull
        if (currentBalance == null) {
            invalidateUsdBalance(error = balance.issueOrNull)
            return
        }
        loadUsdBalance(currency = asset.currency, balance = currentBalance, forceRefresh = true)
    }

    private fun loadOnChainBalance(asset: Asset, forceRefresh: Boolean) {
        val generation = ++onChainBalanceGeneration
        isForcedOnChainBalanceLoadInProgress = forceRefresh
        viewModelScope.launch {
            try {
                _isOnChainLoading.value = true
                _onChainError.value = null
                onChainBalanceRepository.getBalance(asset, forceRefresh = forceRefresh).fold(
                    onSuccess = { balance ->
                        if (generation != onChainBalanceGeneration) return@fold
                        _onChainBalance.value = balance
                        _isOnChainLoading.value = false
                    },
                    onFailure = { e ->
                        if (generation != onChainBalanceGeneration) return@fold
                        val message = e.message ?: "Failed to fetch on-chain balance"
                        // A failed latest-provider read invalidates the previous
                        // snapshot. Keeping it visible would present stale data
                        // as authoritative after an explicit refresh failed.
                        _onChainBalance.value = null
                        invalidateUsdBalance(error = message)
                        _onChainError.value = message
                        _isOnChainLoading.value = false
                    }
                )
            } finally {
                if (generation == onChainBalanceGeneration) {
                    isForcedOnChainBalanceLoadInProgress = false
                }
            }
        }
    }

    private fun refreshOnChainTransactions(asset: Asset, forceRefresh: Boolean) {
        val generation = ++onChainTransactionsGeneration
        viewModelScope.launch {
            if (generation != onChainTransactionsGeneration) return@launch
            _isOnChainTransactionsLoading.value = true
            _onChainTransactionsError.value = null
            val result = onChainTransactionRepository.refresh(
                asset = asset,
                limit = 20,
                forceRefresh = forceRefresh
            )
            if (generation != onChainTransactionsGeneration) return@launch
            result.fold(
                onSuccess = { _ ->
                    _isOnChainTransactionsLoading.value = false
                },
                onFailure = { e ->
                    _onChainTransactionsError.value = e.message ?: "Failed to fetch on-chain transactions"
                    _isOnChainTransactionsLoading.value = false
                }
            )
        }
    }

    private fun loadUsdBalanceIfNeeded(currency: String, balance: Double) {
        val request = usdBalanceRequest(currency = currency, balance = balance)
        if (isForcedUsdBalanceLoadInProgress) {
            if (request.key != latestUsdKey) {
                latestUsdKey = request.key
                _currentBalanceUsd.value = null
                _usdError.value = null
            }
            pendingUsdBalanceRequest = request.takeUnless { it.key == activeForcedUsdKey }
            return
        }
        if (request.key == latestUsdKey) return
        loadUsdBalance(currency = currency, balance = balance, forceRefresh = false)
    }

    private fun loadUsdBalance(currency: String, balance: Double, forceRefresh: Boolean) {
        val request = usdBalanceRequest(currency = currency, balance = balance)
        val inputChanged = request.key != latestUsdKey
        latestUsdKey = request.key
        if (inputChanged) {
            _currentBalanceUsd.value = null
        }
        val generation = ++usdBalanceGeneration
        if (forceRefresh) {
            isForcedUsdBalanceLoadInProgress = true
            activeForcedUsdKey = request.key
            pendingUsdBalanceRequest = null
        }
        if (balance == 0.0) {
            _currentBalanceUsd.value = 0.0
            _usdError.value = null
            _isUsdLoading.value = false
            finishForcedUsdBalanceLoad(generation = generation, forceRefresh = forceRefresh)
            return
        }

        viewModelScope.launch {
            try {
                if (generation != usdBalanceGeneration) return@launch
                _isUsdLoading.value = true
                _usdError.value = null
                runCatching {
                    if (forceRefresh) {
                        exchangeRateRepository.clearCache()
                    }
                    val rate = exchangeRateRepository.fetchRate(currency, "USD")
                    balance * rate
                }.onSuccess { usd ->
                    if (
                        generation != usdBalanceGeneration ||
                        request.key != latestUsdKey
                    ) {
                        return@onSuccess
                    }
                    _currentBalanceUsd.value = usd
                    _isUsdLoading.value = false
                }.onFailure { e ->
                    if (
                        generation != usdBalanceGeneration ||
                        request.key != latestUsdKey
                    ) {
                        return@onFailure
                    }
                    _currentBalanceUsd.value = null
                    _usdError.value = e.message ?: "Failed to fetch USD rate"
                    _isUsdLoading.value = false
                }
            } finally {
                finishForcedUsdBalanceLoad(generation = generation, forceRefresh = forceRefresh)
            }
        }
    }

    private fun usdBalanceRequest(currency: String, balance: Double): UsdBalanceRequest {
        return UsdBalanceRequest(
            currency = currency,
            balance = balance,
            key = "${currency.uppercase()}:${String.format("%.8f", balance)}"
        )
    }

    private fun finishForcedUsdBalanceLoad(generation: Long, forceRefresh: Boolean) {
        if (!forceRefresh || generation != usdBalanceGeneration) return
        isForcedUsdBalanceLoadInProgress = false
        activeForcedUsdKey = null
        val pendingRequest = pendingUsdBalanceRequest
        pendingUsdBalanceRequest = null
        if (pendingRequest != null) {
            loadUsdBalance(
                currency = pendingRequest.currency,
                balance = pendingRequest.balance,
                forceRefresh = false
            )
        }
    }

    private fun invalidateUsdBalance(error: String? = null) {
        usdBalanceGeneration += 1
        latestUsdKey = null
        isForcedUsdBalanceLoadInProgress = false
        activeForcedUsdKey = null
        pendingUsdBalanceRequest = null
        _currentBalanceUsd.value = null
        _usdError.value = error
        _isUsdLoading.value = false
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
