package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.model.MonthlyRequirement
import com.xax.CryptoSavingsTracker.domain.model.RequirementStatus
import com.xax.CryptoSavingsTracker.presentation.navigation.Screen
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleGreen
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleRed
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleYellow
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MonthlyPlanningScreen(
    navController: NavController,
    viewModel: MonthlyPlanningViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Show error in snackbar
    LaunchedEffect(uiState.error) {
        uiState.error?.let { error ->
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Monthly Planning") },
                actions = {
                    IconButton(onClick = { viewModel.loadData() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                    IconButton(onClick = { viewModel.showSettings() }) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            when {
                uiState.isLoading -> {
                    CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center)
                    )
                }
                uiState.requirements.isEmpty() -> {
                    EmptyPlanningState(
                        modifier = Modifier.align(Alignment.Center)
                    )
                }
                else -> {
                    MonthlyPlanningContent(
                        requirements = uiState.requirements,
                        totalRequired = uiState.totalRequired,
                        displayCurrency = uiState.displayCurrency,
                        paymentDay = uiState.paymentDay,
                        onGoalClick = { goalId ->
                            navController.navigate(Screen.GoalDetail.createRoute(goalId))
                        }
                    )
                }
            }
        }

        // Settings dialog
        if (uiState.showSettingsDialog) {
            PaymentDaySettingsDialog(
                currentDay = uiState.paymentDay,
                onDismiss = { viewModel.dismissSettings() },
                onConfirm = { day -> viewModel.updatePaymentDay(day) }
            )
        }
    }
}

@Composable
private fun MonthlyPlanningContent(
    requirements: List<MonthlyRequirement>,
    totalRequired: Double,
    displayCurrency: String,
    paymentDay: Int,
    onGoalClick: (String) -> Unit
) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Summary card
        item {
            TotalRequirementCard(
                totalRequired = totalRequired,
                displayCurrency = displayCurrency,
                paymentDay = paymentDay,
                activeCount = requirements.count { it.status != RequirementStatus.COMPLETED },
                completedCount = requirements.count { it.status == RequirementStatus.COMPLETED }
            )
        }

        // Status summary
        item {
            StatusSummaryRow(requirements)
        }

        // Requirement cards
        items(
            items = requirements,
            key = { it.id }
        ) { requirement ->
            RequirementCard(
                requirement = requirement,
                onClick = { onGoalClick(requirement.goalId) }
            )
        }
    }
}

@Composable
private fun TotalRequirementCard(
    totalRequired: Double,
    displayCurrency: String,
    paymentDay: Int,
    activeCount: Int,
    completedCount: Int
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.CalendarMonth,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                    modifier = Modifier.size(24.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Monthly Total",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "$displayCurrency ${String.format("%,.2f", totalRequired)}",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
            Spacer(modifier = Modifier.height(8.dp))
            Row {
                Text(
                    text = "Payment day: ${paymentDay.toOrdinal()} of each month",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                )
            }
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "$activeCount active goals, $completedCount completed",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
            )
        }
    }
}

@Composable
private fun StatusSummaryRow(requirements: List<MonthlyRequirement>) {
    val criticalCount = requirements.count { it.status == RequirementStatus.CRITICAL }
    val attentionCount = requirements.count { it.status == RequirementStatus.ATTENTION }
    val onTrackCount = requirements.count { it.status == RequirementStatus.ON_TRACK }
    val completedCount = requirements.count { it.status == RequirementStatus.COMPLETED }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceEvenly
    ) {
        if (criticalCount > 0) {
            StatusChip(
                count = criticalCount,
                label = "Critical",
                color = AccessibleRed,
                icon = Icons.Default.Error
            )
        }
        if (attentionCount > 0) {
            StatusChip(
                count = attentionCount,
                label = "Attention",
                color = AccessibleYellow,
                icon = Icons.Default.Warning
            )
        }
        if (onTrackCount > 0) {
            StatusChip(
                count = onTrackCount,
                label = "On Track",
                color = AccessibleGreen,
                icon = Icons.Default.Flag
            )
        }
        if (completedCount > 0) {
            StatusChip(
                count = completedCount,
                label = "Done",
                color = MaterialTheme.colorScheme.primary,
                icon = Icons.Default.CheckCircle
            )
        }
    }
}

@Composable
private fun StatusChip(
    count: Int,
    label: String,
    color: Color,
    icon: ImageVector
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = color.copy(alpha = 0.15f)
        )
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(16.dp)
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = "$count $label",
                style = MaterialTheme.typography.labelMedium,
                color = color
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RequirementCard(
    requirement: MonthlyRequirement,
    onClick: () -> Unit
) {
    val statusColor = when (requirement.status) {
        RequirementStatus.COMPLETED -> AccessibleGreen
        RequirementStatus.ON_TRACK -> AccessibleGreen
        RequirementStatus.ATTENTION -> AccessibleYellow
        RequirementStatus.CRITICAL -> AccessibleRed
    }

    val statusIcon = when (requirement.status) {
        RequirementStatus.COMPLETED -> Icons.Default.CheckCircle
        RequirementStatus.ON_TRACK -> Icons.Default.Flag
        RequirementStatus.ATTENTION -> Icons.Default.Warning
        RequirementStatus.CRITICAL -> Icons.Default.Error
    }

    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = requirement.goalName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = requirement.timeRemainingDescription,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = statusIcon,
                        contentDescription = requirement.status.displayName,
                        tint = statusColor,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = requirement.status.displayName,
                        style = MaterialTheme.typography.labelSmall,
                        color = statusColor
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Progress bar
            LinearProgressIndicator(
                progress = { requirement.progress.toFloat() },
                modifier = Modifier.fillMaxWidth(),
                color = statusColor
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Amount details
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column {
                    Text(
                        text = "Monthly Required",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = requirement.formattedRequiredMonthly(),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = if (requirement.status == RequirementStatus.CRITICAL) statusColor else MaterialTheme.colorScheme.onSurface
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = "Remaining",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = requirement.formattedRemainingAmount(),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Medium
                    )
                }
            }

            Spacer(modifier = Modifier.height(4.dp))

            // Progress percentage
            Text(
                text = "${(requirement.progress * 100).toInt()}% complete",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun EmptyPlanningState(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = Icons.Default.CalendarMonth,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "No Active Goals",
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Create goals to see your monthly savings requirements",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun PaymentDaySettingsDialog(
    currentDay: Int,
    onDismiss: () -> Unit,
    onConfirm: (Int) -> Unit
) {
    var sliderValue by remember { mutableFloatStateOf(currentDay.toFloat()) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Payment Day") },
        text = {
            Column {
                Text(
                    text = "Set the day of each month when you make your savings deposits.",
                    style = MaterialTheme.typography.bodyMedium
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "Day: ${sliderValue.roundToInt().toOrdinal()}",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                Slider(
                    value = sliderValue,
                    onValueChange = { sliderValue = it },
                    valueRange = 1f..28f,
                    steps = 26
                )
                Text(
                    text = "Days 29-31 are not available to ensure consistency across all months.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(sliderValue.roundToInt()) }) {
                Text("Save")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

/**
 * Convert an integer to its ordinal string (1st, 2nd, 3rd, etc.)
 */
private fun Int.toOrdinal(): String {
    val suffixes = arrayOf("th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th")
    return when {
        this % 100 in 11..13 -> "${this}th"
        else -> "$this${suffixes[this % 10]}"
    }
}
