package com.xax.CryptoSavingsTracker.di

import com.xax.CryptoSavingsTracker.data.repository.AllocationRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.AssetRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.GoalRepositoryImpl
import com.xax.CryptoSavingsTracker.data.repository.TransactionRepositoryImpl
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
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
}
