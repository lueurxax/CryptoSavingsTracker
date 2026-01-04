package com.xax.CryptoSavingsTracker.presentation.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties

/**
 * Data class for tooltip content
 */
data class TooltipData(
    val title: String,
    val description: String
)

/**
 * Reusable help tooltip component matching iOS HelpTooltip
 */
@Composable
fun HelpTooltip(
    title: String,
    description: String,
    modifier: Modifier = Modifier
) {
    var showTooltip by remember { mutableStateOf(false) }

    Box(modifier = modifier) {
        IconButton(
            onClick = { showTooltip = true },
            modifier = Modifier.size(24.dp)
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.HelpOutline,
                contentDescription = "Help: $title",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(16.dp)
            )
        }

        if (showTooltip) {
            Popup(
                onDismissRequest = { showTooltip = false },
                properties = PopupProperties(focusable = true)
            ) {
                Surface(
                    modifier = Modifier
                        .widthIn(max = 300.dp)
                        .padding(8.dp),
                    shape = RoundedCornerShape(12.dp),
                    shadowElevation = 8.dp,
                    color = MaterialTheme.colorScheme.surface
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = title,
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold
                            )
                            IconButton(
                                onClick = { showTooltip = false },
                                modifier = Modifier.size(24.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Close,
                                    contentDescription = "Close help",
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.size(20.dp)
                                )
                            }
                        }

                        Text(
                            text = description,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                }
            }
        }
    }
}

/**
 * Row with text and help tooltip
 */
@Composable
fun TextWithTooltip(
    text: String,
    tooltip: TooltipData,
    modifier: Modifier = Modifier,
    textStyle: androidx.compose.ui.text.TextStyle = MaterialTheme.typography.bodyMedium
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = text,
            style = textStyle
        )
        HelpTooltip(
            title = tooltip.title,
            description = tooltip.description
        )
    }
}

/**
 * Predefined tooltip content for common metrics - matches iOS MetricTooltips
 */
object MetricTooltips {
    // Progress Ring tooltips
    val currentTotal = TooltipData(
        title = "Current Total",
        description = "The combined value of all your cryptocurrency assets in this goal, converted to your chosen currency using current exchange rates."
    )

    val progress = TooltipData(
        title = "Progress Percentage",
        description = "How close you are to reaching your savings goal. Colors change from red (0-25%) to green (75-100%) to show your progress visually."
    )

    // Dashboard metrics tooltips
    val dailyTarget = TooltipData(
        title = "Daily Target",
        description = "The amount you need to save each day to reach your goal by the deadline. This is calculated as: (Target Amount - Current Total) / Days Remaining."
    )

    val daysRemaining = TooltipData(
        title = "Days Remaining",
        description = "Number of days left until your goal deadline. The color turns red when less than 30 days remain as a reminder to increase your savings rate."
    )

    val streak = TooltipData(
        title = "Savings Streak",
        description = "Number of consecutive days you've made transactions toward this goal. Maintaining a streak helps build consistent saving habits."
    )

    // Chart tooltips
    val balanceHistory = TooltipData(
        title = "Balance History",
        description = "Shows how your total portfolio value has changed over time. The line represents the combined value of all assets in your chosen currency."
    )

    val assetComposition = TooltipData(
        title = "Asset Breakdown",
        description = "Visual representation of how your portfolio is distributed across different cryptocurrencies. Each color represents a different asset."
    )

    val forecast = TooltipData(
        title = "Goal Forecast",
        description = "Projections of whether you'll reach your goal based on current savings trends. Shows optimistic, realistic, and pessimistic scenarios."
    )

    val heatmap = TooltipData(
        title = "Activity Heatmap",
        description = "Calendar view showing your transaction activity. Darker colors indicate days with more transaction volume. Helps identify saving patterns."
    )

    val transactionCount = TooltipData(
        title = "Transaction Count",
        description = "Total number of buy/sell transactions recorded for this goal. Includes both manual entries and imported blockchain transactions."
    )

    // Forecast specific tooltips
    val requiredDaily = TooltipData(
        title = "Required Daily Savings",
        description = "Based on your current progress and time remaining, this is the daily amount needed to reach your goal on schedule."
    )

    val shortfall = TooltipData(
        title = "Projected Shortfall",
        description = "The estimated amount you'll be short of your goal if current trends continue. Consider increasing your savings rate or extending your deadline."
    )

    // Exchange rate tooltips
    val exchangeRates = TooltipData(
        title = "Exchange Rates",
        description = "All cryptocurrency values are converted to your goal currency using real-time exchange rates from CoinGecko. Rates update automatically."
    )
}
