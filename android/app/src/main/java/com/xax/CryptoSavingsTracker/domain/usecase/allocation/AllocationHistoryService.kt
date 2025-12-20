package com.xax.CryptoSavingsTracker.domain.usecase.allocation

import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Service for managing allocation history snapshots.
 * Creates snapshots when allocations are added, updated, or deleted.
 * Matches iOS behavior for execution tracking.
 */
@Singleton
class AllocationHistoryService @Inject constructor(
    private val allocationHistoryRepository: AllocationHistoryRepository
) {

    /**
     * Create a snapshot of an allocation change.
     * @param allocation The allocation that was changed
     */
    suspend fun createSnapshot(allocation: Allocation) {
        val now = System.currentTimeMillis()
        val snapshot = AllocationHistory(
            id = UUID.randomUUID().toString(),
            assetId = allocation.assetId,
            goalId = allocation.goalId,
            amount = allocation.amount,
            monthLabel = generateMonthLabel(now),
            timestamp = now,
            createdAt = now
        )
        allocationHistoryRepository.insert(snapshot)
    }

    /**
     * Create a snapshot for an allocation deletion (amount = 0).
     * @param assetId The asset ID of the deleted allocation
     * @param goalId The goal ID of the deleted allocation
     */
    suspend fun createDeletionSnapshot(assetId: String, goalId: String) {
        val now = System.currentTimeMillis()
        val snapshot = AllocationHistory(
            id = UUID.randomUUID().toString(),
            assetId = assetId,
            goalId = goalId,
            amount = 0.0,
            monthLabel = generateMonthLabel(now),
            timestamp = now,
            createdAt = now
        )
        allocationHistoryRepository.insert(snapshot)
    }

    /**
     * Get the current month label.
     * @return Month label in format "2025-01" for January 2025
     */
    fun getCurrentMonthLabel(): String {
        return generateMonthLabel(System.currentTimeMillis())
    }

    companion object {
        private val MONTH_LABEL_FORMATTER = DateTimeFormatter.ofPattern("yyyy-MM")

        /**
         * Generate a month label from a timestamp.
         * @param timestampMillis Timestamp in UTC milliseconds
         * @return Month label in format "2025-01" for January 2025
         */
        fun generateMonthLabel(timestampMillis: Long): String {
            val instant = Instant.ofEpochMilli(timestampMillis)
            val localDate = LocalDate.ofInstant(instant, ZoneOffset.UTC)
            return localDate.format(MONTH_LABEL_FORMATTER)
        }

        /**
         * Generate a month label from a LocalDate.
         */
        fun generateMonthLabel(date: LocalDate): String {
            return date.format(MONTH_LABEL_FORMATTER)
        }
    }
}
