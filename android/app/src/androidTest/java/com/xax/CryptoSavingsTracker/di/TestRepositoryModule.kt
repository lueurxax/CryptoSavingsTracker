package com.xax.CryptoSavingsTracker.di

import com.xax.CryptoSavingsTracker.data.repository.AllocationHistoryRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.AllocationRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.AssetRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.CompletedExecutionRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.ExecutionRecordRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.ExecutionSnapshotRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.GoalRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.MonthlyGoalPlanRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.MonthlyPlanRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.TransactionRepositoryImpl
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.CompletedExecutionRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionRecordRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionSnapshotRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.MonthlyGoalPlanRepository
import com.xax.CryptoSavingsTracker.domain.repository.MonthlyPlanRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import dagger.Module
import dagger.Provides
import dagger.hilt.components.SingletonComponent
import dagger.hilt.testing.TestInstallIn
import javax.inject.Singleton

@Module
@TestInstallIn(
    components = [SingletonComponent::class],
    replaces = [RepositoryModule::class]
)
object TestRepositoryModule {
    @Provides @Singleton fun provideGoalRepository(impl: GoalRepositoryImpl): GoalRepository = impl
    @Provides @Singleton fun provideAssetRepository(impl: AssetRepositoryImpl): AssetRepository = impl
    @Provides @Singleton fun provideTransactionRepository(impl: TransactionRepositoryImpl): TransactionRepository = impl
    @Provides @Singleton fun provideAllocationRepository(impl: AllocationRepositoryImpl): AllocationRepository = impl
    @Provides @Singleton fun provideAllocationHistoryRepository(impl: AllocationHistoryRepositoryImpl): AllocationHistoryRepository = impl
    @Provides @Singleton fun provideMonthlyPlanRepository(impl: MonthlyPlanRepositoryImpl): MonthlyPlanRepository = impl
    @Provides @Singleton fun provideMonthlyGoalPlanRepository(impl: MonthlyGoalPlanRepositoryImpl): MonthlyGoalPlanRepository = impl
    @Provides @Singleton fun provideExecutionRecordRepository(impl: ExecutionRecordRepositoryImpl): ExecutionRecordRepository = impl
    @Provides @Singleton fun provideExecutionSnapshotRepository(impl: ExecutionSnapshotRepositoryImpl): ExecutionSnapshotRepository = impl
    @Provides @Singleton fun provideCompletedExecutionRepository(impl: CompletedExecutionRepositoryImpl): CompletedExecutionRepository = impl

    @Provides
    @Singleton
    fun provideOnChainBalanceRepository(): OnChainBalanceRepository {
        return object : OnChainBalanceRepository {
            override suspend fun getBalance(asset: Asset, forceRefresh: Boolean): Result<OnChainBalance> {
                val balance = if (asset.currency.equals("BTC", ignoreCase = true)) 0.004106 else 0.0
                return Result.success(
                    OnChainBalance(
                        assetId = asset.id,
                        chainId = asset.chainId ?: "bitcoin",
                        address = asset.address ?: "bc1qexample",
                        currency = asset.currency,
                        balance = balance,
                        fetchedAtMillis = System.currentTimeMillis(),
                        isStale = true
                    )
                )
            }

            override suspend fun clearCache() = Unit
        }
    }
}

