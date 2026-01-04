package com.xax.CryptoSavingsTracker.presentation.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.presentation.theme.IconSize
import com.xax.CryptoSavingsTracker.presentation.theme.Spacing
import com.xax.CryptoSavingsTracker.presentation.theme.WarningOrange
import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Warning view displayed when exchange rates are unavailable.
 * Matches iOS ExchangeRateWarningView for feature parity.
 */
@Composable
fun ExchangeRateWarningView(
    isOffline: Boolean,
    lastUpdateMillis: Long?,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.small)
            .background(WarningOrange.copy(alpha = 0.1f))
            .padding(Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
    ) {
        Icon(
            imageVector = Icons.Default.Warning,
            contentDescription = null,
            tint = WarningOrange,
            modifier = Modifier.size(IconSize.inline)
        )

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "Exchange Rates Unavailable",
                style = MaterialTheme.typography.labelMedium
            )

            Text(
                text = if (lastUpdateMillis != null) {
                    "Using cached rates from ${formatRelativeTime(lastUpdateMillis)}"
                } else {
                    "Unable to calculate currency conversions"
                },
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Spacer(modifier = Modifier)
    }
}

/**
 * Compact badge for exchange rate status.
 */
@Composable
fun ExchangeRateStatusBadge(
    hasRates: Boolean,
    modifier: Modifier = Modifier
) {
    if (!hasRates) {
        Row(
            modifier = modifier
                .clip(MaterialTheme.shapes.extraSmall)
                .background(WarningOrange.copy(alpha = 0.1f))
                .padding(horizontal = 6.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.xxs)
        ) {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = null,
                tint = WarningOrange,
                modifier = Modifier.size(Spacing.sm)
            )
            Text(
                text = "Rates Unavailable",
                style = MaterialTheme.typography.labelSmall,
                color = WarningOrange
            )
        }
    }
}

private fun formatRelativeTime(timestampMillis: Long): String {
    val now = Instant.now()
    val then = Instant.ofEpochMilli(timestampMillis)
    val duration = Duration.between(then, now)

    return when {
        duration.toMinutes() < 1 -> "just now"
        duration.toMinutes() < 60 -> "${duration.toMinutes()} min ago"
        duration.toHours() < 24 -> "${duration.toHours()} hours ago"
        duration.toDays() < 7 -> "${duration.toDays()} days ago"
        else -> {
            val date = LocalDateTime.ofInstant(then, ZoneId.systemDefault())
            "${date.monthValue}/${date.dayOfMonth}"
        }
    }
}
