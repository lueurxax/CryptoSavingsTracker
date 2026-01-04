package com.xax.CryptoSavingsTracker.presentation.charts

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleGreen
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.TextStyle
import java.util.Locale

/**
 * Heatmap day data matching iOS HeatmapDay
 */
data class HeatmapDay(
    val date: LocalDate,
    val value: Double,
    val intensity: Double, // 0.0 to 1.0
    val transactionCount: Int = 0
) {
    val color: Color
        get() = when {
            transactionCount == 0 -> Color.Gray.copy(alpha = 0.1f)
            transactionCount <= 2 -> AccessibleGreen.copy(alpha = 0.3f)
            transactionCount <= 5 -> AccessibleGreen.copy(alpha = 0.5f)
            transactionCount <= 8 -> AccessibleGreen.copy(alpha = 0.7f)
            else -> AccessibleGreen.copy(alpha = 0.9f)
        }
}

/**
 * Heatmap calendar view matching iOS HeatmapCalendarView
 * Shows transaction activity over a year with color-coded cells
 */
@Composable
fun HeatmapCalendar(
    heatmapData: List<HeatmapDay>,
    modifier: Modifier = Modifier,
    year: Int = LocalDate.now().year,
    title: String = "Activity Heatmap",
    showLegend: Boolean = true,
    animateOnAppear: Boolean = true
) {
    var selectedDay by remember { mutableStateOf<HeatmapDay?>(null) }

    val animationProgress = remember { Animatable(0f) }

    LaunchedEffect(animateOnAppear) {
        if (animateOnAppear) {
            animationProgress.animateTo(
                targetValue = 1f,
                animationSpec = tween(durationMillis = 2000)
            )
        } else {
            animationProgress.snapTo(1f)
        }
    }

    // Stats calculations
    val totalValue = remember(heatmapData) { heatmapData.sumOf { it.value } }
    val averageValue = remember(heatmapData) {
        if (heatmapData.isEmpty()) 0.0 else totalValue / heatmapData.size
    }
    val streakCount = remember(heatmapData) { calculateStreak(heatmapData) }

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
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = year.toString(),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        // Stats
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            StatItem("Total", String.format("%.0f", totalValue))
            StatItem("Daily Avg", String.format("%.1f", averageValue))
            StatItem("Best Streak", "$streakCount days")
        }

        // Calendar heatmap (horizontal scrollable)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            (1..12).forEach { month ->
                MonthGrid(
                    year = year,
                    month = month,
                    heatmapData = heatmapData,
                    animationProgress = animationProgress.value,
                    selectedDay = selectedDay,
                    onDayClick = { day -> selectedDay = day }
                )
            }
        }

        // Legend
        if (showLegend) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = "Transaction Activity",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Medium
                )

                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "0",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )

                    listOf(0.1f, 0.3f, 0.5f, 0.7f, 0.9f).forEach { alpha ->
                        Box(
                            modifier = Modifier
                                .size(12.dp)
                                .clip(RoundedCornerShape(2.dp))
                                .background(
                                    if (alpha == 0.1f) Color.Gray.copy(alpha = 0.1f)
                                    else AccessibleGreen.copy(alpha = alpha)
                                )
                        )
                    }

                    Text(
                        text = "10+",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                Text(
                    text = "Color indicates transaction count per day",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        // Selected day detail
        selectedDay?.let { day ->
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(8.dp),
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = day.date.format(java.time.format.DateTimeFormatter.ofPattern("EEEE, MMMM d")),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium
                        )
                        TextButton(onClick = { selectedDay = null }) {
                            Text("Dismiss")
                        }
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Transactions:", style = MaterialTheme.typography.bodySmall)
                        Text(
                            "${day.transactionCount}",
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Medium
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Volume:", style = MaterialTheme.typography.bodySmall)
                        Text(
                            String.format("%.2f", day.value),
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Medium
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Intensity:", style = MaterialTheme.typography.bodySmall)
                        Text(
                            "${(day.intensity * 100).toInt()}%",
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Medium
                        )
                    }

                    when {
                        day.transactionCount > 5 -> Text(
                            "High activity day!",
                            style = MaterialTheme.typography.labelSmall,
                            color = AccessibleGreen
                        )
                        day.transactionCount == 0 -> Text(
                            "No transactions",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        day.transactionCount == 1 -> Text(
                            "Light activity",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun StatItem(label: String, value: String) {
    Column {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium
        )
    }
}

@Composable
private fun MonthGrid(
    year: Int,
    month: Int,
    heatmapData: List<HeatmapDay>,
    animationProgress: Float,
    selectedDay: HeatmapDay?,
    onDayClick: (HeatmapDay?) -> Unit
) {
    val yearMonth = YearMonth.of(year, month)
    val firstDay = yearMonth.atDay(1)
    val lastDay = yearMonth.atEndOfMonth()

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        // Month label
        Text(
            text = yearMonth.month.getDisplayName(TextStyle.SHORT, Locale.getDefault()),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        // Week grid
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            var currentDate = firstDay
            // Adjust to start of week (Sunday = 7 in ISO)
            val startOffset = (currentDate.dayOfWeek.value % 7)

            while (currentDate <= lastDay || currentDate.dayOfWeek != DayOfWeek.SUNDAY) {
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    repeat(7) { dayOfWeek ->
                        if (currentDate <= lastDay && currentDate.month.value == month &&
                            (currentDate > firstDay || dayOfWeek >= startOffset)
                        ) {
                            val dayData = heatmapData.find { it.date == currentDate }
                            val isSelected = selectedDay?.date == currentDate
                            val effectiveIntensity = (dayData?.intensity ?: 0.0) * animationProgress

                            Box(
                                modifier = Modifier
                                    .size(12.dp)
                                    .clip(RoundedCornerShape(2.dp))
                                    .background(
                                        dayData?.color?.copy(alpha = effectiveIntensity.toFloat())
                                            ?: Color.Gray.copy(alpha = 0.1f)
                                    )
                                    .then(
                                        if (isSelected) Modifier.border(
                                            2.dp,
                                            MaterialTheme.colorScheme.primary,
                                            RoundedCornerShape(2.dp)
                                        ) else Modifier
                                    )
                                    .clickable { onDayClick(dayData) }
                            )
                            currentDate = currentDate.plusDays(1)
                        } else {
                            // Empty placeholder for days outside month
                            Box(modifier = Modifier.size(12.dp))
                            if (currentDate < firstDay) {
                                // Skip days before first of month
                            }
                        }
                    }
                }
                if (currentDate > lastDay) break
            }
        }
    }
}

private fun calculateStreak(heatmapData: List<HeatmapDay>): Int {
    val sortedDates = heatmapData
        .filter { it.value > 0 }
        .map { it.date }
        .sorted()

    if (sortedDates.isEmpty()) return 0

    var currentStreak = 1
    var maxStreak = 1

    for (i in 1 until sortedDates.size) {
        val current = sortedDates[i]
        val previous = sortedDates[i - 1]

        if (current == previous.plusDays(1)) {
            currentStreak++
            maxStreak = maxOf(maxStreak, currentStreak)
        } else {
            currentStreak = 1
        }
    }

    return maxStreak
}

/**
 * Compact heatmap for smaller views
 */
@Composable
fun CompactHeatmap(
    heatmapData: List<HeatmapDay>,
    modifier: Modifier = Modifier,
    timeRangeDays: Int = 30,
    columns: Int = 10
) {
    val cutoffDate = LocalDate.now().minusDays(timeRangeDays.toLong())
    val recentData = remember(heatmapData, cutoffDate) {
        heatmapData
            .filter { it.date >= cutoffDate }
            .sortedBy { it.date }
            .takeLast(columns * 6)
    }

    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        recentData.chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                row.forEach { day ->
                    Box(
                        modifier = Modifier
                            .size(12.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(day.color)
                    )
                }
            }
        }
    }
}
