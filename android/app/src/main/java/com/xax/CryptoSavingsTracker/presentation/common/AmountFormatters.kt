package com.xax.CryptoSavingsTracker.presentation.common

import kotlin.math.abs
import kotlin.math.round
import java.util.Locale

/**
 * iOS parity helpers:
 * - Crypto amounts are typically shown with 6 decimals (e.g., 0.004106 BTC).
 * - Input strings should use '.' as decimal separator so Double parsing works reliably.
 * - Fiat amounts are displayed as integers by default (no trailing .00), matching iOS formatting.
 */
object AmountFormatters {
    fun formatDisplayAmount(amount: Double, isCrypto: Boolean): String {
        val isWholeFiat = !isCrypto && abs(amount - round(amount)) < 1e-9
        val pattern = when {
            isCrypto -> "%,.6f"
            isWholeFiat -> "%,.0f"
            else -> "%,.2f"
        }
        return String.format(Locale.getDefault(), pattern, amount)
    }

    fun formatDisplayCurrencyAmount(amount: Double, currency: String, isCrypto: Boolean): String {
        return "$currency ${formatDisplayAmount(amount, isCrypto)}"
    }

    fun formatInputAmount(amount: Double, isCrypto: Boolean): String {
        return if (isCrypto) {
            String.format(Locale.US, "%.8f", amount).trimEnd('0').trimEnd('.')
        } else {
            String.format(Locale.US, "%.2f", amount)
        }
    }
}
