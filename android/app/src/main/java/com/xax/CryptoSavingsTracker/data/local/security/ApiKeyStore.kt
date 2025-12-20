package com.xax.CryptoSavingsTracker.data.local.security

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.Properties
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ApiKeyStore @Inject constructor(
    @ApplicationContext private val context: Context
) {

    private val encryptedPrefs by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        EncryptedSharedPreferences.create(
            context,
            SECURE_PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    private val legacyPrefs by lazy {
        context.getSharedPreferences(LEGACY_PREFS_NAME, Context.MODE_PRIVATE)
    }

    init {
        migrateBundledConfigIfNeeded()
        migrateLegacyIfNeeded()
    }

    fun getCoinGeckoApiKey(): String {
        return encryptedPrefs.getString(KEY_COINGECKO, "") ?: ""
    }

    fun getTatumApiKey(): String {
        return encryptedPrefs.getString(KEY_TATUM, "") ?: ""
    }

    fun setCoinGeckoApiKey(value: String) {
        encryptedPrefs.edit().putString(KEY_COINGECKO, value.trim()).apply()
    }

    fun setTatumApiKey(value: String) {
        encryptedPrefs.edit().putString(KEY_TATUM, value.trim()).apply()
    }

    private fun migrateLegacyIfNeeded() {
        val legacyCoinGecko = legacyPrefs.getString(KEY_COINGECKO, "") ?: ""
        val legacyTatum = legacyPrefs.getString(KEY_TATUM, "") ?: ""
        if (legacyCoinGecko.isBlank() && legacyTatum.isBlank()) return

        val secureCoinGecko = encryptedPrefs.getString(KEY_COINGECKO, "") ?: ""
        val secureTatum = encryptedPrefs.getString(KEY_TATUM, "") ?: ""
        if (secureCoinGecko.isNotBlank() || secureTatum.isNotBlank()) return

        encryptedPrefs.edit()
            .putString(KEY_COINGECKO, legacyCoinGecko.trim())
            .putString(KEY_TATUM, legacyTatum.trim())
            .apply()

        legacyPrefs.edit().clear().apply()
    }

    private fun migrateBundledConfigIfNeeded() {
        val secureCoinGecko = encryptedPrefs.getString(KEY_COINGECKO, "") ?: ""
        val secureTatum = encryptedPrefs.getString(KEY_TATUM, "") ?: ""
        if (secureCoinGecko.isNotBlank() || secureTatum.isNotBlank()) return

        val props = runCatching {
            context.assets.open(BUNDLED_CONFIG_FILENAME).use { stream ->
                Properties().apply { load(stream) }
            }
        }.getOrNull() ?: return

        val coinGecko = (props.getProperty("CoinGeckoAPIKey") ?: "").trim()
        val tatum = (props.getProperty("TatumAPIKey") ?: "").trim()

        val normalizedCoinGecko = coinGecko.takeIf { it.isNotBlank() && it != "YOUR_COINGECKO_API_KEY" } ?: ""
        val normalizedTatum = tatum.takeIf { it.isNotBlank() && it != "YOUR_TATUM_API_KEY" } ?: ""

        if (normalizedCoinGecko.isBlank() && normalizedTatum.isBlank()) return

        encryptedPrefs.edit()
            .putString(KEY_COINGECKO, normalizedCoinGecko)
            .putString(KEY_TATUM, normalizedTatum)
            .apply()
    }

    private companion object {
        const val LEGACY_PREFS_NAME = "api_keys"
        const val SECURE_PREFS_NAME = "secure_api_keys"
        const val BUNDLED_CONFIG_FILENAME = "Config.properties"

        const val KEY_COINGECKO = "coingecko_api_key"
        const val KEY_TATUM = "tatum_api_key"
    }
}
