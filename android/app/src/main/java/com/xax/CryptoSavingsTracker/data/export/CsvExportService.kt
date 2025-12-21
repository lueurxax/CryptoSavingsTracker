package com.xax.CryptoSavingsTracker.data.export

import android.content.Context
import android.net.Uri
import androidx.core.content.FileProvider
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

data class CsvExportResult(
    val fileUris: List<Uri>,
    val exportDirectory: File
)

@Singleton
class CsvExportService @Inject constructor(
    @ApplicationContext private val context: Context,
    private val goalRepository: GoalRepository,
    private val assetRepository: AssetRepository,
    private val allocationRepository: AllocationRepository,
    private val transactionRepository: TransactionRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository
) {
    suspend fun exportCsvFiles(exportedAt: Instant = Instant.now()): CsvExportResult = withContext(Dispatchers.IO) {
        val goals = goalRepository.getAllGoals().first()
        val assets = assetRepository.getAllAssets().first()

        val allocations = buildList {
            for (goal in goals) {
                addAll(allocationRepository.getAllocationsForGoal(goal.id))
            }
        }

        val transactions = transactionRepository.getAllTransactions().first()
        val allocationHistories = allocationHistoryRepository.getAll().first()

        val assetsById = assets.associateBy { it.id }
        val goalNameById = goals.associate { it.id to it.name }

        val exportDirectory = makeExportDirectory(exportedAt = exportedAt)

        val goalsFile = File(exportDirectory, "goals.csv").also {
            it.writeText(CsvExportFormatter.makeGoalsCsv(goals, allocations, assetsById), Charsets.UTF_8)
        }
        val assetsFile = File(exportDirectory, "assets.csv").also {
            it.writeText(CsvExportFormatter.makeAssetsCsv(assets, allocations, transactions, goalNameById), Charsets.UTF_8)
        }
        val valueChangesFile = File(exportDirectory, "value_changes.csv").also {
            it.writeText(
                CsvExportFormatter.makeValueChangesCsv(
                    transactions = transactions,
                    allocationHistories = allocationHistories,
                    goals = goals,
                    assets = assets
                ),
                Charsets.UTF_8
            )
        }

        val uris = listOf(goalsFile, assetsFile, valueChangesFile).map { file ->
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        }

        CsvExportResult(fileUris = uris, exportDirectory = exportDirectory)
    }

    private fun makeExportDirectory(exportedAt: Instant): File {
        val exportsRoot = File(context.cacheDir, "exports").also { it.mkdirs() }
        val directoryName = "CryptoSavingsTracker-CSV-${CsvExportFormatter.safeTimestampForDirectory(exportedAt)}"
        val dir = File(exportsRoot, directoryName)
        if (dir.exists()) dir.deleteRecursively()
        dir.mkdirs()
        return dir
    }
}

