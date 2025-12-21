package com.xax.CryptoSavingsTracker.di

import android.content.Context
import androidx.room.Room
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
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
import dagger.Module
import dagger.Provides
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dagger.hilt.testing.TestInstallIn
import javax.inject.Singleton

@Module
@TestInstallIn(
    components = [SingletonComponent::class],
    replaces = [DatabaseModule::class]
)
object InMemoryDatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
    }

    @Provides fun provideGoalDao(database: AppDatabase): GoalDao = database.goalDao()
    @Provides fun provideAssetDao(database: AppDatabase): AssetDao = database.assetDao()
    @Provides fun provideTransactionDao(database: AppDatabase): TransactionDao = database.transactionDao()
    @Provides fun provideAllocationDao(database: AppDatabase): AllocationDao = database.allocationDao()
    @Provides fun provideAllocationHistoryDao(database: AppDatabase): AllocationHistoryDao = database.allocationHistoryDao()
    @Provides fun provideMonthlyPlanDao(database: AppDatabase): MonthlyPlanDao = database.monthlyPlanDao()
    @Provides fun provideMonthlyGoalPlanDao(database: AppDatabase): MonthlyGoalPlanDao = database.monthlyGoalPlanDao()
    @Provides fun provideExecutionRecordDao(database: AppDatabase): ExecutionRecordDao = database.executionRecordDao()
    @Provides fun provideExecutionSnapshotDao(database: AppDatabase): ExecutionSnapshotDao = database.executionSnapshotDao()
    @Provides fun provideCompletedExecutionDao(database: AppDatabase): CompletedExecutionDao = database.completedExecutionDao()
}

