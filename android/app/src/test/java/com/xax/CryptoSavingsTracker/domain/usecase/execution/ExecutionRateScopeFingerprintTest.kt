package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class ExecutionRateScopeFingerprintTest {
    @Test
    fun `fingerprint includes allocated assets and ignores unrelated live assets`() = runTest {
        val assetsState = MutableStateFlow(
            listOf(
                asset(id = "asset-1", currency = "BTC"),
                asset(id = "unallocated-asset", currency = "ETH")
            )
        )
        val allocationsByAsset = mutableMapOf(
            "asset-1" to mutableListOf(allocation())
        )
        val assets = mockk<AssetRepository> {
            every { getAllAssets() } returns assetsState
        }
        val allocations = mockk<AllocationRepository> {
            coEvery { getAllocationsForAsset(any()) } answers {
                allocationsByAsset[firstArg()]?.toList().orEmpty()
            }
        }

        val initial = captureExecutionRateScopeFingerprint(assets, allocations, setOf("goal-1"))
        assertThat(initial.assetIds).containsExactly("asset-1")

        assetsState.value = assetsState.value.map { asset ->
            if (asset.id == "unallocated-asset") asset.copy(currency = "USDC") else asset
        }
        val afterUnallocatedCurrencyChange =
            captureExecutionRateScopeFingerprint(assets, allocations, setOf("goal-1"))
        assertThat(afterUnallocatedCurrencyChange).isEqualTo(initial)

        assetsState.value = assetsState.value.map { asset ->
            if (asset.id == "asset-1") asset.copy(currency = "ETH") else asset
        }
        val afterAllocatedCurrencyChange =
            captureExecutionRateScopeFingerprint(assets, allocations, setOf("goal-1"))
        assertThat(afterAllocatedCurrencyChange).isNotEqualTo(initial)

        assetsState.value = assetsState.value.map { asset ->
            if (asset.id == "asset-1") asset.copy(currency = "BTC") else asset
        }
        allocationsByAsset["unallocated-asset"] = mutableListOf(
            allocation(
                id = "allocation-2",
                assetId = "unallocated-asset"
            ).copy(goalId = "archived-goal")
        )
        val afterUnrelatedAllocation =
            captureExecutionRateScopeFingerprint(assets, allocations, setOf("goal-1"))
        assertThat(afterUnrelatedAllocation).isEqualTo(initial)

        allocationsByAsset["unallocated-asset"] = mutableListOf(
            allocation(
                id = "allocation-2",
                assetId = "unallocated-asset"
            )
        )
        val afterNewAllocation =
            captureExecutionRateScopeFingerprint(assets, allocations, setOf("goal-1"))
        assertThat(afterNewAllocation.assetIds)
            .containsExactly("asset-1", "unallocated-asset")
        assertThat(afterNewAllocation).isNotEqualTo(initial)
    }

    @Test
    fun `fingerprint includes every persisted allocation field`() = runTest {
        val assets = mockk<AssetRepository> {
            every { getAllAssets() } returns MutableStateFlow(listOf(asset(currency = "BTC")))
        }
        val original = allocation()
        val allocationsState = mutableListOf(original)
        val allocations = mockk<AllocationRepository> {
            coEvery { getAllocationsForAsset("asset-1") } answers {
                allocationsState.toList()
            }
        }
        val initial = captureExecutionRateScopeFingerprint(assets, allocations, setOf("goal-1"))
        val mutations = listOf(
            original.copy(goalId = "goal-2"),
            original.copy(amount = 2.0),
            original.copy(createdAt = 2_000L),
            original.copy(lastModifiedAt = 2_000L)
        )

        for (mutation in mutations) {
            allocationsState[0] = mutation

            assertThat(captureExecutionRateScopeFingerprint(assets, allocations, setOf("goal-1")))
                .isNotEqualTo(initial)
        }
    }

    private fun asset(
        id: String = "asset-1",
        currency: String
    ) = Asset(
        id = id,
        currency = currency,
        address = null,
        chainId = null,
        createdAt = 1_000L,
        updatedAt = 1_000L
    )

    private fun allocation(
        id: String = "allocation-1",
        assetId: String = "asset-1"
    ) = Allocation(
        id = id,
        assetId = assetId,
        goalId = "goal-1",
        amount = 1.0,
        createdAt = 1_000L,
        lastModifiedAt = 1_000L
    )
}
