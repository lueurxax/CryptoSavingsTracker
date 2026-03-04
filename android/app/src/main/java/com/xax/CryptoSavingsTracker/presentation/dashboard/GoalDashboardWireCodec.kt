package com.xax.CryptoSavingsTracker.presentation.dashboard

import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

class GoalDashboardWireCodecError(message: String) : IllegalArgumentException(message)

object GoalDashboardWireCodec {
    private val decimalRegex = Regex("^-?(0|[1-9][0-9]*)(\\.[0-9]{1,18})?$")
    private val utcMillisRegex = Regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$")
    private val formatter: DateTimeFormatter = DateTimeFormatter
        .ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
        .withZone(ZoneOffset.UTC)

    fun encodeDecimal(value: BigDecimal): String {
        val normalized = value.stripTrailingZeros().toPlainString()
        return if (normalized == "-0") "0" else normalized
    }

    fun decodeDecimal(value: String): BigDecimal {
        require(decimalRegex.matches(value)) {
            "Invalid canonical decimal format: $value"
        }
        return value.toBigDecimalOrNull()
            ?: throw GoalDashboardWireCodecError("Invalid canonical decimal format: $value")
    }

    fun encodeDate(value: Instant): String = formatter.format(value)

    fun decodeDate(value: String): Instant {
        if (!utcMillisRegex.matches(value)) {
            throw GoalDashboardWireCodecError("Invalid canonical RFC3339 UTC date format: $value")
        }
        return try {
            Instant.parse(value)
        } catch (error: DateTimeParseException) {
            throw GoalDashboardWireCodecError("Invalid canonical RFC3339 UTC date format: $value")
        }
    }
}
