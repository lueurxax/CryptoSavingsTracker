package com.xax.CryptoSavingsTracker.presentation.execution.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import java.util.concurrent.TimeUnit

@Composable
internal fun UndoBanner(
    undoDeadlineMillis: Long?,
    onUndo: () -> Unit,
    isBusy: Boolean,
    isRecoveryRequired: Boolean = false
) {
    val nowMillis by produceState(
        initialValue = System.currentTimeMillis(),
        key1 = undoDeadlineMillis
    ) {
        val deadline = undoDeadlineMillis ?: return@produceState
        while (value < deadline) {
            delay(minOf(TimeUnit.MINUTES.toMillis(1), deadline - value))
            value = System.currentTimeMillis()
        }
    }
    val timeRemaining = formatUndoTimeRemaining(undoDeadlineMillis, nowMillis)

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.Undo,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        text = if (isRecoveryRequired) {
                            "Tracking cannot continue"
                        } else {
                            "Execution started"
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = if (isRecoveryRequired) {
                            "Cancel tracking to return to planning."
                        } else {
                            "Undo expires in $timeRemaining"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Button(
                onClick = onUndo,
                enabled = !isBusy
            ) {
                Text(if (isRecoveryRequired) "Cancel tracking" else "Undo")
            }
        }
    }
}

internal fun formatUndoTimeRemaining(
    undoDeadlineMillis: Long?,
    nowMillis: Long
): String {
    val deadline = undoDeadlineMillis ?: return "—"
    val remainingMillis = deadline - nowMillis
    if (remainingMillis <= 0L) return "Expired"
    val hours = TimeUnit.MILLISECONDS.toHours(remainingMillis)
    val minutes = TimeUnit.MILLISECONDS.toMinutes(remainingMillis) % 60
    return if (hours > 0L) "${hours}h ${minutes}m" else "${minutes}m"
}
