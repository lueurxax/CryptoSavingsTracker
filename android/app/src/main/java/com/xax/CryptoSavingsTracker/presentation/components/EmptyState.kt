package com.xax.CryptoSavingsTracker.presentation.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleGreen
import com.xax.CryptoSavingsTracker.presentation.theme.IconSize
import com.xax.CryptoSavingsTracker.presentation.theme.Spacing

/**
 * Action configuration for empty states
 */
data class EmptyStateAction(
    val title: String,
    val icon: ImageVector? = null,
    val isPrimary: Boolean = true,
    val onClick: () -> Unit
)

/**
 * Illustration types for empty states
 */
enum class EmptyStateIllustration {
    CHART,
    PORTFOLIO,
    TRANSACTION,
    GOAL,
    SEARCH
}

/**
 * Comprehensive empty state component matching iOS EmptyStateView
 */
@Composable
fun EmptyStateView(
    icon: ImageVector,
    title: String,
    description: String,
    modifier: Modifier = Modifier,
    primaryAction: EmptyStateAction? = null,
    secondaryAction: EmptyStateAction? = null,
    illustration: EmptyStateIllustration? = null
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        // Illustration or Icon
        if (illustration != null) {
            Box(
                modifier = Modifier.size(100.dp),
                contentAlignment = Alignment.Center
            ) {
                EmptyStateIllustrationView(illustration)
            }
        } else {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(IconSize.feature),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
            )
        }

        Spacer(modifier = Modifier.height(Spacing.lg))

        // Title
        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(Spacing.sm))

        // Description
        Text(
            text = description,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = Spacing.md)
        )

        // Actions
        if (primaryAction != null || secondaryAction != null) {
            Spacer(modifier = Modifier.height(Spacing.lg))

            Column(
                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                primaryAction?.let { action ->
                    Button(
                        onClick = action.onClick,
                        modifier = Modifier.fillMaxWidth(0.7f)
                    ) {
                        action.icon?.let { icon ->
                            Icon(
                                imageVector = icon,
                                contentDescription = null,
                                modifier = Modifier.size(IconSize.small)
                            )
                            Spacer(modifier = Modifier.width(Spacing.xs))
                        }
                        Text(
                            text = action.title,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }

                secondaryAction?.let { action ->
                    OutlinedButton(
                        onClick = action.onClick,
                        modifier = Modifier.fillMaxWidth(0.7f)
                    ) {
                        action.icon?.let { icon ->
                            Icon(
                                imageVector = icon,
                                contentDescription = null,
                                modifier = Modifier.size(IconSize.small)
                            )
                            Spacer(modifier = Modifier.width(Spacing.xs))
                        }
                        Text(
                            text = action.title,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyStateIllustrationView(illustration: EmptyStateIllustration) {
    val surfaceColor = MaterialTheme.colorScheme.surfaceVariant
    val tertiaryColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
    val primaryColor = MaterialTheme.colorScheme.primary

    when (illustration) {
        EmptyStateIllustration.CHART -> {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val width = size.width
                val height = size.height

                // Background
                drawRoundRect(
                    color = surfaceColor,
                    size = size,
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(16f)
                )

                // Chart line
                val path = Path().apply {
                    moveTo(width * 0.1f, height * 0.7f)
                    lineTo(width * 0.3f, height * 0.4f)
                    lineTo(width * 0.5f, height * 0.5f)
                    lineTo(width * 0.7f, height * 0.3f)
                    lineTo(width * 0.9f, height * 0.45f)
                }
                drawPath(
                    path = path,
                    color = tertiaryColor,
                    style = Stroke(width = 4f, cap = StrokeCap.Round)
                )

                // X-axis dots
                for (i in 0..4) {
                    drawCircle(
                        color = tertiaryColor,
                        radius = 4f,
                        center = Offset(width * (0.1f + 0.2f * i), height * 0.85f)
                    )
                }
            }
        }

        EmptyStateIllustration.PORTFOLIO -> {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val center = Offset(size.width / 2, size.height / 2)
                val radius = size.minDimension / 2.5f

                // Background circle
                drawCircle(
                    color = surfaceColor,
                    radius = radius,
                    center = center
                )

                // Pie segments
                val colors = listOf(
                    AccessibleGreen,
                    Color(0xFF2196F3),
                    Color(0xFFFF9800)
                )
                var startAngle = -90f
                colors.forEachIndexed { index, color ->
                    val sweepAngle = 120f
                    drawArc(
                        color = color,
                        startAngle = startAngle,
                        sweepAngle = sweepAngle,
                        useCenter = false,
                        style = Stroke(width = 16f),
                        topLeft = Offset(center.x - radius, center.y - radius),
                        size = androidx.compose.ui.geometry.Size(radius * 2, radius * 2)
                    )
                    startAngle += sweepAngle
                }
            }
        }

        EmptyStateIllustration.TRANSACTION -> {
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(Spacing.xs, Alignment.CenterVertically)
            ) {
                repeat(3) { index ->
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(20.dp),
                        shape = MaterialTheme.shapes.extraSmall,
                        color = surfaceColor
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = Spacing.xs),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(Spacing.xs)
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(Spacing.xs)
                                    .clip(CircleShape)
                                    .then(
                                        Modifier.fillMaxSize()
                                    ),
                                contentAlignment = Alignment.Center
                            ) {
                                Canvas(modifier = Modifier.fillMaxSize()) {
                                    drawCircle(
                                        color = if (index == 1) AccessibleGreen else tertiaryColor
                                    )
                                }
                            }
                            Surface(
                                modifier = Modifier
                                    .weight(1f)
                                    .height(6.dp),
                                shape = RoundedCornerShape(2.dp),
                                color = tertiaryColor
                            ) {}
                            Surface(
                                modifier = Modifier
                                    .width(30.dp)
                                    .height(6.dp),
                                shape = RoundedCornerShape(2.dp),
                                color = tertiaryColor
                            ) {}
                        }
                    }
                }
            }
        }

        EmptyStateIllustration.GOAL -> {
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Surface(
                    modifier = Modifier.size(80.dp),
                    shape = MaterialTheme.shapes.medium,
                    color = surfaceColor
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.Flag,
                            contentDescription = null,
                            modifier = Modifier.size(IconSize.large),
                            tint = tertiaryColor
                        )
                        Spacer(modifier = Modifier.height(Spacing.xs))
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(Spacing.xxs)
                        ) {
                            repeat(3) { index ->
                                Surface(
                                    modifier = Modifier
                                        .width(Spacing.sm)
                                        .height(Spacing.xxs),
                                    shape = RoundedCornerShape(2.dp),
                                    color = if (index == 0) AccessibleGreen else tertiaryColor
                                ) {}
                            }
                        }
                    }
                }
            }
        }

        EmptyStateIllustration.SEARCH -> {
            Surface(
                modifier = Modifier.size(80.dp),
                shape = CircleShape,
                color = surfaceColor
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = Icons.Default.Search,
                        contentDescription = null,
                        modifier = Modifier.size(IconSize.hero),
                        tint = tertiaryColor
                    )
                }
            }
        }
    }
}

// Predefined Empty States matching iOS

object EmptyStates {
    @Composable
    fun NoGoals(
        onCreateGoal: () -> Unit,
        onStartOnboarding: (() -> Unit)? = null
    ) {
        if (onStartOnboarding != null) {
            EmptyStateView(
                icon = Icons.Default.AutoAwesome,
                title = "Welcome to CryptoSavings!",
                description = "Let's get you set up with a personalized savings goal. Our quick setup will help you choose the right cryptocurrencies and timeline.",
                primaryAction = EmptyStateAction(
                    title = "Start Quick Setup",
                    icon = Icons.AutoMirrored.Filled.ArrowForward,
                    onClick = onStartOnboarding
                ),
                secondaryAction = EmptyStateAction(
                    title = "Create Goal Manually",
                    icon = Icons.Default.Add,
                    isPrimary = false,
                    onClick = onCreateGoal
                ),
                illustration = EmptyStateIllustration.GOAL
            )
        } else {
            EmptyStateView(
                icon = Icons.Default.Flag,
                title = "No Savings Goals Yet",
                description = "Create your first cryptocurrency savings goal to start tracking your progress and building wealth.",
                primaryAction = EmptyStateAction(
                    title = "Create Your First Goal",
                    icon = Icons.Default.Add,
                    onClick = onCreateGoal
                ),
                illustration = EmptyStateIllustration.GOAL
            )
        }
    }

    @Composable
    fun NoAssets(onAddAsset: () -> Unit) {
        EmptyStateView(
            icon = Icons.Default.AccountBalanceWallet,
            title = "No Assets in Goal",
            description = "Add cryptocurrency assets to this goal to start tracking your portfolio and progress.",
            primaryAction = EmptyStateAction(
                title = "Add Your First Asset",
                icon = Icons.Default.Add,
                onClick = onAddAsset
            ),
            illustration = EmptyStateIllustration.PORTFOLIO
        )
    }

    @Composable
    fun NoTransactions(
        onAddTransaction: () -> Unit,
        onImportTransactions: (() -> Unit)? = null
    ) {
        EmptyStateView(
            icon = Icons.Default.SwapHoriz,
            title = "No Transactions Yet",
            description = "Record your cryptocurrency purchases and sales to track your progress toward your savings goal.",
            primaryAction = EmptyStateAction(
                title = "Add Transaction",
                icon = Icons.Default.Add,
                onClick = onAddTransaction
            ),
            secondaryAction = onImportTransactions?.let {
                EmptyStateAction(
                    title = "Import from Blockchain",
                    icon = Icons.Default.Download,
                    isPrimary = false,
                    onClick = it
                )
            },
            illustration = EmptyStateIllustration.TRANSACTION
        )
    }

    @Composable
    fun NoChartData(chartType: String) {
        EmptyStateView(
            icon = Icons.AutoMirrored.Filled.ShowChart,
            title = "No Data to Display",
            description = "Add transactions to your assets to see ${chartType.lowercase()} data. Your chart will automatically update as you record activity.",
            illustration = EmptyStateIllustration.CHART
        )
    }

    @Composable
    fun NoSearchResults(query: String, onClearSearch: () -> Unit) {
        EmptyStateView(
            icon = Icons.Default.Search,
            title = "No Results Found",
            description = "No cryptocurrencies match '$query'. Try searching with a different term or symbol.",
            primaryAction = EmptyStateAction(
                title = "Clear Search",
                icon = Icons.Default.Clear,
                onClick = onClearSearch
            ),
            illustration = EmptyStateIllustration.SEARCH
        )
    }

    @Composable
    fun NoActivity() {
        EmptyStateView(
            icon = Icons.Default.CalendarMonth,
            title = "No Activity Yet",
            description = "Start making transactions to see your activity patterns. Consistent trading helps build good investment habits.",
            illustration = EmptyStateIllustration.CHART
        )
    }

    @Composable
    fun NoForecastData() {
        EmptyStateView(
            icon = Icons.AutoMirrored.Filled.TrendingUp,
            title = "Insufficient Data for Forecast",
            description = "Add more transaction history to generate meaningful projections. We need at least a few data points to predict trends.",
            illustration = EmptyStateIllustration.CHART
        )
    }
}
