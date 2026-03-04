package com.xax.CryptoSavingsTracker.domain.repository

interface ExecutionTransitionTransactionRunner {
    suspend fun <T> run(block: suspend () -> T): T
}
