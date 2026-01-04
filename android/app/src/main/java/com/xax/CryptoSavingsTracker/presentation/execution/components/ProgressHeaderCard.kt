package com.xax.CryptoSavingsTracker.presentation.execution.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionSession
import java.time.Instant
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

internal val executionDisplayCurrencies = listOf(
    "USD",
    "EUR",
    "GBP",
    "JPY",
    "CHF",
    "CAD",
    "AUD",
    "CNY",
    "INR",
    "KRW"
)

internal fun formatCurrency(amount: Double, currency: String = "USD"): String {
    return "$currency ${String.format("%,.2f", amount)}"
}

internal fun formatRelativeTime(millis: Long): String {
    val now = Instant.now()
    val then = Instant.ofEpochMilli(millis)
    val minutes = ChronoUnit.MINUTES.between(then, now)
    return when {
        minutes < 1 -> "just now"
        minutes < 60 -> "${minutes}m ago"
        else -> {
            val hours = ChronoUnit.HOURS.between(then, now)
            if (hours < 24) "${hours}h ago" else "${hours / 24}d ago"
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ProgressHeaderCard(
    session: ExecutionSession,
    displayCurrency: String,
    totalRemainingDisplay: Double?,
    hasRateWarning: Boolean,
    lastRateUpdateMillis: Long?,
    currentFocusGoal: com.xax.CryptoSavingsTracker.presentation.execution.ExecutionFocusGoal?,
    currencyPickerExpanded: Boolean,
    onToggleCurrencyPicker: () -> Unit,
    onDisplayCurrencySelected: (String) -> Unit
) {
    val monthLabel = session.record.monthLabel
    val formattedMonth = remember(monthLabel) {
        try {
            val ym = YearMonth.parse(monthLabel)
            ym.format(DateTimeFormatter.ofPattern("MMMM yyyy"))
        } catch (e: Exception) {
            monthLabel
        }
    }

    val progressPercent = session.overallProgress.coerceIn(0.0, 100.0)
    val progressColor = if (progressPercent >= 100) Color(0xFF4CAF50) else MaterialTheme.colorScheme.primary
    val focusFormatter = remember { DateTimeFormatter.ofPattern("MMM d") }

    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Title row with status and month
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.Refresh,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Active This Month",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                }
                Text(
                    text = formattedMonth,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Display Currency",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                ExposedDropdownMenuBox(
                    expanded = currencyPickerExpanded,
                    onExpandedChange = { onToggleCurrencyPicker() }
                ) {
                    OutlinedTextField(
                        value = displayCurrency,
                        onValueChange = {},
                        readOnly = true,
                        modifier = Modifier
                            .menuAnchor(MenuAnchorType.PrimaryNotEditable),
                        label = { Text("Currency") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = currencyPickerExpanded) },
                        singleLine = true
                    )
                    ExposedDropdownMenu(
                        expanded = currencyPickerExpanded,
                        onDismissRequest = onToggleCurrencyPicker
                    ) {
                        executionDisplayCurrencies.forEach { currency ->
                            DropdownMenuItem(
                                text = { Text(currency) },
                                onClick = { onDisplayCurrencySelected(currency) }
                            )
                        }
                    }
                }
            }

            // Rate update timestamp
            if (lastRateUpdateMillis != null) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Rates updated ${formatRelativeTime(lastRateUpdateMillis)}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Progress bar
            LinearProgressIndicator(
                progress = { (progressPercent / 100.0).toFloat().coerceIn(0f, 1f) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp)
                    .semantics { contentDescription = "Monthly execution progress: ${progressPercent.toInt()} percent complete" },
                color = progressColor,
                trackColor = MaterialTheme.colorScheme.surfaceVariant
            )

            if (currentFocusGoal != null) {
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = "Current focus: ${currentFocusGoal.goalName} (until ${currentFocusGoal.deadline.format(focusFormatter)})",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Stats row
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                // Percentage complete
                Column(horizontalAlignment = Alignment.Start) {
                    Text(
                        text = "${progressPercent.toInt()}%",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        color = if (progressPercent >= 100) progressColor else MaterialTheme.colorScheme.onSurface
                    )
                    Text(
                        text = "complete",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                // Goals funded
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = "${session.fulfilledCount}/${session.goals.size}",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "goals funded",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                // Total planned
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = formatCurrency(session.totalPlanned),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "planned",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            if (totalRemainingDisplay != null) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Remaining this month: ${formatCurrency(totalRemainingDisplay, displayCurrency)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else if (hasRateWarning) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Remaining this month: unavailable (rate missing)",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
