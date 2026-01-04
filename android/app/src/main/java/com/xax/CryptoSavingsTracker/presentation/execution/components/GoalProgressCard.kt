package com.xax.CryptoSavingsTracker.presentation.execution.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionGoalProgress
import com.xax.CryptoSavingsTracker.presentation.common.AmountFormatters

@Composable
internal fun GoalProgressCard(
    goal: ExecutionGoalProgress,
    isFulfilled: Boolean,
    remainingDisplay: Double?,
    remainingCurrency: String?,
    onAddToCloseMonth: ((ExecutionGoalProgress) -> Unit)?
) {
    val progressPercent = goal.progressPercent
    val progressColor = if (isFulfilled) Color(0xFF4CAF50) else MaterialTheme.colorScheme.primary
    val backgroundColor = if (isFulfilled) {
        Color(0xFF4CAF50).copy(alpha = 0.1f)
    } else {
        MaterialTheme.colorScheme.surfaceVariant
    }
    val remainingToClose = (goal.plannedAmount - goal.contributed).coerceAtLeast(0.0)

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = backgroundColor)
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            // Title row
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = goal.snapshot.goalName,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
                )
                if (isFulfilled) {
                    Icon(
                        imageVector = Icons.Default.CheckCircle,
                        contentDescription = "Fulfilled",
                        tint = Color(0xFF4CAF50),
                        modifier = Modifier.size(20.dp)
                    )
                } else {
                    Text(
                        text = "$progressPercent%",
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Progress bar
            LinearProgressIndicator(
                progress = { (progressPercent / 100.0).toFloat().coerceIn(0f, 1f) },
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "${goal.snapshot.goalName} progress: ${progressPercent.toInt()} percent complete" },
                color = progressColor,
                trackColor = if (isFulfilled) Color(0xFF4CAF50).copy(alpha = 0.3f) else MaterialTheme.colorScheme.surface
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Amount row: contributed / planned
            Text(
                text = "${formatCurrency(goal.contributed, goal.snapshot.currency)} / ${formatCurrency(goal.plannedAmount, goal.snapshot.currency)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (remainingDisplay != null && remainingDisplay > 0) {
                Spacer(modifier = Modifier.height(6.dp))
                val currency = remainingCurrency ?: goal.snapshot.currency
                val isCrypto = !executionDisplayCurrencies.contains(currency.uppercase())
                Text(
                    text = "Remaining to close: ${AmountFormatters.formatDisplayCurrencyAmount(remainingDisplay, currency, isCrypto = isCrypto)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            if (!isFulfilled && remainingToClose <= 0.0) {
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = "Month already closed for this goal",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            if (!isFulfilled && remainingToClose > 0 && onAddToCloseMonth != null) {
                Spacer(modifier = Modifier.height(8.dp))
                Button(
                    onClick = { onAddToCloseMonth(goal) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Add to Close Month")
                }
            }
        }
    }
}
