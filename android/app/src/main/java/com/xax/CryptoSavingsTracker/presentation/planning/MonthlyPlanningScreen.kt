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
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.model.PlanningMode
import com.xax.CryptoSavingsTracker.domain.model.RequirementStatus
import com.xax.CryptoSavingsTracker.presentation.navigation.Screen
import com.xax.CryptoSavingsTracker.presentation.planning.components.FixedBudgetIntroCard
import com.xax.CryptoSavingsTracker.presentation.planning.components.PlanningModeSegmentedControl
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleGreen
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleRed
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleYellow
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

private val planningDisplayCurrencies = listOf(
    "USD",
    "EUR",
    "GBP",
    "JPY",
    "CHF",
    "CAD",
    "AUD",
    "CNY",
    "INR",
    "KRW"
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MonthlyPlanningScreen(
    navController: NavController,
    viewModel: MonthlyPlanningViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var customDialogGoalId by remember { mutableStateOf<String?>(null) }

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
                    IconButton(onClick = { navController.navigate(Screen.Execution.route) }) {
                        val hasActiveExecution = uiState.activeExecutionMonthLabel != null
                        Icon(
                            Icons.Default.Flag,
                            contentDescription = if (hasActiveExecution) "Execution (Active)" else "Execution",
                            tint = if (hasActiveExecution) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            }
                        )
                    }
                    IconButton(onClick = { navController.navigate(Screen.PlanHistory.route) }) {
                        Icon(Icons.Default.CalendarMonth, contentDescription = "History")
                    }
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
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Fixed Budget Intro Card (show only when in Per Goal mode and not seen yet)
            if (!uiState.hasSeenFixedBudgetIntro && uiState.planningMode == PlanningMode.PER_GOAL) {
                FixedBudgetIntroCard(
                    onLearnMore = { viewModel.showSettings() },
                    onTryIt = { viewModel.tryFixedBudgetMode() },
                    onDismiss = { viewModel.dismissFixedBudgetIntro() },
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }

            // Planning Mode Segmented Control
            PlanningModeSegmentedControl(
                selectedMode = uiState.planningMode,
                onModeSelected = { mode -> viewModel.setPlanningMode(mode) },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
            )

            // Content based on planning mode
            when (uiState.planningMode) {
                PlanningMode.FIXED_BUDGET -> {
                    FixedBudgetPlanningScreen(
                        navController = navController,
                        modifier = Modifier.fillMaxSize()
                    )
                }
                PlanningMode.PER_GOAL -> {
                    Box(modifier = Modifier.fillMaxSize()) {
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
                                    flexAdjustment = uiState.flexAdjustment,
                                    totalRequired = uiState.totalRequired,
                                    baseTotalRequired = uiState.baseTotalRequired,
                                    displayCurrency = uiState.displayCurrency,
                                    paymentDay = uiState.paymentDay,
                                    activeExecutionMonthLabel = uiState.activeExecutionMonthLabel,
                                    activeExecutionStartedAtMillis = uiState.activeExecutionStartedAtMillis,
                                    onViewExecution = { navController.navigate(Screen.Execution.route) },
                                    onGoalClick = { goalId ->
                                        navController.navigate(Screen.GoalDetail.createRoute(goalId))
                                    },
                                    onFlexAdjustmentChanged = viewModel::updateFlexAdjustment,
                                    onToggleProtected = viewModel::toggleProtected,
                                    onToggleSkipped = viewModel::toggleSkipped,
                                    onCustomAmountClick = { goalId -> customDialogGoalId = goalId }
                                )
                            }
                        }
                    }
                }
            }
        }

        // Settings dialog
        if (uiState.showSettingsDialog) {
            PlanningSettingsDialog(
                currentDay = uiState.paymentDay,
                currentCurrency = uiState.displayCurrency,
                availableCurrencies = planningDisplayCurrencies,
                onDismiss = { viewModel.dismissSettings() },
                onConfirm = { day, currency -> viewModel.updatePlanningSettings(day, currency) }
            )
        }

        val dialogGoalId = customDialogGoalId
        if (dialogGoalId != null) {
            val row = uiState.requirements.firstOrNull { it.goalId == dialogGoalId }
            if (row != null) {
                CustomAmountDialog(
                    goalName = row.requirement.goalName,
                    currency = row.requirement.currency,
                    currentAmount = row.customAmount,
                    onDismiss = { customDialogGoalId = null },
                    onClear = {
                        viewModel.setCustomAmount(dialogGoalId, null)
                        customDialogGoalId = null
                    },
                    onConfirm = { amount ->
                        viewModel.setCustomAmount(dialogGoalId, amount)
                        customDialogGoalId = null
                    }
                )
            } else {
                customDialogGoalId = null
            }
        }
    }
}

@Composable
private fun MonthlyPlanningContent(
    requirements: List<MonthlyRequirementRow>,
    flexAdjustment: Double,
    totalRequired: Double,
    baseTotalRequired: Double,
    displayCurrency: String,
    paymentDay: Int,
    activeExecutionMonthLabel: String?,
    activeExecutionStartedAtMillis: Long?,
    onViewExecution: () -> Unit,
    onGoalClick: (String) -> Unit,
    onFlexAdjustmentChanged: (Double) -> Unit,
    onToggleProtected: (String) -> Unit,
    onToggleSkipped: (String) -> Unit,
    onCustomAmountClick: (String) -> Unit
) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (activeExecutionMonthLabel != null && activeExecutionStartedAtMillis != null) {
            item {
                TrackingModeBanner(
                    monthLabel = activeExecutionMonthLabel,
                    startedAtMillis = activeExecutionStartedAtMillis,
                    onViewExecution = onViewExecution
                )
            }
        }

        // Summary card
        item {
            TotalRequirementCard(
                totalRequired = totalRequired,
                baseTotalRequired = baseTotalRequired,
                displayCurrency = displayCurrency,
                paymentDay = paymentDay,
                flexAdjustment = flexAdjustment,
                onFlexAdjustmentChanged = onFlexAdjustmentChanged,
                activeCount = requirements.count { it.requirement.status != RequirementStatus.COMPLETED },
                completedCount = requirements.count { it.requirement.status == RequirementStatus.COMPLETED }
            )
        }

        // Status summary
        item {
            StatusSummaryRow(requirements)
        }

        // Requirement cards
        items(
            items = requirements,
            key = { it.goalId }
        ) { row ->
            RequirementCard(
                row = row,
                onClick = { onGoalClick(row.goalId) },
                onToggleProtected = { onToggleProtected(row.goalId) },
                onToggleSkipped = { onToggleSkipped(row.goalId) },
                onCustomAmountClick = { onCustomAmountClick(row.goalId) }
            )
        }
    }
}

@Composable
private fun TrackingModeBanner(
    monthLabel: String,
    startedAtMillis: Long,
    onViewExecution: () -> Unit
) {
    val startedAtText = remember(startedAtMillis) {
        DateTimeFormatter.ofPattern("MMM d, yyyy 'at' h:mm a")
            .withZone(ZoneId.systemDefault())
            .format(Instant.ofEpochMilli(startedAtMillis))
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Tracking Mode",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Recording contributions for $monthLabel",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f)
                )
                Text(
                    text = "Started: $startedAtText",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f)
                )
            }
            Spacer(modifier = Modifier.width(12.dp))
            TextButton(onClick = onViewExecution) {
                Text("View")
            }
        }
    }
}

@Composable
private fun TotalRequirementCard(
    totalRequired: Double,
    baseTotalRequired: Double,
    displayCurrency: String,
    paymentDay: Int,
    flexAdjustment: Double,
    onFlexAdjustmentChanged: (Double) -> Unit,
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
            if (kotlin.math.abs(totalRequired - baseTotalRequired) > 0.01) {
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = "Base: $displayCurrency ${String.format("%,.2f", baseTotalRequired)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                )
            }
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

            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "Flex: ${(flexAdjustment * 100).roundToInt()}%",
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
            Slider(
                value = flexAdjustment.toFloat(),
                onValueChange = { onFlexAdjustmentChanged(it.toDouble()) },
                valueRange = 0f..1.5f
            )
        }
    }
}

@Composable
private fun StatusSummaryRow(requirements: List<MonthlyRequirementRow>) {
    val criticalCount = requirements.count { it.requirement.status == RequirementStatus.CRITICAL }
    val attentionCount = requirements.count { it.requirement.status == RequirementStatus.ATTENTION }
    val onTrackCount = requirements.count { it.requirement.status == RequirementStatus.ON_TRACK }
    val completedCount = requirements.count { it.requirement.status == RequirementStatus.COMPLETED }

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
    row: MonthlyRequirementRow,
    onClick: () -> Unit,
    onToggleProtected: () -> Unit,
    onToggleSkipped: () -> Unit,
    onCustomAmountClick: () -> Unit
) {
    val requirement = row.requirement
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
                        text = row.formattedAdjustedRequiredMonthly(),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = if (requirement.status == RequirementStatus.CRITICAL) statusColor else MaterialTheme.colorScheme.onSurface
                    )
                    val baseChanged = kotlin.math.abs(row.adjustedRequiredMonthly - requirement.requiredMonthly) > 0.01
                    if (baseChanged) {
                        Text(
                            text = "Base: ${requirement.formattedRequiredMonthly()}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
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

            Spacer(modifier = Modifier.height(12.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(onClick = onToggleProtected) {
                        Icon(
                            imageVector = Icons.Default.Flag,
                            contentDescription = null,
                            tint = if (row.isProtected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(if (row.isProtected) "Protected" else "Protect")
                    }
                    TextButton(onClick = onToggleSkipped) {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = null,
                            tint = if (row.isSkipped) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(if (row.isSkipped) "Skipped" else "Skip")
                    }
                }
                TextButton(onClick = onCustomAmountClick) {
                    Icon(
                        imageVector = Icons.Default.Settings,
                        contentDescription = null,
                        tint = if (row.customAmount != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(if (row.customAmount != null) "Custom" else "Set")
                }
            }
        }
    }
}

@Composable
private fun CustomAmountDialog(
    goalName: String,
    currency: String,
    currentAmount: Double?,
    onDismiss: () -> Unit,
    onClear: () -> Unit,
    onConfirm: (Double) -> Unit
) {
    var value by remember {
        mutableStateOf(currentAmount?.let { String.format("%.2f", it) } ?: "")
    }
    val parsed = value.toDoubleOrNull()
    val error = if (value.isNotEmpty() && (parsed == null || parsed < 0.0)) "Enter a valid amount" else null

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Custom Amount") },
        text = {
            Column {
                Text(
                    text = "Set a custom monthly amount for \"$goalName\".",
                    style = MaterialTheme.typography.bodyMedium
                )
                Spacer(modifier = Modifier.height(12.dp))
                OutlinedTextField(
                    value = value,
                    onValueChange = { newValue ->
                        val filtered = newValue.filter { it.isDigit() || it == '.' }
                        if (filtered.count { it == '.' } <= 1) value = filtered
                    },
                    label = { Text("Amount ($currency)") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    isError = error != null,
                    supportingText = error?.let { { Text(it) } },
                    singleLine = true
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(parsed ?: 0.0) },
                enabled = parsed != null && parsed >= 0.0 && error == null
            ) {
                Text("Save")
            }
        },
        dismissButton = {
            Row {
                if (currentAmount != null) {
                    TextButton(onClick = onClear) {
                        Text("Clear")
                    }
                }
                TextButton(onClick = onDismiss) {
                    Text("Cancel")
                }
            }
        }
    )
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PlanningSettingsDialog(
    currentDay: Int,
    currentCurrency: String,
    availableCurrencies: List<String>,
    onDismiss: () -> Unit,
    onConfirm: (Int, String) -> Unit
) {
    var sliderValue by remember { mutableFloatStateOf(currentDay.toFloat()) }
    var expanded by remember { mutableStateOf(false) }
    var selectedCurrency by remember { mutableStateOf(currentCurrency) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Planning Settings") },
        text = {
            Column {
                Text(
                    text = "Choose the display currency and payment schedule for your monthly requirements.",
                    style = MaterialTheme.typography.bodyMedium
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "Display Currency",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.height(8.dp))
                ExposedDropdownMenuBox(
                    expanded = expanded,
                    onExpandedChange = { expanded = it }
                ) {
                    OutlinedTextField(
                        value = selectedCurrency,
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Currency") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .menuAnchor(MenuAnchorType.PrimaryNotEditable),
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                        singleLine = true
                    )
                    ExposedDropdownMenu(
                        expanded = expanded,
                        onDismissRequest = { expanded = false }
                    ) {
                        availableCurrencies.forEach { currency ->
                            DropdownMenuItem(
                                text = { Text(currency) },
                                onClick = {
                                    selectedCurrency = currency
                                    expanded = false
                                }
                            )
                        }
                    }
                }
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
            TextButton(onClick = { onConfirm(sliderValue.roundToInt(), selectedCurrency) }) {
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
