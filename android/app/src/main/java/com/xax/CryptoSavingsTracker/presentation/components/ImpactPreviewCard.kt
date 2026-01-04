package com.xax.CryptoSavingsTracker.presentation.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.TrendingDown
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.domain.model.GoalImpact
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleGreen
import com.xax.CryptoSavingsTracker.presentation.theme.InfoBlue
import com.xax.CryptoSavingsTracker.presentation.theme.WarningOrange
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.abs

/**
 * Card showing the impact preview of goal changes.
 * Matches iOS ImpactPreviewCard for feature parity.
 */
@Composable
fun ImpactPreviewCard(
    impact: GoalImpact,
    currency: String = "USD",
    modifier: Modifier = Modifier
) {
    val accessibilityDescription = remember(impact) {
        buildAccessibilityDescription(impact, currency)
    }

    Card(
        modifier = modifier
            .fillMaxWidth()
            .semantics { contentDescription = accessibilityDescription },
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Header
            ImpactHeader(isPositive = impact.isPositiveChange)

            // Progress Comparison
            ProgressComparisonRow(impact = impact)

            // Key Changes
            KeyChangesSection(impact = impact, currency = currency)

            // Warning if significant negative change
            if (!impact.isPositiveChange && impact.significantChange) {
                SignificantChangeWarning(impact = impact)
            }
        }
    }
}

@Composable
private fun ImpactHeader(isPositive: Boolean) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(
            imageVector = if (isPositive) Icons.AutoMirrored.Filled.TrendingUp else Icons.AutoMirrored.Filled.TrendingDown,
            contentDescription = null,
            tint = if (isPositive) AccessibleGreen else WarningOrange,
            modifier = Modifier.size(24.dp)
        )

        Column {
            Text(
                text = "Impact Preview",
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = if (isPositive) "Positive change" else "Requires attention",
                style = MaterialTheme.typography.labelSmall,
                color = if (isPositive) AccessibleGreen else WarningOrange
            )
        }

        Spacer(modifier = Modifier.weight(1f))
    }
}

@Composable
private fun ProgressComparisonRow(impact: GoalImpact) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = "Progress",
            style = MaterialTheme.typography.labelLarge
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Before
            ProgressIndicator(
                label = "Before",
                progress = impact.oldProgress,
                color = InfoBlue
            )

            // Arrow
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(24.dp)
            )

            // After
            ProgressIndicator(
                label = "After",
                progress = impact.newProgress,
                color = if (impact.isPositiveChange) AccessibleGreen else WarningOrange
            )
        }
    }
}

@Composable
private fun ProgressIndicator(
    label: String,
    progress: Double,
    color: Color
) {
    var animatedProgress by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(progress) {
        animatedProgress = progress.toFloat()
    }

    val animatedValue by animateFloatAsState(
        targetValue = animatedProgress,
        animationSpec = tween(durationMillis = 1000),
        label = "progress"
    )

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        CircularProgressIndicator(
            progress = animatedValue,
            size = 60.dp,
            strokeWidth = 6.dp,
            color = color
        )

        Text(
            text = "${(progress * 100).toInt()}%",
            style = MaterialTheme.typography.labelMedium
        )
    }
}

@Composable
private fun CircularProgressIndicator(
    progress: Float,
    size: Dp,
    strokeWidth: Dp,
    color: Color
) {
    Box(
        modifier = Modifier.size(size),
        contentAlignment = Alignment.Center
    ) {
        Canvas(modifier = Modifier.size(size)) {
            // Background circle
            drawArc(
                color = color.copy(alpha = 0.2f),
                startAngle = 0f,
                sweepAngle = 360f,
                useCenter = false,
                style = Stroke(width = strokeWidth.toPx(), cap = StrokeCap.Round)
            )

            // Progress arc
            drawArc(
                color = color,
                startAngle = -90f,
                sweepAngle = 360f * progress,
                useCenter = false,
                style = Stroke(width = strokeWidth.toPx(), cap = StrokeCap.Round)
            )
        }
    }
}

@Composable
private fun KeyChangesSection(impact: GoalImpact, currency: String) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (abs(impact.targetAmountChange) > 0.01) {
            ChangeRow(
                title = "Target Amount",
                oldValue = formatCurrency(impact.oldTargetAmount, currency),
                newValue = formatCurrency(impact.newTargetAmount, currency),
                isPositive = impact.targetAmountChange > 0
            )
        }

        if (abs(impact.dailyTargetChange) > 0.01) {
            ChangeRow(
                title = "Daily Target",
                oldValue = formatCurrency(impact.oldDailyTarget, currency),
                newValue = formatCurrency(impact.newDailyTarget, currency),
                isPositive = impact.dailyTargetChange < 0 // Less daily target is better
            )
        }

        if (impact.daysRemainingChange != 0) {
            ChangeRow(
                title = "Days Remaining",
                oldValue = "${impact.oldDaysRemaining} days",
                newValue = "${impact.newDaysRemaining} days",
                isPositive = impact.daysRemainingChange > 0 // More days is better
            )
        }
    }
}

@Composable
private fun ChangeRow(
    title: String,
    oldValue: String,
    newValue: String,
    isPositive: Boolean
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = oldValue,
                style = MaterialTheme.typography.labelSmall.copy(
                    textDecoration = TextDecoration.LineThrough
                ),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                contentDescription = null,
                modifier = Modifier.size(12.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Text(
                text = newValue,
                style = MaterialTheme.typography.labelMedium,
                color = if (isPositive) AccessibleGreen else WarningOrange
            )
        }
    }
}

@Composable
private fun SignificantChangeWarning(impact: GoalImpact) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(WarningOrange.copy(alpha = 0.1f))
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = Icons.Default.Warning,
            contentDescription = null,
            tint = WarningOrange,
            modifier = Modifier.size(16.dp)
        )

        Column {
            Text(
                text = "Significant Change",
                style = MaterialTheme.typography.labelMedium
            )
            Text(
                text = getWarningMessage(impact),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Spacer(modifier = Modifier.weight(1f))
    }
}

private fun getWarningMessage(impact: GoalImpact): String {
    return when {
        impact.dailyTargetChange > 50 -> "Daily target increased significantly. Consider adjusting your deadline."
        impact.progressChange < -0.2 -> "Progress percentage will decrease substantially."
        impact.daysRemainingChange < -30 -> "Deadline moved much closer. Ensure the new timeline is realistic."
        else -> "Review the changes carefully before saving."
    }
}

private fun formatCurrency(amount: Double, currency: String): String {
    val format = NumberFormat.getCurrencyInstance(Locale.US)
    format.currency = java.util.Currency.getInstance(currency)
    return format.format(amount)
}

private fun buildAccessibilityDescription(impact: GoalImpact, currency: String): String {
    val progressChange = ((impact.newProgress - impact.oldProgress) * 100).toInt()
    val dailyChange = impact.newDailyTarget - impact.oldDailyTarget

    return buildString {
        append("Impact preview showing changes to your goal. ")
        append("Progress will change by $progressChange percentage points. ")
        append("Daily target will change by ${formatCurrency(dailyChange, currency)}. ")
        if (impact.isPositiveChange) {
            append("This is a positive change.")
        } else {
            append("This change requires attention.")
        }
    }
}
