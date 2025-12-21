package com.xax.CryptoSavingsTracker.data.export

import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.ReminderFrequency
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatterBuilder
import java.util.Locale

object CsvExportFormatter {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
    }

    private val isoInstantMillis = DateTimeFormatterBuilder()
        .appendInstant(3)
        .toFormatter(Locale.US)

    fun makeGoalsCsv(
        goals: List<Goal>,
        allocations: List<Allocation>,
        assetsById: Map<String, Asset>
    ): String {
        val goalNameById = goals.associate { it.id to it.name }
        val allocationsByGoalId = allocations.groupBy { it.goalId }

        val header = listOf(
            "id",
            "name",
            "currency",
            "targetAmount",
            "deadline",
            "startDate",
            "lifecycleStatusRawValue",
            "lifecycleStatusChangedAt",
            "lastModifiedDate",
            "reminderFrequency",
            "reminderTime",
            "firstReminderDate",
            "emoji",
            "goalDescription",
            "link",
            "allocationCount",
            "allocationIds",
            "allocationsJson"
        )

        val rows = goals
            .sortedBy { it.name.lowercase(Locale.US) }
            .map { goal ->
                val goalAllocations = allocationsByGoalId[goal.id].orEmpty()
                val allocationIds = goalAllocations.joinToString(separator = ";") { it.id }

                listOf(
                    goal.id,
                    goal.name,
                    goal.currency,
                    CsvFormatting.double(goal.targetAmount),
                    CsvFormatting.localDate(goal.deadline),
                    CsvFormatting.localDate(goal.startDate),
                    goal.lifecycleStatus.rawValue,
                    CsvFormatting.instantMillisOptional(goal.lifecycleStatusChangedAt),
                    CsvFormatting.instantMillis(goal.updatedAt),
                    CsvFormatting.reminderFrequency(goal.reminderFrequency),
                    CsvFormatting.instantMillisOptional(goal.reminderTimeMillis),
                    CsvFormatting.localDateOptional(goal.firstReminderDate),
                    goal.emoji.orEmpty(),
                    goal.description.orEmpty(),
                    goal.link.orEmpty(),
                    goalAllocations.size.toString(),
                    allocationIds,
                    allocationsJson(
                        allocations = goalAllocations,
                        assetsById = assetsById,
                        goalNameById = goalNameById
                    )
                )
            }

        return CsvWriter.csv(header = header, rows = rows)
    }

    fun makeAssetsCsv(
        assets: List<Asset>,
        allocations: List<Allocation>,
        transactions: List<Transaction>,
        goalNameById: Map<String, String>
    ): String {
        val allocationsByAssetId = allocations.groupBy { it.assetId }
        val transactionsByAssetId = transactions.groupBy { it.assetId }

        val header = listOf(
            "id",
            "currency",
            "address",
            "chainId",
            "transactionCount",
            "transactionIds",
            "allocationCount",
            "allocationIds",
            "allocationsJson"
        )

        val rows = assets
            .sortedBy { it.currency.lowercase(Locale.US) }
            .map { asset ->
                val assetTransactions = transactionsByAssetId[asset.id].orEmpty()
                    .sortedBy { it.dateMillis }
                val assetAllocations = allocationsByAssetId[asset.id].orEmpty()
                val transactionIds = assetTransactions.joinToString(separator = ";") { it.id }
                val allocationIds = assetAllocations.joinToString(separator = ";") { it.id }

                listOf(
                    asset.id,
                    asset.currency,
                    asset.address.orEmpty(),
                    asset.chainId.orEmpty(),
                    assetTransactions.size.toString(),
                    transactionIds,
                    assetAllocations.size.toString(),
                    allocationIds,
                    allocationsJson(
                        allocations = assetAllocations,
                        assetsById = mapOf(asset.id to asset),
                        goalNameById = goalNameById
                    )
                )
            }

        return CsvWriter.csv(header = header, rows = rows)
    }

    fun makeValueChangesCsv(
        transactions: List<Transaction>,
        allocationHistories: List<AllocationHistory>,
        goals: List<Goal>,
        assets: List<Asset>
    ): String {
        val goalNameById = goals.associate { it.id to it.name }
        val assetById = assets.associateBy { it.id }

        data class ValueChangeEvent(val timestampMillis: Long, val row: List<String>)

        val header = listOf(
            "eventType",
            "eventId",
            "timestamp",
            "amount",
            "amountSemantics",
            "assetId",
            "assetCurrency",
            "assetChainId",
            "assetAddress",
            "goalId",
            "goalName",
            "transactionSource",
            "transactionExternalId",
            "transactionCounterparty",
            "transactionComment",
            "allocationMonthLabel",
            "allocationCreatedAt"
        )

        val events = ArrayList<ValueChangeEvent>(transactions.size + allocationHistories.size)

        for (tx in transactions.sortedBy { it.dateMillis }) {
            val asset = assetById[tx.assetId]
            val row = listOf(
                "transaction",
                tx.id,
                CsvFormatting.instantMillis(tx.dateMillis),
                CsvFormatting.double(tx.amount),
                "delta",
                tx.assetId,
                asset?.currency.orEmpty(),
                asset?.chainId.orEmpty(),
                asset?.address.orEmpty(),
                "",
                "",
                CsvFormatting.transactionSource(tx.source),
                tx.externalId.orEmpty(),
                tx.counterparty.orEmpty(),
                tx.comment.orEmpty(),
                "",
                ""
            )
            events.add(ValueChangeEvent(timestampMillis = tx.dateMillis, row = row))
        }

        for (history in allocationHistories.sortedBy { it.timestamp }) {
            val asset = assetById[history.assetId]
            val goalName = goalNameById[history.goalId].orEmpty()
            val row = listOf(
                "allocationHistory",
                history.id,
                CsvFormatting.instantMillis(history.timestamp),
                CsvFormatting.double(history.amount),
                "allocationTargetSnapshot",
                history.assetId,
                asset?.currency.orEmpty(),
                asset?.chainId.orEmpty(),
                asset?.address.orEmpty(),
                history.goalId,
                goalName,
                "",
                "",
                "",
                "",
                history.monthLabel,
                CsvFormatting.instantMillis(history.createdAt)
            )
            events.add(ValueChangeEvent(timestampMillis = history.timestamp, row = row))
        }

        val sortedRows = events
            .sortedBy { it.timestampMillis }
            .map { it.row }

        return CsvWriter.csv(header = header, rows = sortedRows)
    }

    fun safeTimestampForDirectory(exportedAt: Instant): String {
        val raw = isoInstantMillis.format(exportedAt)
        return raw
            .replace(":", "-")
            .replace(".", "-")
    }

    private fun allocationsJson(
        allocations: List<Allocation>,
        assetsById: Map<String, Asset>,
        goalNameById: Map<String, String>
    ): String {
        @Serializable
        data class ExportAllocation(
            val id: String,
            val amount: Double,
            val createdDate: String,
            val lastModifiedDate: String,
            val assetId: String,
            val goalId: String,
            val assetCurrency: String,
            val goalName: String
        )

        val exportAllocations = allocations.map { allocation ->
            val asset = assetsById[allocation.assetId]
            ExportAllocation(
                id = allocation.id,
                amount = allocation.amount,
                createdDate = CsvFormatting.instantMillis(allocation.createdAt),
                lastModifiedDate = CsvFormatting.instantMillis(allocation.lastModifiedAt),
                assetId = allocation.assetId,
                goalId = allocation.goalId,
                assetCurrency = asset?.currency.orEmpty(),
                goalName = goalNameById[allocation.goalId].orEmpty()
            )
        }

        return runCatching { json.encodeToString(exportAllocations) }.getOrDefault("")
    }

    private object CsvFormatting {
        fun instantMillis(millis: Long): String = isoInstantMillis.format(Instant.ofEpochMilli(millis))

        fun instantMillisOptional(millis: Long?): String = millis?.let(::instantMillis).orEmpty()

        fun localDate(date: LocalDate): String {
            val instant = date.atStartOfDay(ZoneOffset.UTC).toInstant()
            return isoInstantMillis.format(instant)
        }

        fun localDateOptional(date: LocalDate?): String = date?.let(::localDate).orEmpty()

        fun double(value: Double): String = value.toString()

        fun reminderFrequency(frequency: ReminderFrequency?): String {
            return when (frequency) {
                null -> ""
                ReminderFrequency.WEEKLY -> "weekly"
                ReminderFrequency.BIWEEKLY -> "biweekly"
                ReminderFrequency.MONTHLY -> "monthly"
                ReminderFrequency.DAILY -> "daily"
            }
        }

        fun transactionSource(source: com.xax.CryptoSavingsTracker.domain.model.TransactionSource): String {
            return when (source) {
                com.xax.CryptoSavingsTracker.domain.model.TransactionSource.MANUAL -> "manual"
                com.xax.CryptoSavingsTracker.domain.model.TransactionSource.ON_CHAIN -> "onChain"
                com.xax.CryptoSavingsTracker.domain.model.TransactionSource.IMPORT -> "import"
            }
        }
    }

    private object CsvWriter {
        fun csv(header: List<String>, rows: List<List<String>>): String {
            val lines = ArrayList<String>(rows.size + 1)
            lines.add(line(header))
            for (row in rows) lines.add(line(row))
            return lines.joinToString(separator = "\n", postfix = "\n")
        }

        private fun line(values: List<String>): String = values.joinToString(separator = ",") { escape(it) }

        private fun escape(value: String): String {
            val needsQuoting = value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r')
            if (!needsQuoting) return value
            val escaped = value.replace("\"", "\"\"")
            return "\"$escaped\""
        }
    }
}

