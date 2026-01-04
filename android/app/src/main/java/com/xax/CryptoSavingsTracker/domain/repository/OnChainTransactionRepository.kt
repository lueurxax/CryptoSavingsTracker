package com.xax.CryptoSavingsTracker.domain.repository

import com.xax.CryptoSavingsTracker.domain.model.Asset

/**
 * Fetches and imports on-chain transactions for a tracked asset address.
 *
 * iOS parity: on-chain transactions are stored locally as Transaction rows (source: ON_CHAIN)
 * so execution tracking can remain timestamp-based without relying on network at calculation time.
 */
interface OnChainTransactionRepository {
    /**
     * Refresh on-chain transactions for an asset.
     *
     * @return number of inserted/updated transactions
     */
    suspend fun refresh(asset: Asset, limit: Int = 20, forceRefresh: Boolean = false): Result<Int>
}

