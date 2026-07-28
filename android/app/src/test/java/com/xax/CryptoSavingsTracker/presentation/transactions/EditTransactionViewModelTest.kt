package com.xax.CryptoSavingsTracker.presentation.transactions

import androidx.lifecycle.SavedStateHandle
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.transaction.GetTransactionByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.transaction.UpdateTransactionUseCase
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.Test
import java.time.LocalDate
import java.time.ZoneId

@OptIn(ExperimentalCoroutinesApi::class)
class EditTransactionViewModelTest {
    @Test
    fun `metadata-only edit preserves the original transaction timestamp`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val originalDateMillis = LocalDate.now()
                .atStartOfDay(ZoneId.systemDefault())
                .toInstant()
                .toEpochMilli()
            val original = Transaction(
                id = "transaction-1",
                assetId = "asset-1",
                amount = 1.0,
                dateMillis = originalDateMillis,
                source = TransactionSource.MANUAL,
                externalId = null,
                counterparty = "Alice",
                comment = "Before",
                createdAt = originalDateMillis - 1_000
            )
            val asset = Asset(
                id = "asset-1",
                currency = "BTC",
                address = null,
                chainId = "bitcoin",
                createdAt = 1L,
                updatedAt = 1L
            )
            val getTransaction = mockk<GetTransactionByIdUseCase>()
            val getAsset = mockk<GetAssetByIdUseCase>()
            val updateTransaction = mockk<UpdateTransactionUseCase>()
            var savedTransaction: Transaction? = null

            coEvery { getTransaction("transaction-1") } returns original
            coEvery { getAsset("asset-1") } returns asset
            coEvery { updateTransaction(any()) } answers {
                savedTransaction = firstArg()
            }

            val viewModel = EditTransactionViewModel(
                savedStateHandle = SavedStateHandle(mapOf("transactionId" to "transaction-1")),
                getTransactionByIdUseCase = getTransaction,
                getAssetByIdUseCase = getAsset,
                updateTransactionUseCase = updateTransaction
            )
            advanceUntilIdle()

            viewModel.setComment("After")
            viewModel.save()
            advanceUntilIdle()

            assertThat(savedTransaction).isNotNull()
            assertThat(savedTransaction!!.comment).isEqualTo("After")
            assertThat(savedTransaction!!.dateMillis).isEqualTo(originalDateMillis)
        } finally {
            Dispatchers.resetMain()
        }
    }
}
