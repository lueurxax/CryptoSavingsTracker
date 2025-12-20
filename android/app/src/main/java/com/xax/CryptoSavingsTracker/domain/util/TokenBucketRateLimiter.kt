package com.xax.CryptoSavingsTracker.domain.util

import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.math.max

class TokenBucketRateLimiter(
    private val maxTokens: Double,
    private val refillTokensPerSecond: Double
) {
    private val mutex = Mutex()
    private var tokens: Double = maxTokens
    private var lastRefillAtMillis: Long = System.currentTimeMillis()

    suspend fun acquire(tokensNeeded: Double = 1.0) {
        require(tokensNeeded > 0) { "tokensNeeded must be positive" }

        while (true) {
            val waitMillis = mutex.withLock {
                refillLocked()
                if (tokens >= tokensNeeded) {
                    tokens -= tokensNeeded
                    0L
                } else {
                    val missing = tokensNeeded - tokens
                    val secondsToWait = missing / refillTokensPerSecond
                    max(1L, (secondsToWait * 1000.0).toLong())
                }
            }

            if (waitMillis <= 0L) return
            delay(waitMillis)
        }
    }

    private fun refillLocked() {
        val now = System.currentTimeMillis()
        val elapsedMillis = max(0L, now - lastRefillAtMillis)
        if (elapsedMillis <= 0L) return

        val refill = (elapsedMillis / 1000.0) * refillTokensPerSecond
        tokens = (tokens + refill).coerceAtMost(maxTokens)
        lastRefillAtMillis = now
    }
}

