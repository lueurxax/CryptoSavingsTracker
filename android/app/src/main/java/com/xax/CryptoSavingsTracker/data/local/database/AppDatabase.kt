package com.xax.CryptoSavingsTracker.data.local.database

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.xax.CryptoSavingsTracker.data.local.database.converter.Converters
import com.xax.CryptoSavingsTracker.data.local.database.dao.AllocationDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.AllocationHistoryDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.AssetDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.CompletedExecutionDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.ExecutionRecordDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.ExecutionSnapshotDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.GoalDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.MonthlyGoalPlanDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.MonthlyPlanDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.TransactionDao
import com.xax.CryptoSavingsTracker.data.local.database.entity.AllocationHistoryEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetAllocationEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.AssetEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.CompletedExecutionEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.ExecutionSnapshotEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.GoalEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.MonthlyGoalPlanEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.MonthlyExecutionRecordEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.MonthlyPlanEntity
import com.xax.CryptoSavingsTracker.data.local.database.entity.TransactionEntity

@Database(
    entities = [
        GoalEntity::class,
        AssetEntity::class,
        TransactionEntity::class,
        AssetAllocationEntity::class,
        AllocationHistoryEntity::class,
        MonthlyPlanEntity::class,
        MonthlyGoalPlanEntity::class,
        MonthlyExecutionRecordEntity::class,
        ExecutionSnapshotEntity::class,
        CompletedExecutionEntity::class
    ],
    version = 2,
    exportSchema = true
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {

    abstract fun goalDao(): GoalDao
    abstract fun assetDao(): AssetDao
    abstract fun transactionDao(): TransactionDao
    abstract fun allocationDao(): AllocationDao
    abstract fun allocationHistoryDao(): AllocationHistoryDao
    abstract fun monthlyPlanDao(): MonthlyPlanDao
    abstract fun monthlyGoalPlanDao(): MonthlyGoalPlanDao
    abstract fun executionRecordDao(): ExecutionRecordDao
    abstract fun executionSnapshotDao(): ExecutionSnapshotDao
    abstract fun completedExecutionDao(): CompletedExecutionDao

    companion object {
        const val DATABASE_NAME = "crypto_savings_tracker.db"
    }
}
