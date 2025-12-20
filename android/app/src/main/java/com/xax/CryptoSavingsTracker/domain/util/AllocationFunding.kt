package com.xax.CryptoSavingsTracker.domain.util

import kotlin.math.max
import kotlin.math.min

object AllocationFunding {
    fun fundedPortion(
        allocationAmount: Double,
        assetBalance: Double,
        totalAllocatedForAsset: Double
    ): Double {
        val target = max(0.0, allocationAmount)
        val balance = max(0.0, assetBalance)
        val total = max(0.0, totalAllocatedForAsset)

        if (target == 0.0 || balance == 0.0 || total == 0.0) return 0.0

        val ratio = min(1.0, balance / total)
        return target * ratio
    }
}

