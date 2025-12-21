package com.xax.CryptoSavingsTracker.presentation.goals

import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AssetAllocationStatus
import kotlin.math.max
import kotlin.math.min

data class UnallocatedAssetWarning(
    val assetId: String,
    val currency: String,
    val address: String?,
    val chainId: String?,
    val unallocatedPercentage: Int,
    val unallocatedAmount: Double
)

object UnallocatedAssetsMapper {
    private const val EPSILON = 0.0000001

    fun fromStatuses(statuses: List<AssetAllocationStatus>): List<UnallocatedAssetWarning> {
        return statuses
            .filter { it.unallocatedAmount > EPSILON }
            .map { status ->
                val balance = status.totalBalance
                val percent = if (balance > 0.0) {
                    (min(1.0, max(0.0, status.unallocatedAmount / balance)) * 100).toInt()
                } else {
                    0
                }
                UnallocatedAssetWarning(
                    assetId = status.asset.id,
                    currency = status.asset.currency,
                    address = status.asset.address,
                    chainId = status.asset.chainId,
                    unallocatedPercentage = percent,
                    unallocatedAmount = status.unallocatedAmount
                )
            }
            .sortedWith(
                compareByDescending<UnallocatedAssetWarning> { it.unallocatedPercentage }
                    .thenByDescending { it.unallocatedAmount }
            )
    }
}

