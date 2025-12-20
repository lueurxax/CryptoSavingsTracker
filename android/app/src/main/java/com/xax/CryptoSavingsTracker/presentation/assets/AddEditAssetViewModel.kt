package com.xax.CryptoSavingsTracker.presentation.assets

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.ChainIds
import com.xax.CryptoSavingsTracker.domain.model.Cryptocurrencies
import com.xax.CryptoSavingsTracker.domain.usecase.asset.AddAssetUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.asset.UpdateAssetUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI State for Add/Edit Asset screen
 */
data class AddEditAssetUiState(
    val isLoading: Boolean = false,
    val isEditMode: Boolean = false,
    val assetId: String? = null,
    val currency: String = "",
    val address: String = "",
    val chainId: String? = null,
    val isCryptoAsset: Boolean = true,
    val currencyError: String? = null,
    val addressError: String? = null,
    val isSaved: Boolean = false,
    val error: String? = null
)

/**
 * ViewModel for Add/Edit Asset screen
 */
@HiltViewModel
class AddEditAssetViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val addAssetUseCase: AddAssetUseCase,
    private val updateAssetUseCase: UpdateAssetUseCase,
    private val getAssetByIdUseCase: GetAssetByIdUseCase
) : ViewModel() {

    private val assetId: String? = savedStateHandle["assetId"]

    private val _uiState = MutableStateFlow(AddEditAssetUiState())
    val uiState: StateFlow<AddEditAssetUiState> = _uiState.asStateFlow()

    private var originalAsset: Asset? = null

    init {
        assetId?.let { id ->
            loadAsset(id)
        }
    }

    private fun loadAsset(id: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            val asset = getAssetByIdUseCase(id)
            if (asset != null) {
                originalAsset = asset
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        isEditMode = true,
                        assetId = asset.id,
                        currency = asset.currency,
                        address = asset.address ?: "",
                        chainId = asset.chainId,
                        isCryptoAsset = asset.address != null
                    )
                }
            } else {
                _uiState.update {
                    it.copy(isLoading = false, error = "Asset not found")
                }
            }
        }
    }

    fun updateCurrency(currency: String) {
        _uiState.update { it.copy(currency = currency.uppercase(), currencyError = null) }
    }

    fun updateAddress(address: String) {
        _uiState.update { it.copy(address = address, addressError = null) }
    }

    fun updateChainId(chainId: String?) {
        _uiState.update { it.copy(chainId = chainId) }
    }

    fun updateIsCryptoAsset(isCrypto: Boolean) {
        _uiState.update {
            it.copy(
                isCryptoAsset = isCrypto,
                address = if (isCrypto) it.address else "",
                chainId = if (isCrypto) it.chainId else null
            )
        }
    }

    fun selectCurrency(currency: String) {
        _uiState.update { it.copy(currency = currency, currencyError = null) }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun saveAsset() {
        val state = _uiState.value

        // Validation
        var hasErrors = false

        if (state.currency.isBlank()) {
            _uiState.update { it.copy(currencyError = "Currency is required") }
            hasErrors = true
        }

        if (state.isCryptoAsset && state.address.isBlank()) {
            _uiState.update { it.copy(addressError = "Wallet address is required for crypto assets") }
            hasErrors = true
        }

        if (hasErrors) return

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            val result = if (state.isEditMode && originalAsset != null) {
                val updatedAsset = originalAsset!!.copy(
                    currency = state.currency.trim().uppercase(),
                    address = if (state.isCryptoAsset) state.address.trim() else null,
                    chainId = if (state.isCryptoAsset) state.chainId else null
                )
                updateAssetUseCase(updatedAsset)
            } else {
                addAssetUseCase(
                    currency = state.currency.trim().uppercase(),
                    address = if (state.isCryptoAsset && state.address.isNotBlank()) state.address.trim() else null,
                    chainId = if (state.isCryptoAsset) state.chainId else null
                )
            }

            result.fold(
                onSuccess = {
                    _uiState.update { it.copy(isLoading = false, isSaved = true) }
                },
                onFailure = { e ->
                    _uiState.update {
                        it.copy(isLoading = false, error = e.message ?: "Failed to save asset")
                    }
                }
            )
        }
    }

    companion object {
        val availableCurrencies = Cryptocurrencies.common.map { it.first }
        val availableChains = ChainIds.allChains
    }
}
