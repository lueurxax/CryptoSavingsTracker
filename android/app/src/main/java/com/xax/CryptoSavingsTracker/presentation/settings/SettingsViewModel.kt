package com.xax.CryptoSavingsTracker.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.data.local.security.ApiKeyStore
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SettingsUiState(
    val coinGeckoApiKey: String = "",
    val tatumApiKey: String = "",
    val isSaving: Boolean = false,
    val saveMessage: String? = null,
    val isClearingCaches: Boolean = false,
    val cacheMessage: String? = null
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val apiKeyStore: ApiKeyStore,
    private val exchangeRateRepository: ExchangeRateRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(
        SettingsUiState(
            coinGeckoApiKey = apiKeyStore.getCoinGeckoApiKey(),
            tatumApiKey = apiKeyStore.getTatumApiKey()
        )
    )
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    fun updateCoinGeckoApiKey(value: String) {
        _uiState.update { it.copy(coinGeckoApiKey = value, saveMessage = null) }
    }

    fun updateTatumApiKey(value: String) {
        _uiState.update { it.copy(tatumApiKey = value, saveMessage = null) }
    }

    fun save() {
        val state = _uiState.value
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, saveMessage = null) }
            runCatching {
                apiKeyStore.setCoinGeckoApiKey(state.coinGeckoApiKey)
                apiKeyStore.setTatumApiKey(state.tatumApiKey)
            }.onSuccess {
                _uiState.update { it.copy(isSaving = false, saveMessage = "Saved") }
            }.onFailure { e ->
                _uiState.update { it.copy(isSaving = false, saveMessage = e.message ?: "Failed to save") }
            }
        }
    }

    fun clearCaches() {
        viewModelScope.launch {
            _uiState.update { it.copy(isClearingCaches = true, cacheMessage = null) }
            runCatching {
                exchangeRateRepository.clearCache()
                onChainBalanceRepository.clearCache()
            }.onSuccess {
                _uiState.update { it.copy(isClearingCaches = false, cacheMessage = "Caches cleared") }
            }.onFailure { e ->
                _uiState.update { it.copy(isClearingCaches = false, cacheMessage = e.message ?: "Failed to clear caches") }
            }
        }
    }

    fun clearMessages() {
        _uiState.update { it.copy(saveMessage = null, cacheMessage = null) }
    }
}
