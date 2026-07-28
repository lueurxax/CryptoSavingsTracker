package com.xax.CryptoSavingsTracker.presentation.transactions

import androidx.lifecycle.SavedStateHandle
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetByIdUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.transaction.AddTransactionUseCase
import io.mockk.coEvery
import io.mockk.mockk
import java.time.LocalDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class TransactionInputIntegrityTest {
    @Test
    fun `oversized decimal is not a valid transaction amount`() {
        val state = AddTransactionState(amount = "9".repeat(400))

        assertThat(state.isValid).isFalse()
        assertThat(state.amountError).isNotNull()
    }

    @Test
    fun `add transaction view model ignores future dates`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val assets = mockk<GetAssetByIdUseCase>()
            coEvery { assets("asset-1") } returns null
            val viewModel = AddTransactionViewModel(
                savedStateHandle = SavedStateHandle(mapOf("assetId" to "asset-1")),
                getAssetByIdUseCase = assets,
                addTransactionUseCase = mockk<AddTransactionUseCase>(relaxed = true)
            )
            advanceUntilIdle()
            val initialDate = viewModel.state.value.date

            viewModel.setDate(LocalDate.now().plusDays(1))

            assertThat(viewModel.state.value.date).isEqualTo(initialDate)
        } finally {
            Dispatchers.resetMain()
        }
    }
}
