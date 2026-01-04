package com.xax.CryptoSavingsTracker.di

import android.content.Context
import androidx.room.Room
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
import com.xax.CryptoSavingsTracker.data.local.database.dao.MonthlyGoalPlanDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.AllocationDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.AllocationHistoryDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.AssetDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.CompletedExecutionDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.ExecutionRecordDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.ExecutionSnapshotDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.GoalDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.MonthlyPlanDao
import com.xax.CryptoSavingsTracker.data.local.database.dao.TransactionDao
import com.xax.CryptoSavingsTracker.data.local.database.migration.DatabaseMigrations
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.databaseBuilder(
            context,
            AppDatabase::class.java,
            AppDatabase.DATABASE_NAME
        )
            .addMigrations(
                DatabaseMigrations.MIGRATION_1_2,
                DatabaseMigrations.MIGRATION_2_3
            )
            .fallbackToDestructiveMigrationOnDowngrade()
            .build()
    }

    @Provides
    fun provideGoalDao(database: AppDatabase): GoalDao = database.goalDao()

    @Provides
    fun provideAssetDao(database: AppDatabase): AssetDao = database.assetDao()

    @Provides
    fun provideTransactionDao(database: AppDatabase): TransactionDao = database.transactionDao()

    @Provides
    fun provideAllocationDao(database: AppDatabase): AllocationDao = database.allocationDao()

    @Provides
    fun provideAllocationHistoryDao(database: AppDatabase): AllocationHistoryDao = database.allocationHistoryDao()

    @Provides
    fun provideMonthlyPlanDao(database: AppDatabase): MonthlyPlanDao = database.monthlyPlanDao()

    @Provides
    fun provideMonthlyGoalPlanDao(database: AppDatabase): MonthlyGoalPlanDao = database.monthlyGoalPlanDao()

    @Provides
    fun provideExecutionRecordDao(database: AppDatabase): ExecutionRecordDao = database.executionRecordDao()

    @Provides
    fun provideExecutionSnapshotDao(database: AppDatabase): ExecutionSnapshotDao = database.executionSnapshotDao()

    @Provides
    fun provideCompletedExecutionDao(database: AppDatabase): CompletedExecutionDao = database.completedExecutionDao()
}
