package com.xax.CryptoSavingsTracker.presentation.charts

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleGreen
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleRed
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/**
 * Historical data point for forecast chart
 */
data class HistoricalDataPoint(
    val date: LocalDate,
    val balance: Double
)

/**
 * Forecast data point with 3 scenarios
 */
data class ForecastDataPoint(
    val date: LocalDate,
    val optimistic: Double,
    val realistic: Double,
    val pessimistic: Double
)

/**
 * Forecast type enum matching iOS
 */
enum class ForecastType(val displayName: String, val color: Color) {
    OPTIMISTIC("Optimistic", AccessibleGreen),
    REALISTIC("Realistic", Color(0xFF2196F3)), // Blue
    PESSIMISTIC("Pessimistic", AccessibleRed)
}

/**
 * Forecast chart matching iOS ForecastChartView
 * Shows historical data and 3 forecast scenarios (optimistic/realistic/pessimistic)
 */
@Composable
fun ForecastChart(
    historicalData: List<HistoricalDataPoint>,
    forecastData: List<ForecastDataPoint>,
    targetValue: Double,
    targetDate: LocalDate,
    currency: String,
    modifier: Modifier = Modifier,
    chartHeight: Int = 300
) {
    var selectedForecastType by remember { mutableStateOf(ForecastType.REALISTIC) }

    val animationProgress = remember { Animatable(0f) }

    LaunchedEffect(Unit) {
        animationProgress.animateTo(
            targetValue = 1f,
            animationSpec = tween(durationMillis = 1500)
        )
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
                shape = RoundedCornerShape(12.dp)
            )
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Goal Forecast",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
        }

        // Target info
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                text = "Target: ${String.format("%.2f", targetValue)} $currency",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = "Deadline: ${targetDate.format(DateTimeFormatter.ofPattern("MMM d, yyyy"))}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        // Forecast type selector
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ForecastType.entries.forEach { type ->
                val isSelected = type == selectedForecastType
                Surface(
                    modifier = Modifier
                        .weight(1f)
                        .clickable { selectedForecastType = type },
                    shape = RoundedCornerShape(8.dp),
                    color = if (isSelected) type.color.copy(alpha = 0.2f) else Color.Transparent,
                    border = if (isSelected) null else androidx.compose.foundation.BorderStroke(
                        1.dp,
                        MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)
                    )
                ) {
                    Text(
                        text = type.displayName,
                        modifier = Modifier.padding(vertical = 8.dp, horizontal = 4.dp),
                        style = MaterialTheme.typography.labelMedium,
                        color = if (isSelected) type.color else MaterialTheme.colorScheme.onSurface,
                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
                    )
                }
            }
        }

        // Chart
        ForecastChartCanvas(
            historicalData = historicalData,
            forecastData = forecastData,
            selectedType = selectedForecastType,
            targetValue = targetValue,
            animationProgress = animationProgress.value,
            modifier = Modifier
                .fillMaxWidth()
                .height(chartHeight.dp)
        )

        // Target indicator
        Row(
            modifier = Modifier
                .background(
                    color = AccessibleGreen.copy(alpha = 0.1f),
                    shape = RoundedCornerShape(4.dp)
                )
                .padding(horizontal = 8.dp, vertical = 4.dp)
        ) {
            Text(
                text = "Target: ${String.format("%.0f", targetValue)} $currency",
                style = MaterialTheme.typography.labelSmall,
                color = AccessibleGreen
            )
        }

        // Forecast analysis
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                text = "Forecast Analysis",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Medium
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ForecastType.entries.forEach { type ->
                    val lastForecast = forecastData.lastOrNull()
                    val value = when (type) {
                        ForecastType.OPTIMISTIC -> lastForecast?.optimistic ?: 0.0
                        ForecastType.REALISTIC -> lastForecast?.realistic ?: 0.0
                        ForecastType.PESSIMISTIC -> lastForecast?.pessimistic ?: 0.0
                    }
                    val shortfall = (targetValue - value).coerceAtLeast(0.0)
                    val isSelected = type == selectedForecastType

                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .background(
                                color = type.color.copy(alpha = 0.1f),
                                shape = RoundedCornerShape(8.dp)
                            )
                            .then(
                                if (isSelected) Modifier.border(
                                    2.dp,
                                    type.color,
                                    RoundedCornerShape(8.dp)
                                ) else Modifier
                            )
                            .padding(8.dp)
                            .clickable { selectedForecastType = type },
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(8.dp)
                                    .background(type.color, CircleShape)
                            )
                            Text(
                                text = type.displayName,
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.Medium
                            )
                        }

                        Text(
                            text = "${String.format("%.0f", value)} $currency",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Medium
                        )

                        if (shortfall > 0) {
                            Text(
                                text = "Shortfall: ${String.format("%.0f", shortfall)}",
                                style = MaterialTheme.typography.labelSmall,
                                color = AccessibleRed
                            )
                        } else {
                            Text(
                                text = "Goal achieved!",
                                style = MaterialTheme.typography.labelSmall,
                                color = AccessibleGreen
                            )
                        }
                    }
                }
            }
        }

        // Required daily savings
        val lastHistorical = historicalData.lastOrNull()
        if (lastHistorical != null) {
            val currentValue = lastHistorical.balance
            val daysRemaining = ChronoUnit.DAYS.between(LocalDate.now(), targetDate).coerceAtLeast(1)
            val requiredDaily = ((targetValue - currentValue) / daysRemaining).coerceAtLeast(0.0)

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                        shape = RoundedCornerShape(8.dp)
                    )
                    .padding(12.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column {
                    Text(
                        text = "Required Daily Savings",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = "${String.format("%.2f", requiredDaily)} $currency",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium
                    )
                }

                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = "Days Remaining",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = "$daysRemaining",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium,
                        color = if (daysRemaining < 30) Color(0xFFFF9800) else MaterialTheme.colorScheme.onSurface
                    )
                }
            }
        }
    }
}

@Composable
private fun ForecastChartCanvas(
    historicalData: List<HistoricalDataPoint>,
    forecastData: List<ForecastDataPoint>,
    selectedType: ForecastType,
    targetValue: Double,
    animationProgress: Float,
    modifier: Modifier = Modifier
) {
    val historicalLineColor = MaterialTheme.colorScheme.primary

    // Combine data for selected forecast type
    val combinedData = remember(historicalData, forecastData, selectedType) {
        val historical = historicalData.map { it.date to it.balance }
        val forecast = forecastData.map { point ->
            val value = when (selectedType) {
                ForecastType.OPTIMISTIC -> point.optimistic
                ForecastType.REALISTIC -> point.realistic
                ForecastType.PESSIMISTIC -> point.pessimistic
            }
            point.date to value
        }
        historical + forecast
    }

    val minValue = remember(combinedData, targetValue) {
        (combinedData.minOfOrNull { it.second } ?: 0.0).coerceAtMost(targetValue * 0.8)
    }

    val maxValue = remember(combinedData, targetValue) {
        (combinedData.maxOfOrNull { it.second } ?: 100.0).coerceAtLeast(targetValue * 1.1)
    }

    val valueRange = (maxValue - minValue).coerceAtLeast(1.0)

    Canvas(modifier = modifier) {
        if (combinedData.isEmpty()) return@Canvas

        val canvasWidth = size.width
        val canvasHeight = size.height
        val padding = 40f

        val chartWidth = canvasWidth - padding * 2
        val chartHeight = canvasHeight - padding * 2

        // Calculate points
        val points = combinedData.mapIndexed { index, (_, value) ->
            val x = padding + (chartWidth * index / (combinedData.size - 1).coerceAtLeast(1))
            val normalizedValue = (value - minValue) / valueRange
            val y = padding + chartHeight * (1f - normalizedValue.toFloat())
            Offset(x, y)
        }

        // Draw target line
        val targetY = padding + chartHeight * (1f - ((targetValue - minValue) / valueRange).toFloat())
        drawLine(
            color = AccessibleGreen.copy(alpha = 0.5f),
            start = Offset(padding, targetY),
            end = Offset(canvasWidth - padding, targetY),
            strokeWidth = 2f,
            pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(10f, 10f))
        )

        // Draw historical line (solid)
        val historicalPointCount = historicalData.size
        if (historicalPointCount > 1) {
            val historicalPath = Path().apply {
                val animatedCount = (historicalPointCount * animationProgress).toInt().coerceAtLeast(1)
                val firstPoint = points.first()
                moveTo(firstPoint.x, firstPoint.y)
                for (i in 1 until animatedCount.coerceAtMost(historicalPointCount)) {
                    lineTo(points[i].x, points[i].y)
                }
            }
            drawPath(
                path = historicalPath,
                color = historicalLineColor,
                style = Stroke(width = 3f, cap = StrokeCap.Round, join = StrokeJoin.Round)
            )
        }

        // Draw forecast line (dashed)
        if (forecastData.isNotEmpty() && historicalPointCount > 0) {
            val forecastStartIndex = historicalPointCount - 1
            val forecastPath = Path().apply {
                val startPoint = points[forecastStartIndex]
                moveTo(startPoint.x, startPoint.y)
                val animatedForecastCount = ((points.size - forecastStartIndex) * animationProgress).toInt().coerceAtLeast(1)
                for (i in forecastStartIndex + 1 until (forecastStartIndex + animatedForecastCount).coerceAtMost(points.size)) {
                    lineTo(points[i].x, points[i].y)
                }
            }
            drawPath(
                path = forecastPath,
                color = selectedType.color,
                style = Stroke(
                    width = 3f,
                    cap = StrokeCap.Round,
                    join = StrokeJoin.Round,
                    pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(15f, 10f))
                )
            )
        }
    }
}
