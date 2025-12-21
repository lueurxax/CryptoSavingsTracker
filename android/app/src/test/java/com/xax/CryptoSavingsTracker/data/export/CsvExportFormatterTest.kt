package com.xax.CryptoSavingsTracker.data.export

import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.google.common.truth.Truth.assertThat
import org.junit.jupiter.api.Test
import java.time.LocalDate

class CsvExportFormatterTest {

    @Test
    fun goalsCsv_includesAllocationsJson_andEscapesCommas() {
        val goal = Goal(
            id = "g1",
            name = "My Goal",
            currency = "USD",
            targetAmount = 1000.0,
            deadline = LocalDate.of(2026, 1, 1),
            startDate = LocalDate.of(2025, 12, 1),
            lifecycleStatus = GoalLifecycleStatus.ACTIVE,
            lifecycleStatusChangedAt = null,
            emoji = "🙂",
            description = "hello, world",
            link = "https://example.com",
            reminderFrequency = null,
            reminderTimeMillis = null,
            firstReminderDate = null,
            createdAt = 1L,
            updatedAt = 2L
        )
        val asset = Asset(
            id = "a1",
            currency = "BTC",
            address = "bc1q...",
            chainId = "bitcoin",
            createdAt = 1L,
            updatedAt = 2L
        )
        val allocation = Allocation(
            id = "al1",
            assetId = asset.id,
            goalId = goal.id,
            amount = 0.004106,
            createdAt = 1000L,
            lastModifiedAt = 2000L
        )

        val csv = CsvExportFormatter.makeGoalsCsv(
            goals = listOf(goal),
            allocations = listOf(allocation),
            assetsById = mapOf(asset.id to asset)
        )

        assertThat(csv).startsWith("id,name,currency,targetAmount")
        assertThat(csv).contains("\"hello, world\"")
        // JSON is embedded as a CSV field, so quotes may be escaped/doubled.
        assertThat(csv).contains("assetCurrency")
        // BTC should only appear inside allocationsJson for this test row.
        assertThat(csv).contains("BTC")
    }

    @Test
    fun valueChangesCsv_containsTransactionAndAllocationHistoryRows() {
        val goal = Goal(
            id = "g1",
            name = "Goal A",
            currency = "USD",
            targetAmount = 1000.0,
            deadline = LocalDate.of(2026, 1, 1),
            startDate = LocalDate.of(2025, 12, 1),
            lifecycleStatus = GoalLifecycleStatus.ACTIVE,
            lifecycleStatusChangedAt = null,
            emoji = null,
            description = null,
            link = null,
            reminderFrequency = null,
            reminderTimeMillis = null,
            firstReminderDate = null,
            createdAt = 1L,
            updatedAt = 2L
        )
        val asset = Asset(
            id = "a1",
            currency = "BTC",
            address = "bc1q...",
            chainId = "bitcoin",
            createdAt = 1L,
            updatedAt = 2L
        )

        val tx = Transaction(
            id = "t1",
            assetId = asset.id,
            amount = 0.5,
            dateMillis = 10_000L,
            source = TransactionSource.MANUAL,
            externalId = null,
            counterparty = "Binance",
            comment = "Deposit",
            createdAt = 10_000L
        )
        val history = AllocationHistory(
            id = "h1",
            assetId = asset.id,
            goalId = goal.id,
            amount = 0.1,
            monthLabel = "2025-12",
            timestamp = 20_000L,
            createdAt = 20_001L
        )

        val csv = CsvExportFormatter.makeValueChangesCsv(
            transactions = listOf(tx),
            allocationHistories = listOf(history),
            goals = listOf(goal),
            assets = listOf(asset)
        )

        assertThat(csv).contains("\ntransaction,t1,")
        assertThat(csv).contains("\nallocationHistory,h1,")
        assertThat(csv).contains(",allocationTargetSnapshot,")
    }
}
