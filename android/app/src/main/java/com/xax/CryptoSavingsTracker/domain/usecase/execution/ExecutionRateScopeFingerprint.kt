package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import kotlinx.coroutines.flow.first

internal data class ExecutionRateScopeFingerprint(
    val assets: List<ExecutionRateScopeAsset>,
    val allocations: List<ExecutionRateScopeAllocation>,
    val allocationHistory: List<ExecutionRateScopeHistory>
) {
    val assetIds: Set<String>
        get() = assets.mapTo(linkedSetOf()) { it.id }
}

internal data class ExecutionRateScopeAsset(
    val id: String,
    val currency: String,
    val address: String?,
    val chainId: String?,
    val createdAt: Long,
    val updatedAt: Long
)

internal data class ExecutionRateScopeAllocation(
    val id: String,
    val assetId: String,
    val goalId: String,
    val amountBits: Long,
    val createdAt: Long,
    val lastModifiedAt: Long
)

internal data class ExecutionRateScopeHistory(
    val id: String,
    val assetId: String,
    val goalId: String,
    val amountBits: Long,
    val monthLabel: String,
    val timestamp: Long,
    val createdAt: Long
)

internal suspend fun captureExecutionRateScopeFingerprint(
    assetRepository: AssetRepository,
    allocationRepository: AllocationRepository,
    eligibleGoalIds: Set<String>,
    historicalAllocations: List<AllocationHistory> = emptyList()
): ExecutionRateScopeFingerprint {
    val persistedAssets = assetRepository.getAllAssets().first()
    val assetsById = persistedAssets.associateBy { it.id }

    val persistedAllocations = persistedAssets
        .flatMap { asset ->
            allocationRepository.getAllocationsForAsset(asset.id)
        }
    val scopedAllocations = persistedAllocations
        .filter { allocation -> allocation.goalId in eligibleGoalIds }
    val scopedHistory = historicalAllocations
        .filter { history -> history.goalId in eligibleGoalIds }
    val relevantAssetIds = linkedSetOf<String>().apply {
        scopedAllocations.mapTo(this) { it.assetId }
        scopedHistory.mapTo(this) { it.assetId }
    }

    // Once an asset is in execution scope, sibling goal allocations/history
    // are part of the attribution proof and therefore of the immutable start
    // fingerprint too.
    val allocations = persistedAllocations
        .filter { allocation -> allocation.assetId in relevantAssetIds }
        .map { allocation ->
            ExecutionRateScopeAllocation(
                id = allocation.id,
                assetId = allocation.assetId,
                goalId = allocation.goalId,
                amountBits = allocation.amount.toBits(),
                createdAt = allocation.createdAt,
                lastModifiedAt = allocation.lastModifiedAt
            )
        }
        .sortedWith(
            compareBy<ExecutionRateScopeAllocation>(
                { it.assetId },
                { it.id },
                { it.goalId },
                { it.amountBits },
                { it.createdAt },
                { it.lastModifiedAt }
            )
        )

    val relevantHistory = historicalAllocations
        .asSequence()
        .filter { history -> history.assetId in relevantAssetIds }
        .map { history ->
            ExecutionRateScopeHistory(
                id = history.id,
                assetId = history.assetId,
                goalId = history.goalId,
                amountBits = history.amount.toBits(),
                monthLabel = history.monthLabel,
                timestamp = history.timestamp,
                createdAt = history.createdAt
            )
        }
        .sortedWith(
            compareBy<ExecutionRateScopeHistory>(
                { it.assetId },
                { it.id },
                { it.goalId },
                { it.amountBits },
                { it.monthLabel },
                { it.timestamp },
                { it.createdAt }
            )
        )
        .toList()

    val assets = relevantAssetIds
        .map { assetId ->
            val asset = checkNotNull(assetsById[assetId]) {
                "Allocation references missing asset $assetId"
            }
            ExecutionRateScopeAsset(
                id = asset.id,
                currency = asset.currency.uppercase(),
                address = asset.address,
                chainId = asset.chainId,
                createdAt = asset.createdAt,
                updatedAt = asset.updatedAt
            )
        }
        .sortedBy { it.id }

    return ExecutionRateScopeFingerprint(
        assets = assets,
        allocations = allocations,
        allocationHistory = relevantHistory
    )
}
