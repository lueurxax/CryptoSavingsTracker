package com.xax.CryptoSavingsTracker.presentation.transactions

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.transaction.AddTransactionUseCase
import com.xax.CryptoSavingsTracker.presentation.common.AmountFormatters
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject

enum class TransactionType {
    DEPOSIT,
    WITHDRAWAL
}

data class AddTransactionState(
    val assetId: String = "",
    val assetCurrency: String = "",
    val assetName: String = "",
    val transactionType: TransactionType = TransactionType.DEPOSIT,
    val amount: String = "",
    val date: LocalDate = LocalDate.now(),
    val counterparty: String = "",
    val comment: String = "",
    val isLoading: Boolean = false,
    val isSaved: Boolean = false,
    val error: String? = null
) {
    val isValid: Boolean
        get() = amount.toDoubleOrNull()?.let { it > 0 } == true

    val amountError: String?
        get() = when {
            amount.isEmpty() -> null
            amount.toDoubleOrNull() == null -> "Enter a valid number"
            amount.toDoubleOrNull()!! <= 0 -> "Amount must be positive"
            else -> null
        }
}

@HiltViewModel
class AddTransactionViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val getAssetByIdUseCase: GetAssetByIdUseCase,
    private val addTransactionUseCase: AddTransactionUseCase
) : ViewModel() {

    private val assetId: String = checkNotNull(savedStateHandle["assetId"])
    private val prefillAmount: Double? = savedStateHandle.get<String>("prefillAmount")?.toDoubleOrNull()

    private val _state = MutableStateFlow(AddTransactionState(assetId = assetId))
    val state: StateFlow<AddTransactionState> = _state.asStateFlow()

    init {
        loadAsset()
    }

    private fun loadAsset() {
        viewModelScope.launch {
            try {
                val asset = getAssetByIdUseCase(assetId)
                if (asset != null) {
                    val prefillValue = prefillAmount?.let {
                        AmountFormatters.formatInputAmount(it, isCrypto = asset.isCryptoAsset)
                    }
                    _state.update { current ->
                        current.copy(
                            assetCurrency = asset.currency,
                            assetName = asset.displayName(),
                            amount = if (current.amount.isBlank() && !prefillValue.isNullOrBlank()) {
                                prefillValue
                            } else {
                                current.amount
                            }
                        )
                    }
                }
            } catch (e: Exception) {
                _state.update { it.copy(error = "Failed to load asset: ${e.message}") }
            }
        }
    }

    fun setTransactionType(type: TransactionType) {
        _state.update { it.copy(transactionType = type) }
    }

    fun setAmount(amount: String) {
        // Only allow valid decimal input
        val filtered = amount.filter { it.isDigit() || it == '.' }
        // Ensure only one decimal point
        if (filtered.count { it == '.' } <= 1) {
            _state.update { it.copy(amount = filtered) }
        }
    }

    fun setDate(date: LocalDate) {
        _state.update { it.copy(date = date) }
    }

    fun setCounterparty(counterparty: String) {
        _state.update { it.copy(counterparty = counterparty) }
    }

    fun setComment(comment: String) {
        _state.update { it.copy(comment = comment) }
    }

    fun saveTransaction() {
        val currentState = _state.value
        if (!currentState.isValid) return

        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            try {
                val amountValue = currentState.amount.toDouble()
                val signedAmount = if (currentState.transactionType == TransactionType.WITHDRAWAL) {
                    -amountValue
                } else {
                    amountValue
                }

                // iOS parity: use current timestamp for today's date to ensure
                // transactions fall within the execution window (which starts at a specific time).
                // For past dates, use start of day.
                val dateMillis = if (currentState.date == LocalDate.now()) {
                    System.currentTimeMillis()
                } else {
                    currentState.date
                        .atStartOfDay(ZoneId.systemDefault())
                        .toInstant()
                        .toEpochMilli()
                }

                addTransactionUseCase.create(
                    assetId = currentState.assetId,
                    amount = signedAmount,
                    dateMillis = dateMillis,
                    source = TransactionSource.MANUAL,
                    counterparty = currentState.counterparty.ifEmpty { null },
                    comment = currentState.comment.ifEmpty { null }
                )

                _state.update { it.copy(isLoading = false, isSaved = true) }
            } catch (e: Exception) {
                _state.update { it.copy(
                    isLoading = false,
                    error = "Failed to save transaction: ${e.message}"
                )}
            }
        }
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }
}
