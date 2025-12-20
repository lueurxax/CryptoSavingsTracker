package com.xax.CryptoSavingsTracker.presentation.transactions

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.transaction.GetTransactionByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.transaction.UpdateTransactionUseCase
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

data class EditTransactionState(
    val transactionId: String = "",
    val assetId: String = "",
    val assetCurrency: String = "",
    val assetName: String = "",
    val transactionType: TransactionType = TransactionType.DEPOSIT,
    val amount: String = "",
    val date: LocalDate = LocalDate.now(),
    val counterparty: String = "",
    val comment: String = "",
    val source: TransactionSource = TransactionSource.MANUAL,
    val isLoading: Boolean = true,
    val isSaved: Boolean = false,
    val error: String? = null
) {
    val isEditable: Boolean
        get() = source == TransactionSource.MANUAL

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
class EditTransactionViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val getTransactionByIdUseCase: GetTransactionByIdUseCase,
    private val getAssetByIdUseCase: GetAssetByIdUseCase,
    private val updateTransactionUseCase: UpdateTransactionUseCase
) : ViewModel() {

    private val transactionId: String = checkNotNull(savedStateHandle["transactionId"])
    private var originalTransaction: Transaction? = null

    private val _state = MutableStateFlow(EditTransactionState(transactionId = transactionId))
    val state: StateFlow<EditTransactionState> = _state.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            runCatching {
                val tx = getTransactionByIdUseCase(transactionId)
                    ?: throw IllegalStateException("Transaction not found")
                originalTransaction = tx
                val asset = getAssetByIdUseCase(tx.assetId)
                val date = Instant.ofEpochMilli(tx.dateMillis).atZone(ZoneId.systemDefault()).toLocalDate()
                val type = if (tx.amount < 0) TransactionType.WITHDRAWAL else TransactionType.DEPOSIT
                EditTransactionState(
                    transactionId = tx.id,
                    assetId = tx.assetId,
                    assetCurrency = asset?.currency ?: "",
                    assetName = asset?.displayName() ?: "",
                    transactionType = type,
                    amount = tx.absoluteAmount.toString(),
                    date = date,
                    counterparty = tx.counterparty.orEmpty(),
                    comment = tx.comment.orEmpty(),
                    source = tx.source,
                    isLoading = false,
                    isSaved = false,
                    error = null
                )
            }.onSuccess { loaded ->
                _state.value = loaded
            }.onFailure { e ->
                _state.update { it.copy(isLoading = false, error = e.message ?: "Failed to load transaction") }
            }
        }
    }

    fun setTransactionType(type: TransactionType) {
        _state.update { it.copy(transactionType = type) }
    }

    fun setAmount(amount: String) {
        val filtered = amount.filter { it.isDigit() || it == '.' }
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

    fun save() {
        val currentState = _state.value
        val original = originalTransaction ?: return
        if (!currentState.isEditable || !currentState.isValid) return

        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            runCatching {
                val amountValue = currentState.amount.toDouble()
                val signedAmount = if (currentState.transactionType == TransactionType.WITHDRAWAL) {
                    -amountValue
                } else {
                    amountValue
                }
                val dateMillis = currentState.date
                    .atStartOfDay(ZoneId.systemDefault())
                    .toInstant()
                    .toEpochMilli()

                val updated = original.copy(
                    amount = signedAmount,
                    dateMillis = dateMillis,
                    counterparty = currentState.counterparty.ifEmpty { null },
                    comment = currentState.comment.ifEmpty { null }
                )
                updateTransactionUseCase(updated)
            }.onSuccess {
                _state.update { it.copy(isLoading = false, isSaved = true) }
            }.onFailure { e ->
                _state.update { it.copy(isLoading = false, error = e.message ?: "Failed to save transaction") }
            }
        }
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }
}

