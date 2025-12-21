package com.xax.CryptoSavingsTracker.presentation.assets

internal object AssetBalanceCalculator {
    fun totalBalance(manualBalance: Double, onChainBalance: Double?, hasOnChain: Boolean): Double {
        return if (hasOnChain) {
            manualBalance + (onChainBalance ?: 0.0)
        } else {
            manualBalance
        }
    }
}
