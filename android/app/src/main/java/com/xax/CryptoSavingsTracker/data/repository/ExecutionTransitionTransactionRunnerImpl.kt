package com.xax.CryptoSavingsTracker.data.repository

import androidx.room.withTransaction
import com.xax.CryptoSavingsTracker.data.local.database.AppDatabase
import com.xax.CryptoSavingsTracker.domain.repository.ExecutionTransitionTransactionRunner
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ExecutionTransitionTransactionRunnerImpl @Inject constructor(
    private val appDatabase: AppDatabase
) : ExecutionTransitionTransactionRunner {
    override suspend fun <T> run(block: suspend () -> T): T {
        return appDatabase.withTransaction {
            block()
        }
    }
}
