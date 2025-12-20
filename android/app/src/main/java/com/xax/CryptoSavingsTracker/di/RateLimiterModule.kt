package com.xax.CryptoSavingsTracker.di

import com.xax.CryptoSavingsTracker.domain.util.TokenBucketRateLimiter
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Named
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object RateLimiterModule {

    @Provides
    @Singleton
    @Named("CoinGeckoRateLimiter")
    fun provideCoinGeckoRateLimiter(): TokenBucketRateLimiter {
        return TokenBucketRateLimiter(maxTokens = 5.0, refillTokensPerSecond = 5.0)
    }

    @Provides
    @Singleton
    @Named("TatumRateLimiter")
    fun provideTatumRateLimiter(): TokenBucketRateLimiter {
        return TokenBucketRateLimiter(maxTokens = 5.0, refillTokensPerSecond = 5.0)
    }
}

