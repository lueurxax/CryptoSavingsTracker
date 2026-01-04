package com.xax.CryptoSavingsTracker.presentation.charts

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleGreen
import java.time.LocalDate

/**
 * Data point for sparkline chart
 */
data class SparklineDataPoint(
    val date: LocalDate,
    val value: Double
)

/**
 * Compact sparkline chart for dashboard overview - matches iOS SparklineChartView
 */
@Composable
fun SparklineChart(
    dataPoints: List<SparklineDataPoint>,
    modifier: Modifier = Modifier,
    height: Dp = 40.dp,
    showGradient: Boolean = true,
    lineColor: Color = AccessibleGreen,
    gradientColor: Color = lineColor
) {
    val sortedPoints = remember(dataPoints) {
        dataPoints.sortedBy { it.date }
    }

    val minValue = remember(sortedPoints) {
        sortedPoints.minOfOrNull { it.value } ?: 0.0
    }

    val maxValue = remember(sortedPoints) {
        sortedPoints.maxOfOrNull { it.value } ?: 100.0
    }

    val valueRange = remember(minValue, maxValue) {
        (maxValue - minValue).coerceAtLeast(0.01)
    }

    // Animation
    val animationProgress = remember { Animatable(0f) }

    LaunchedEffect(sortedPoints) {
        animationProgress.snapTo(0f)
        animationProgress.animateTo(
            targetValue = 1f,
            animationSpec = tween(durationMillis = 1500)
        )
    }

    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
    ) {
        if (sortedPoints.isEmpty() || valueRange <= 0) return@Canvas

        val canvasWidth = size.width
        val canvasHeight = size.height
        val pointCount = sortedPoints.size

        // Calculate points
        val points = sortedPoints.mapIndexed { index, point ->
            val x = if (pointCount > 1) {
                canvasWidth * index / (pointCount - 1)
            } else {
                canvasWidth / 2
            }
            val normalizedValue = (point.value - minValue) / valueRange
            val y = canvasHeight * (1f - normalizedValue.toFloat())
            Offset(x, y)
        }

        if (points.isEmpty()) return@Canvas

        // Determine how many points to draw based on animation progress
        val animatedPointCount = (points.size * animationProgress.value).toInt().coerceAtLeast(1)
        val animatedPoints = points.take(animatedPointCount)

        // Draw gradient fill area
        if (showGradient && animatedPoints.size > 1) {
            val gradientPath = Path().apply {
                val firstPoint = animatedPoints.first()
                moveTo(firstPoint.x, canvasHeight)
                lineTo(firstPoint.x, firstPoint.y)

                for (point in animatedPoints.drop(1)) {
                    lineTo(point.x, point.y)
                }

                val lastPoint = animatedPoints.last()
                lineTo(lastPoint.x, canvasHeight)
                close()
            }

            drawPath(
                path = gradientPath,
                brush = Brush.verticalGradient(
                    colors = listOf(
                        gradientColor.copy(alpha = 0.3f),
                        gradientColor.copy(alpha = 0.05f)
                    )
                )
            )
        }

        // Draw sparkline
        if (animatedPoints.size > 1) {
            val linePath = Path().apply {
                val firstPoint = animatedPoints.first()
                moveTo(firstPoint.x, firstPoint.y)

                for (point in animatedPoints.drop(1)) {
                    lineTo(point.x, point.y)
                }
            }

            drawPath(
                path = linePath,
                brush = Brush.horizontalGradient(
                    colors = listOf(lineColor, lineColor.copy(alpha = 0.8f))
                ),
                style = Stroke(
                    width = 2.5.dp.toPx(),
                    cap = StrokeCap.Round,
                    join = StrokeJoin.Round
                )
            )
        }

        // Draw end point indicator
        if (animatedPoints.isNotEmpty()) {
            val lastPoint = animatedPoints.last()
            drawCircle(
                color = lineColor,
                radius = 3.dp.toPx(),
                center = lastPoint
            )
        }
    }
}

/**
 * Sparkline with trend indicator showing positive/negative change
 */
@Composable
fun TrendSparkline(
    dataPoints: List<SparklineDataPoint>,
    modifier: Modifier = Modifier,
    height: Dp = 40.dp
) {
    val trend = remember(dataPoints) {
        if (dataPoints.size < 2) 0.0
        else {
            val sorted = dataPoints.sortedBy { it.date }
            val first = sorted.first().value
            val last = sorted.last().value
            if (first > 0) (last - first) / first else 0.0
        }
    }

    val lineColor = when {
        trend > 0.01 -> AccessibleGreen
        trend < -0.01 -> Color(0xFFE53935) // Red
        else -> Color(0xFF9E9E9E) // Gray for flat
    }

    SparklineChart(
        dataPoints = dataPoints,
        modifier = modifier,
        height = height,
        lineColor = lineColor,
        gradientColor = lineColor
    )
}

/**
 * Mini sparkline for use in list items
 */
@Composable
fun MiniSparkline(
    values: List<Double>,
    modifier: Modifier = Modifier,
    height: Dp = 24.dp,
    lineColor: Color = AccessibleGreen
) {
    // Convert values to SparklineDataPoints with synthetic dates
    val dataPoints = remember(values) {
        values.mapIndexed { index, value ->
            SparklineDataPoint(
                date = LocalDate.now().minusDays((values.size - 1 - index).toLong()),
                value = value
            )
        }
    }

    SparklineChart(
        dataPoints = dataPoints,
        modifier = modifier,
        height = height,
        showGradient = false,
        lineColor = lineColor
    )
}
