package com.xax.CryptoSavingsTracker.presentation.whatif

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.MonetizationOn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleGreen
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleYellow
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.roundToInt

/**
 * What-If settings state matching iOS WhatIfSettings
 */
data class WhatIfState(
    val enabled: Boolean = false,
    val monthly: Double = 0.0,
    val oneTime: Double = 0.0
)

/**
 * What-If simulator matching iOS WhatIfView
 * Allows users to project future goal totals based on contribution scenarios
 */
@Composable
fun WhatIfSimulator(
    currentTotal: Double,
    targetAmount: Double,
    deadline: LocalDate,
    currency: String,
    modifier: Modifier = Modifier,
    state: WhatIfState = WhatIfState(),
    onStateChange: (WhatIfState) -> Unit = {}
) {
    val daysRemaining = remember(deadline) {
        ChronoUnit.DAYS.between(LocalDate.now(), deadline).coerceAtLeast(0).toInt()
    }

    val monthsRemaining = remember(daysRemaining) {
        (daysRemaining / 30.0).coerceAtLeast(0.0)
    }

    val projectedTotal = remember(currentTotal, state.oneTime, state.monthly, monthsRemaining) {
        currentTotal + state.oneTime + state.monthly * monthsRemaining
    }

    val isOnTrack = projectedTotal >= targetAmount

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(
                color = MaterialTheme.colorScheme.surface,
                shape = RoundedCornerShape(16.dp)
            )
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.1f),
                shape = RoundedCornerShape(16.dp)
            )
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "What-If Scenario",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Medium
            )

            Surface(
                shape = RoundedCornerShape(8.dp),
                color = if (isOnTrack) AccessibleGreen.copy(alpha = 0.1f) else AccessibleYellow.copy(alpha = 0.1f)
            ) {
                Text(
                    text = if (isOnTrack) "On Track" else "Behind",
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isOnTrack) AccessibleGreen else AccessibleYellow
                )
            }
        }

        // Enable toggle
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.MonetizationOn,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
                Text(
                    text = "Enable Overlay",
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            Switch(
                checked = state.enabled,
                onCheckedChange = { onStateChange(state.copy(enabled = it)) }
            )
        }

        // Monthly contribution slider
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.MonetizationOn,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp)
                    )
                    Text(
                        text = "Monthly Contribution",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = "${state.monthly.roundToInt()} $currency",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
                )
            }

            Slider(
                value = state.monthly.toFloat(),
                onValueChange = { onStateChange(state.copy(monthly = it.toDouble())) },
                valueRange = 0f..1000f,
                steps = 39 // 25 increments
            )
        }

        // One-time investment slider
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.CreditCard,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp)
                    )
                    Text(
                        text = "One-Time Investment",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = "${state.oneTime.roundToInt()} $currency",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
                )
            }

            Slider(
                value = state.oneTime.toFloat(),
                onValueChange = { onStateChange(state.copy(oneTime = it.toDouble())) },
                valueRange = 0f..5000f,
                steps = 99 // 50 increments
            )
        }

        HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))

        // Results
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = "Projected Total by Deadline",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = "${projectedTotal.roundToInt()} $currency",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
            }

            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = "Days Remaining",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = "$daysRemaining",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = if (daysRemaining < 30) AccessibleYellow else MaterialTheme.colorScheme.onSurface
                )
            }
        }

        // Additional info
        if (isOnTrack) {
            val surplus = projectedTotal - targetAmount
            Text(
                text = "You'll exceed your goal by ${surplus.roundToInt()} $currency",
                style = MaterialTheme.typography.labelSmall,
                color = AccessibleGreen
            )
        } else {
            val shortfall = targetAmount - projectedTotal
            val requiredMonthly = if (monthsRemaining > 0) {
                (shortfall / monthsRemaining).roundToInt()
            } else 0
            Text(
                text = "You need ${shortfall.roundToInt()} $currency more. Try adding $requiredMonthly/month",
                style = MaterialTheme.typography.labelSmall,
                color = AccessibleYellow
            )
        }
    }
}

/**
 * Compact What-If card for dashboard
 */
@Composable
fun WhatIfCard(
    currentTotal: Double,
    targetAmount: Double,
    deadline: LocalDate,
    currency: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val daysRemaining = remember(deadline) {
        ChronoUnit.DAYS.between(LocalDate.now(), deadline).coerceAtLeast(0).toInt()
    }

    val progress = (currentTotal / targetAmount).coerceIn(0.0, 1.0)
    val isOnTrack = progress >= (1.0 - daysRemaining / 365.0).coerceAtLeast(0.0)

    Card(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = "What-If Simulator",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    text = "Explore contribution scenarios",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Surface(
                shape = RoundedCornerShape(8.dp),
                color = if (isOnTrack) AccessibleGreen.copy(alpha = 0.1f) else AccessibleYellow.copy(alpha = 0.1f)
            ) {
                Text(
                    text = if (isOnTrack) "On Track" else "Behind",
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isOnTrack) AccessibleGreen else AccessibleYellow
                )
            }
        }
    }
}
