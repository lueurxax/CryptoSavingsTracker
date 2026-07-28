package com.xax.CryptoSavingsTracker.presentation.transactions

import androidx.lifecycle.SavedStateHandle
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.transaction.DeleteTransactionUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.transaction.GetTransactionsUseCase
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class TransactionListBalanceCompletenessTest {
    @Test
    fun `transactions remain visible while addressed total is explicitly unavailable`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val asset = Asset(
                id = "asset-1",
                currency = "BTC",
                address = "bc1qwallet",
                chainId = "bitcoin",
                createdAt = 1L,
                updatedAt = 1L
            )
            val manual = Transaction(
                id = "transaction-1",
                assetId = asset.id,
                amount = 5.0,
                dateMillis = 1L,
                source = TransactionSource.MANUAL,
                externalId = null,
                counterparty = null,
                comment = null,
                createdAt = 1L
            )
            val assets = mockk<AssetRepository>()
            val transactions = mockk<TransactionRepository>()
            val balances = mockk<OnChainBalanceRepository>()

            coEvery { assets.getAssetById(asset.id) } returns asset
            every { transactions.getTransactionsByAssetId(asset.id) } returns flowOf(listOf(manual))
            coEvery { balances.getBalance(asset, forceRefresh = false) } returns
                Result.failure(IllegalStateException("provider offline"))

            val viewModel = TransactionListViewModel(
                savedStateHandle = SavedStateHandle(mapOf("assetId" to asset.id)),
                getTransactionsUseCase = GetTransactionsUseCase(transactions),
                getAssetByIdUseCase = GetAssetByIdUseCase(assets),
                deleteTransactionUseCase = DeleteTransactionUseCase(transactions),
                onChainBalanceRepository = balances
            )
            advanceUntilIdle()

            val state = viewModel.state.value
            assertThat(state.transactions).containsExactly(manual)
            assertThat(state.totalBalance).isNull()
            assertThat(state.balanceIssue).contains("Refresh")
            assertThat(state.depositCount).isEqualTo(1)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `delayed provider balance combines with the latest manual transaction snapshot`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val asset = Asset(
                id = "asset-1",
                currency = "BTC",
                address = "bc1qwallet",
                chainId = "bitcoin",
                createdAt = 1L,
                updatedAt = 1L
            )
            val manual = Transaction(
                id = "transaction-1",
                assetId = asset.id,
                amount = 5.0,
                dateMillis = 1L,
                source = TransactionSource.MANUAL,
                externalId = null,
                counterparty = null,
                comment = null,
                createdAt = 1L
            )
            val transactionFlow = MutableStateFlow<List<Transaction>>(emptyList())
            val balanceStarted = CompletableDeferred<Unit>()
            val releaseBalance = CompletableDeferred<Unit>()
            val assets = mockk<AssetRepository>()
            val transactions = mockk<TransactionRepository>()
            val balances = mockk<OnChainBalanceRepository>()

            coEvery { assets.getAssetById(asset.id) } returns asset
            every { transactions.getTransactionsByAssetId(asset.id) } returns transactionFlow
            coEvery { balances.getBalance(asset, forceRefresh = false) } coAnswers {
                balanceStarted.complete(Unit)
                releaseBalance.await()
                Result.success(
                    OnChainBalance(
                        assetId = asset.id,
                        chainId = "bitcoin",
                        address = "bc1qwallet",
                        currency = "BTC",
                        balance = 7.0,
                        fetchedAtMillis = System.currentTimeMillis(),
                        isStale = false
                    )
                )
            }

            val viewModel = TransactionListViewModel(
                savedStateHandle = SavedStateHandle(mapOf("assetId" to asset.id)),
                getTransactionsUseCase = GetTransactionsUseCase(transactions),
                getAssetByIdUseCase = GetAssetByIdUseCase(assets),
                deleteTransactionUseCase = DeleteTransactionUseCase(transactions),
                onChainBalanceRepository = balances
            )
            runCurrent()
            balanceStarted.await()

            transactionFlow.value = listOf(manual)
            runCurrent()
            assertThat(viewModel.state.value.transactions).containsExactly(manual)
            assertThat(viewModel.state.value.totalBalance).isNull()

            releaseBalance.complete(Unit)
            advanceUntilIdle()

            assertThat(viewModel.state.value.totalBalance).isEqualTo(12.0)
            assertThat(viewModel.state.value.cachedOnChainBalance).isEqualTo(7.0)
        } finally {
            Dispatchers.resetMain()
        }
    }
}
