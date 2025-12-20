package com.xax.CryptoSavingsTracker.di

import android.content.Context
import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import com.xax.CryptoSavingsTracker.data.local.security.ApiKeyStore
import com.xax.CryptoSavingsTracker.data.remote.api.CoinGeckoApi
import com.xax.CryptoSavingsTracker.data.remote.api.TatumApi
import com.xax.CryptoSavingsTracker.data.repository.ExchangeRateRepositoryImpl
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import kotlinx.serialization.json.Json
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import java.util.concurrent.TimeUnit
import javax.inject.Named
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    @Provides
    @Singleton
    fun provideLoggingInterceptor(): HttpLoggingInterceptor {
        return HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        }
    }

    @Provides
    @Singleton
    @Named("CoinGeckoAuthInterceptor")
    fun provideCoinGeckoAuthInterceptor(
        apiKeyStore: ApiKeyStore
    ): Interceptor {
        return Interceptor { chain ->
            val apiKey = apiKeyStore.getCoinGeckoApiKey()
            val request = chain.request().newBuilder()
                .addHeader("accept", "application/json")
                .apply {
                    if (apiKey.isNotEmpty()) {
                        addHeader("x-cg-demo-api-key", apiKey)
                    }
                }
                .build()
            chain.proceed(request)
        }
    }

    @Provides
    @Singleton
    @Named("TatumAuthInterceptor")
    fun provideTatumAuthInterceptor(
        apiKeyStore: ApiKeyStore
    ): Interceptor {
        return Interceptor { chain ->
            val apiKey = apiKeyStore.getTatumApiKey()
            val request = chain.request().newBuilder()
                .addHeader("accept", "application/json")
                .apply {
                    if (apiKey.isNotEmpty()) {
                        addHeader("x-api-key", apiKey)
                    }
                }
                .build()
            chain.proceed(request)
        }
    }

    @Provides
    @Singleton
    @Named("CoinGeckoClient")
    fun provideCoinGeckoOkHttpClient(
        loggingInterceptor: HttpLoggingInterceptor,
        @Named("CoinGeckoAuthInterceptor") authInterceptor: Interceptor
    ): OkHttpClient {
        return OkHttpClient.Builder()
            .addInterceptor(authInterceptor)
            .addInterceptor(loggingInterceptor)
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .writeTimeout(10, TimeUnit.SECONDS)
            .build()
    }

    @Provides
    @Singleton
    @Named("TatumClient")
    fun provideTatumOkHttpClient(
        loggingInterceptor: HttpLoggingInterceptor,
        @Named("TatumAuthInterceptor") authInterceptor: Interceptor
    ): OkHttpClient {
        return OkHttpClient.Builder()
            .addInterceptor(authInterceptor)
            .addInterceptor(loggingInterceptor)
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .writeTimeout(10, TimeUnit.SECONDS)
            .build()
    }

    @Provides
    @Singleton
    fun provideCoinGeckoApi(
        @Named("CoinGeckoClient") okHttpClient: OkHttpClient
    ): CoinGeckoApi {
        return Retrofit.Builder()
            .baseUrl("https://api.coingecko.com/api/v3/")
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(CoinGeckoApi::class.java)
    }

    @Provides
    @Singleton
    fun provideTatumApi(
        @Named("TatumClient") okHttpClient: OkHttpClient
    ): TatumApi {
        return Retrofit.Builder()
            .baseUrl("https://api.tatum.io/")
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(TatumApi::class.java)
    }
}

@Module
@InstallIn(SingletonComponent::class)
abstract class ExchangeRateModule {

    @Binds
    @Singleton
    abstract fun bindExchangeRateRepository(
        impl: ExchangeRateRepositoryImpl
    ): ExchangeRateRepository
}
