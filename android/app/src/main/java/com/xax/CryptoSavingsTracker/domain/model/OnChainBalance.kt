package com.xax.CryptoSavingsTracker.domain.model

data class OnChainBalance(
    val assetId: String,
    val chainId: String,
    val address: String,
    val currency: String,
    val balance: Double,
    val fetchedAtMillis: Long,
    val isStale: Boolean
)

