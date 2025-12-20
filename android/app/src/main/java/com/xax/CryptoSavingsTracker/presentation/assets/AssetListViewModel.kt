package com.xax.CryptoSavingsTracker.presentation.assets

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.usecase.asset.DeleteAssetUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetsUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI State for the Assets List screen
 */
data class AssetListUiState(
    val assets: List<Asset> = emptyList(),
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
    private val deleteAssetUseCase: DeleteAssetUseCase
) : ViewModel() {

    private val _isLoading = MutableStateFlow(true)
    private val _error = MutableStateFlow<String?>(null)
    private val _showDeleteConfirmation = MutableStateFlow<Asset?>(null)

    val uiState: StateFlow<AssetListUiState> = combine(
        getAssetsUseCase(),
        _isLoading,
        _error,
        _showDeleteConfirmation
    ) { assets, isLoading, error, deleteConfirmation ->
        AssetListUiState(
            assets = assets.sortedBy { it.currency },
            isLoading = false,
            error = error,
            showDeleteConfirmation = deleteConfirmation
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = AssetListUiState()
    )

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
