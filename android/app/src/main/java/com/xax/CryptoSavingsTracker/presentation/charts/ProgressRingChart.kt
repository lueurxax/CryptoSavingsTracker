package com.xax.CryptoSavingsTracker.presentation.charts

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleGreen
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleRed
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleYellow

/**
 * Progress ring chart matching iOS ProgressRingView.
 * Supports 0-150% progress with dynamic colors.
 */
@Composable
fun ProgressRingChart(
    progress: Float,
    current: Double,
    target: Double,
    currency: String,
    modifier: Modifier = Modifier,
    size: Dp = 200.dp,
    strokeWidth: Dp = 20.dp,
    showLabels: Boolean = true
) {
    // Clamp progress to 0-1.5 (150%)
    val clampedProgress = progress.coerceIn(0f, 1.5f)

    // Animation
    val animatedProgress = remember { Animatable(0f) }

    LaunchedEffect(clampedProgress) {
        animatedProgress.animateTo(
            targetValue = clampedProgress,
            animationSpec = tween(durationMillis = 1200)
        )
    }

    // Colors based on progress
    val progressColor = when {
        clampedProgress < 0.25f -> AccessibleRed
        clampedProgress < 0.5f -> Color(0xFFFF9800) // Orange
        clampedProgress < 0.75f -> AccessibleYellow
        clampedProgress < 1.0f -> AccessibleGreen
        else -> MaterialTheme.colorScheme.primary // Blue for 100%+
    }

    val gradientColors = when {
        clampedProgress >= 1.0f -> listOf(
            MaterialTheme.colorScheme.primary,
            MaterialTheme.colorScheme.tertiary
        )
        clampedProgress >= 0.75f -> listOf(AccessibleGreen, MaterialTheme.colorScheme.primary)
        clampedProgress >= 0.5f -> listOf(AccessibleYellow, AccessibleGreen)
        clampedProgress >= 0.25f -> listOf(Color(0xFFFF9800), AccessibleYellow)
        else -> listOf(AccessibleRed, Color(0xFFFF9800))
    }

    val backgroundColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)

    Box(
        modifier = modifier.size(size),
        contentAlignment = Alignment.Center
    ) {
        Canvas(
            modifier = Modifier.fillMaxSize()
        ) {
            val canvasSize = this.size
            val radius = (canvasSize.minDimension - strokeWidth.toPx()) / 2
            val center = Offset(canvasSize.width / 2, canvasSize.height / 2)

            // Background ring
            drawCircle(
                color = backgroundColor,
                radius = radius,
                center = center,
                style = Stroke(width = strokeWidth.toPx())
            )

            // Progress arc (up to 100%)
            val sweepAngle = (animatedProgress.value.coerceAtMost(1f) * 360f)
            drawArc(
                brush = Brush.sweepGradient(
                    colors = gradientColors,
                    center = center
                ),
                startAngle = -90f,
                sweepAngle = sweepAngle,
                useCenter = false,
                topLeft = Offset(
                    center.x - radius,
                    center.y - radius
                ),
                size = Size(radius * 2, radius * 2),
                style = Stroke(
                    width = strokeWidth.toPx(),
                    cap = StrokeCap.Round
                )
            )

            // Over-achievement indicator (100%+ as dashed inner ring)
            if (animatedProgress.value > 1f) {
                val overProgress = animatedProgress.value - 1f
                val innerRadius = radius - strokeWidth.toPx() * 0.5f
                val overSweepAngle = overProgress * 360f

                drawArc(
                    brush = Brush.linearGradient(
                        colors = listOf(Color(0xFF9C27B0), Color(0xFFE91E63))
                    ),
                    startAngle = -90f,
                    sweepAngle = overSweepAngle,
                    useCenter = false,
                    topLeft = Offset(
                        center.x - innerRadius,
                        center.y - innerRadius
                    ),
                    size = Size(innerRadius * 2, innerRadius * 2),
                    style = Stroke(
                        width = strokeWidth.toPx() * 0.6f,
                        cap = StrokeCap.Round
                    )
                )
            }

            // Progress indicator dot
            val dotAngle = Math.toRadians((animatedProgress.value.coerceAtMost(1f) * 360f - 90f).toDouble())
            val dotX = center.x + radius * kotlin.math.cos(dotAngle).toFloat()
            val dotY = center.y + radius * kotlin.math.sin(dotAngle).toFloat()

            drawCircle(
                color = progressColor,
                radius = strokeWidth.toPx() * 0.4f,
                center = Offset(dotX, dotY)
            )
        }

        // Center labels
        if (showLabels) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                // Percentage
                Text(
                    text = "${(animatedProgress.value * 100).toInt()}%",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = progressColor
                )

                // Current value
                Text(
                    text = String.format("%.2f %s", current, currency),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
                )

                // Target value
                Text(
                    text = "of ${String.format("%.2f", target)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                // Achievement badge
                if (animatedProgress.value >= 1f) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "⭐ ACHIEVED!",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
        }
    }
}

/**
 * Compact progress ring for smaller displays
 */
@Composable
fun CompactProgressRing(
    progress: Float,
    modifier: Modifier = Modifier,
    size: Dp = 48.dp,
    strokeWidth: Dp = 4.dp
) {
    val clampedProgress = progress.coerceIn(0f, 1f)
    val animatedProgress = remember { Animatable(0f) }

    LaunchedEffect(clampedProgress) {
        animatedProgress.animateTo(
            targetValue = clampedProgress,
            animationSpec = tween(durationMillis = 800)
        )
    }

    val progressColor = when {
        clampedProgress < 0.25f -> AccessibleRed
        clampedProgress < 0.5f -> Color(0xFFFF9800)
        clampedProgress < 0.75f -> AccessibleYellow
        else -> AccessibleGreen
    }

    val backgroundColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)

    Box(
        modifier = modifier.size(size),
        contentAlignment = Alignment.Center
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val canvasSize = this.size
            val radius = (canvasSize.minDimension - strokeWidth.toPx()) / 2
            val center = Offset(canvasSize.width / 2, canvasSize.height / 2)

            // Background
            drawCircle(
                color = backgroundColor,
                radius = radius,
                center = center,
                style = Stroke(width = strokeWidth.toPx())
            )

            // Progress
            drawArc(
                color = progressColor,
                startAngle = -90f,
                sweepAngle = animatedProgress.value * 360f,
                useCenter = false,
                topLeft = Offset(center.x - radius, center.y - radius),
                size = Size(radius * 2, radius * 2),
                style = Stroke(width = strokeWidth.toPx(), cap = StrokeCap.Round)
            )
        }

        Text(
            text = "${(animatedProgress.value * 100).toInt()}%",
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = progressColor,
            textAlign = TextAlign.Center
        )
    }
}
