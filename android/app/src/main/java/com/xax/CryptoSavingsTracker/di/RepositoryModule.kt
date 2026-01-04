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
import com.xax.CryptoSavingsTracker.data.repository.OnChainBalanceRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.OnChainTransactionRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.TransactionRepositoryImpl
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
import com.xax.CryptoSavingsTracker.domain.repository.OnChainTransactionRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Hilt module for providing repository implementations
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {

    @Binds
    @Singleton
    abstract fun bindGoalRepository(
        goalRepositoryImpl: GoalRepositoryImpl
    ): GoalRepository

    @Binds
    @Singleton
    abstract fun bindAssetRepository(
        assetRepositoryImpl: AssetRepositoryImpl
    ): AssetRepository

    @Binds
    @Singleton
    abstract fun bindTransactionRepository(
        transactionRepositoryImpl: TransactionRepositoryImpl
    ): TransactionRepository

    @Binds
    @Singleton
    abstract fun bindAllocationRepository(
        allocationRepositoryImpl: AllocationRepositoryImpl
    ): AllocationRepository

    @Binds
    @Singleton
    abstract fun bindAllocationHistoryRepository(
        allocationHistoryRepositoryImpl: AllocationHistoryRepositoryImpl
    ): AllocationHistoryRepository

    @Binds
    @Singleton
    abstract fun bindMonthlyPlanRepository(
        monthlyPlanRepositoryImpl: MonthlyPlanRepositoryImpl
    ): MonthlyPlanRepository

    @Binds
    @Singleton
    abstract fun bindMonthlyGoalPlanRepository(
        impl: MonthlyGoalPlanRepositoryImpl
    ): MonthlyGoalPlanRepository

    @Binds
    @Singleton
    abstract fun bindExecutionRecordRepository(
        executionRecordRepositoryImpl: ExecutionRecordRepositoryImpl
    ): ExecutionRecordRepository

    @Binds
    @Singleton
    abstract fun bindExecutionSnapshotRepository(
        executionSnapshotRepositoryImpl: ExecutionSnapshotRepositoryImpl
    ): ExecutionSnapshotRepository

    @Binds
    @Singleton
    abstract fun bindCompletedExecutionRepository(
        completedExecutionRepositoryImpl: CompletedExecutionRepositoryImpl
    ): CompletedExecutionRepository

    @Binds
    @Singleton
    abstract fun bindOnChainBalanceRepository(
        impl: OnChainBalanceRepositoryImpl
    ): OnChainBalanceRepository

    @Binds
    @Singleton
    abstract fun bindOnChainTransactionRepository(
        impl: OnChainTransactionRepositoryImpl
    ): OnChainTransactionRepository
}
