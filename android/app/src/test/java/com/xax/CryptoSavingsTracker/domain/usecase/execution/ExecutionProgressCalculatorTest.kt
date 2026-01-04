package com.xax.CryptoSavingsTracker.domain.usecase.execution

import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.ExecutionSnapshot
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID

/**
 * Tests for ExecutionProgressCalculator, focusing on time-window edge cases
 * to ensure iOS parity for execution tracking.
 */
class ExecutionProgressCalculatorTest {

    private lateinit var calculator: ExecutionProgressCalculator

    @BeforeEach
    fun setup() {
        calculator = ExecutionProgressCalculator()
    }

    private fun createSnapshot(
        goalId: String = "goal-1",
        goalName: String = "Test Goal",
        requiredAmount: Double = 1000.0,
        isSkipped: Boolean = false
    ) = ExecutionSnapshot(
        id = UUID.randomUUID().toString(),
        executionRecordId = "exec-1",
        goalId = goalId,
        goalName = goalName,
        currency = "USD",
        targetAmount = 10000.0,
        currentTotalAtStart = 0.0,
        requiredAmount = requiredAmount,
        isProtected = false,
        isSkipped = isSkipped,
        customAmount = null,
        createdAtMillis = System.currentTimeMillis()
    )

    private fun createTransaction(
        assetId: String = "asset-1",
        amount: Double,
        dateMillis: Long
    ) = Transaction(
        id = UUID.randomUUID().toString(),
        assetId = assetId,
        amount = amount,
        dateMillis = dateMillis,
        source = TransactionSource.MANUAL,
        externalId = null,
        counterparty = null,
        comment = null,
        createdAt = dateMillis
    )

    private fun createAllocationHistory(
        assetId: String = "asset-1",
        goalId: String = "goal-1",
        amount: Double,
        timestamp: Long
    ) = AllocationHistory(
        id = UUID.randomUUID().toString(),
        assetId = assetId,
        goalId = goalId,
        amount = amount,
        monthLabel = "2025-12",
        timestamp = timestamp,
        createdAt = timestamp
    )

    private fun toMillis(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0): Long {
        return LocalDateTime.of(year, month, day, hour, minute, second)
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli()
    }

    @Nested
    @DisplayName("Basic Window Filtering")
    inner class BasicWindowFiltering {

        @Test
        fun `transaction exactly at startedAtMillis is INCLUDED`() {
            val startedAt = toMillis(2025, 12, 21, 12, 0, 0)
            val snapshot = createSnapshot()
            val allocation = createAllocationHistory(amount = 1000.0, timestamp = startedAt - 1000)
            val transaction = createTransaction(amount = 500.0, dateMillis = startedAt) // Exact boundary

            val result = calculator.calculateForSnapshots(
                snapshots = listOf(snapshot),
                transactions = listOf(transaction),
                allocationHistory = listOf(allocation),
                startedAtMillis = startedAt,
                nowMillis = startedAt + 60_000
            )

            assertThat(result).hasSize(1)
            assertThat(result[0].contributed).isEqualTo(500.0)
        }

        @Test
        fun `transaction 1ms before startedAtMillis is EXCLUDED`() {
            val startedAt = toMillis(2025, 12, 21, 12, 0, 0)
            val snapshot = createSnapshot()
            val allocation = createAllocationHistory(amount = 1000.0, timestamp = startedAt - 2000)
            val transaction = createTransaction(amount = 500.0, dateMillis = startedAt - 1) // 1ms before

            val result = calculator.calculateForSnapshots(
                snapshots = listOf(snapshot),
                transactions = listOf(transaction),
                allocationHistory = listOf(allocation),
                startedAtMillis = startedAt,
                nowMillis = startedAt + 60_000
            )

            assertThat(result).hasSize(1)
            assertThat(result[0].contributed).isEqualTo(0.0) // Pre-start transaction doesn't count
        }

        @Test
        fun `transaction after nowMillis is EXCLUDED`() {
            val startedAt = toMillis(2025, 12, 21, 12, 0, 0)
            val now = startedAt + 60_000
            val snapshot = createSnapshot()
            val allocation = createAllocationHistory(amount = 1000.0, timestamp = startedAt - 1000)
            val transaction = createTransaction(amount = 500.0, dateMillis = now + 1000) // After now

            val result = calculator.calculateForSnapshots(
                snapshots = listOf(snapshot),
                transactions = listOf(transaction),
                allocationHistory = listOf(allocation),
                startedAtMillis = startedAt,
                nowMillis = now
            )

            assertThat(result).hasSize(1)
            assertThat(result[0].contributed).isEqualTo(0.0)
        }
    }

    @Nested
    @DisplayName("Time-Window Edge Cases")
    inner class TimeWindowEdgeCases {

        @Test
        fun `end of day - execution at 11_55 PM, transaction at 11_58 PM is included`() {
            val startedAt = toMillis(2025, 12, 21, 23, 55, 0) // 11:55 PM
            val txTime = toMillis(2025, 12, 21, 23, 58, 0) // 11:58 PM
            val now = toMillis(2025, 12, 21, 23, 59, 0)

            val snapshot = createSnapshot()
            val allocation = createAllocationHistory(amount = 1000.0, timestamp = startedAt - 1000)
            val transaction = createTransaction(amount = 500.0, dateMillis = txTime)

            val result = calculator.calculateForSnapshots(
                snapshots = listOf(snapshot),
                transactions = listOf(transaction),
                allocationHistory = listOf(allocation),
                startedAtMillis = startedAt,
                nowMillis = now
            )

            assertThat(result).hasSize(1)
            assertThat(result[0].contributed).isEqualTo(500.0)
        }

        @Test
        fun `midnight crossing - start at 11_55 PM Day1, transaction at 12_05 AM Day2 is included`() {
            val startedAt = toMillis(2025, 12, 21, 23, 55, 0) // 11:55 PM Dec 21
            val txTime = toMillis(2025, 12, 22, 0, 5, 0) // 12:05 AM Dec 22
            val now = toMillis(2025, 12, 22, 0, 10, 0)

            val snapshot = createSnapshot()
            val allocation = createAllocationHistory(amount = 1000.0, timestamp = startedAt - 1000)
            val transaction = createTransaction(amount = 500.0, dateMillis = txTime)

            val result = calculator.calculateForSnapshots(
                snapshots = listOf(snapshot),
                transactions = listOf(transaction),
                allocationHistory = listOf(allocation),
                startedAtMillis = startedAt,
                nowMillis = now
            )

            assertThat(result).hasSize(1)
            assertThat(result[0].contributed).isEqualTo(500.0)
        }

        @Test
        fun `multiple transactions in window accumulate correctly`() {
            val startedAt = toMillis(2025, 12, 21, 10, 0, 0)
            val now = toMillis(2025, 12, 21, 18, 0, 0)

            val snapshot = createSnapshot()
            val allocation = createAllocationHistory(amount = 1000.0, timestamp = startedAt - 1000)
            val transactions = listOf(
                createTransaction(amount = 200.0, dateMillis = toMillis(2025, 12, 21, 11, 0, 0)),
                createTransaction(amount = 300.0, dateMillis = toMillis(2025, 12, 21, 14, 0, 0)),
                createTransaction(amount = 100.0, dateMillis = toMillis(2025, 12, 21, 16, 0, 0))
            )

            val result = calculator.calculateForSnapshots(
                snapshots = listOf(snapshot),
                transactions = transactions,
                allocationHistory = listOf(allocation),
                startedAtMillis = startedAt,
                nowMillis = now
            )

            assertThat(result).hasSize(1)
            assertThat(result[0].contributed).isEqualTo(600.0) // 200 + 300 + 100
        }

        @Test
        fun `pre-start transactions count toward balance but not contributions`() {
            val startedAt = toMillis(2025, 12, 21, 12, 0, 0)
            val now = toMillis(2025, 12, 21, 18, 0, 0)

            val snapshot = createSnapshot()
            val allocation = createAllocationHistory(amount = 1000.0, timestamp = startedAt - 100_000)

            // Pre-start balance: 800
            val preStartTx = createTransaction(amount = 800.0, dateMillis = startedAt - 50_000)
            // In-window deposit: 200 (should max out at target)
            val inWindowTx = createTransaction(amount = 200.0, dateMillis = startedAt + 60_000)

            val result = calculator.calculateForSnapshots(
                snapshots = listOf(snapshot),
                transactions = listOf(preStartTx, inWindowTx),
                allocationHistory = listOf(allocation),
                startedAtMillis = startedAt,
                nowMillis = now
            )

            assertThat(result).hasSize(1)
            // Only the in-window transaction counts as contribution
            assertThat(result[0].contributed).isEqualTo(200.0)
        }
    }

    @Nested
    @DisplayName("Fulfillment Status")
    inner class FulfillmentStatus {

        @Test
        fun `goal is fulfilled when contributed equals planned`() {
            val startedAt = toMillis(2025, 12, 21, 12, 0, 0)
            val now = toMillis(2025, 12, 21, 18, 0, 0)

            val snapshot = createSnapshot(requiredAmount = 500.0)
            val allocation = createAllocationHistory(amount = 500.0, timestamp = startedAt - 1000)
            val transaction = createTransaction(amount = 500.0, dateMillis = startedAt + 60_000)

            val result = calculator.calculateForSnapshots(
                snapshots = listOf(snapshot),
                transactions = listOf(transaction),
                allocationHistory = listOf(allocation),
                startedAtMillis = startedAt,
                nowMillis = now
            )

            assertThat(result).hasSize(1)
            assertThat(result[0].contributed).isEqualTo(500.0)
            assertThat(result[0].isFulfilled).isTrue()
        }

        @Test
        fun `goal is fulfilled when contributed exceeds planned`() {
            val startedAt = toMillis(2025, 12, 21, 12, 0, 0)
            val now = toMillis(2025, 12, 21, 18, 0, 0)

            val snapshot = createSnapshot(requiredAmount = 500.0)
            val allocation = createAllocationHistory(amount = 1000.0, timestamp = startedAt - 1000)
            val transaction = createTransaction(amount = 700.0, dateMillis = startedAt + 60_000)

            val result = calculator.calculateForSnapshots(
                snapshots = listOf(snapshot),
                transactions = listOf(transaction),
                allocationHistory = listOf(allocation),
                startedAtMillis = startedAt,
                nowMillis = now
            )

            assertThat(result).hasSize(1)
            assertThat(result[0].contributed).isEqualTo(700.0)
            assertThat(result[0].isFulfilled).isTrue()
        }

        @Test
        fun `goal is not fulfilled when contributed less than planned`() {
            val startedAt = toMillis(2025, 12, 21, 12, 0, 0)
            val now = toMillis(2025, 12, 21, 18, 0, 0)

            val snapshot = createSnapshot(requiredAmount = 500.0)
            val allocation = createAllocationHistory(amount = 500.0, timestamp = startedAt - 1000)
            val transaction = createTransaction(amount = 300.0, dateMillis = startedAt + 60_000)

            val result = calculator.calculateForSnapshots(
                snapshots = listOf(snapshot),
                transactions = listOf(transaction),
                allocationHistory = listOf(allocation),
                startedAtMillis = startedAt,
                nowMillis = now
            )

            assertThat(result).hasSize(1)
            assertThat(result[0].contributed).isEqualTo(300.0)
            assertThat(result[0].isFulfilled).isFalse()
            assertThat(result[0].progressPercent).isEqualTo(60) // 300/500 = 60%
        }
    }

    @Nested
    @DisplayName("Empty and Edge States")
    inner class EmptyAndEdgeStates {

        @Test
        fun `empty snapshots returns empty list`() {
            val result = calculator.calculateForSnapshots(
                snapshots = emptyList(),
                transactions = emptyList(),
                allocationHistory = emptyList(),
                startedAtMillis = System.currentTimeMillis(),
                nowMillis = System.currentTimeMillis()
            )

            assertThat(result).isEmpty()
        }

        @Test
        fun `zero startedAtMillis returns zero contributions`() {
            val snapshot = createSnapshot()

            val result = calculator.calculateForSnapshots(
                snapshots = listOf(snapshot),
                transactions = emptyList(),
                allocationHistory = emptyList(),
                startedAtMillis = 0L,
                nowMillis = System.currentTimeMillis()
            )

            assertThat(result).hasSize(1)
            assertThat(result[0].contributed).isEqualTo(0.0)
        }

        @Test
        fun `skipped goals are included but have zero contribution`() {
            val startedAt = toMillis(2025, 12, 21, 12, 0, 0)
            val snapshot = createSnapshot(isSkipped = true, requiredAmount = 500.0)

            val result = calculator.calculateForSnapshots(
                snapshots = listOf(snapshot),
                transactions = emptyList(),
                allocationHistory = emptyList(),
                startedAtMillis = startedAt,
                nowMillis = startedAt + 60_000
            )

            assertThat(result).hasSize(1)
            assertThat(result[0].snapshot.isSkipped).isTrue()
            assertThat(result[0].contributed).isEqualTo(0.0)
        }
    }
}
