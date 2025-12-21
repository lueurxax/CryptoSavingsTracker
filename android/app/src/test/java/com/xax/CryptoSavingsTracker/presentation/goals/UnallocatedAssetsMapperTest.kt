package com.xax.CryptoSavingsTracker.presentation.goals

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AssetAllocationStatus
import org.junit.jupiter.api.Test

class UnallocatedAssetsMapperTest {
    @Test
    fun fromStatuses_filtersTinyUnallocated_andComputesPercent() {
        val asset = Asset(
            id = "a1",
            currency = "BTC",
            address = "bc1qexample",
            chainId = "bitcoin",
            createdAt = 1L,
            updatedAt = 1L
        )

        val tiny = AssetAllocationStatus(
            asset = asset,
            totalBalance = 1.0,
            totalAllocated = 1.0,
            allocationDelta = 0.0,
            unallocatedAmount = 0.00000001,
            isFullyAllocated = true,
            isOverAllocated = false
        )
        val real = AssetAllocationStatus(
            asset = asset.copy(id = "a2"),
            totalBalance = 10.0,
            totalAllocated = 6.0,
            allocationDelta = 4.0,
            unallocatedAmount = 4.0,
            isFullyAllocated = false,
            isOverAllocated = false
        )

        val result = UnallocatedAssetsMapper.fromStatuses(listOf(tiny, real))
        assertThat(result).hasSize(1)
        assertThat(result.first().assetId).isEqualTo("a2")
        assertThat(result.first().unallocatedPercentage).isEqualTo(40)
    }
}

