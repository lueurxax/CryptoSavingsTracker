package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import kotlinx.coroutines.flow.StateFlow

interface OnChainBalanceRepository {
    /** Changes after a successful cache refresh or invalidation; cache reads do not emit. */
    val balanceChanges: StateFlow<Long>

    suspend fun getBalance(asset: Asset, forceRefresh: Boolean = false): Result<OnChainBalance>
    suspend fun clearCache()
}

