package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

interface OnChainBalanceRepository {
    suspend fun getBalance(asset: Asset, forceRefresh: Boolean = false): Result<OnChainBalance>

    /**
     * Fetches a fresh provider snapshot for transactional validation without
     * publishing that snapshot to the shared balance cache.
     */
    suspend fun getFreshBalanceForPreflight(asset: Asset): Result<OnChainBalance>

    suspend fun clearCache()

    /**
     * Monotonic cache/provider data version used to invalidate derived
     * financial views without polling.
     */
    fun observeBalanceInvalidations(): Flow<Long> = flowOf(0L)
}
