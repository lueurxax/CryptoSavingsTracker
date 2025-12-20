package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance

interface OnChainBalanceRepository {
    suspend fun getBalance(asset: Asset, forceRefresh: Boolean = false): Result<OnChainBalance>
    suspend fun clearCache()
}

