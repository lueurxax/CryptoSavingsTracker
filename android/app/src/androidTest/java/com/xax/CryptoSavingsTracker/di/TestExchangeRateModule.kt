package com.xax.CryptoSavingsTracker.di

import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import dagger.Module
import dagger.Provides
import dagger.hilt.components.SingletonComponent
import dagger.hilt.testing.TestInstallIn
import javax.inject.Singleton

@Module
@TestInstallIn(
    components = [SingletonComponent::class],
    replaces = [ExchangeRateModule::class]
)
object TestExchangeRateModule {
    @Provides
    @Singleton
    fun provideExchangeRateRepository(): ExchangeRateRepository {
        return object : ExchangeRateRepository {
            override suspend fun fetchRate(from: String, to: String): Double {
                if (from.equals(to, ignoreCase = true)) return 1.0
                return when {
                    from.equals("BTC", ignoreCase = true) && to.equals("USD", ignoreCase = true) -> 100_000.0
                    from.equals("USD", ignoreCase = true) && to.equals("BTC", ignoreCase = true) -> 0.00001
                    else -> 1.0
                }
            }

            override fun hasValidConfiguration(): Boolean = true

            override suspend fun clearCache() = Unit
        }
    }
}

