package com.xax.CryptoSavingsTracker.presentation.execution

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
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
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.MenuAnchorType
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.model.ScheduledGoalBlock
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionGoalProgress
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionSession
import com.xax.CryptoSavingsTracker.presentation.common.AmountFormatters
import com.xax.CryptoSavingsTracker.presentation.navigation.Screen
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.launch

private val executionDisplayCurrencies = listOf(
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
fun ExecutionScreen(
    navController: NavController,
    viewModel: ExecutionViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val coroutineScope = rememberCoroutineScope()

    var showAssetPicker by remember { mutableStateOf(false) }
    var selectedGoal by remember { mutableStateOf<ExecutionGoalProgress?>(null) }
    var assetOptions by remember { mutableStateOf<List<ExecutionAssetOption>>(emptyList()) }
    var isSuggesting by remember { mutableStateOf(false) }

    LaunchedEffect(uiState.error) {
        uiState.error?.let { error ->
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Monthly Execution") },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            if (uiState.session == null) {
                EmptyExecutionState(
                    canUndo = uiState.undoableRecordId != null,
                    isBusy = uiState.isBusy,
                    onStart = viewModel::startExecution,
                    onUndo = viewModel::undoLastCompletion
                )
            } else {
                ActiveExecutionContent(
                    session = uiState.session!!,
                    displayCurrency = uiState.displayCurrency,
                    remainingByGoalId = uiState.remainingByGoalId,
                    remainingCurrencyByGoalId = uiState.remainingCurrencyByGoalId,
                    totalRemainingDisplay = uiState.totalRemainingDisplay,
                    hasRateWarning = uiState.hasRateConversionWarning,
                    canUndoStart = uiState.canUndoStart,
                    isBusy = uiState.isBusy,
                    // Fixed Budget Mode context
                    isFixedBudgetMode = uiState.isFixedBudgetMode,
                    monthlyBudget = uiState.monthlyBudget,
                    budgetCurrency = uiState.budgetCurrency,
                    budgetProgress = uiState.budgetProgress,
                    currentScheduledGoal = uiState.currentScheduledGoal,
                    nextUpGoal = uiState.nextUpGoal,
                    onComplete = viewModel::completeExecution,
                    onUndoStart = viewModel::undoStartExecution,
                    onDisplayCurrencySelected = viewModel::updateDisplayCurrency,
                    onAddToCloseMonth = { goal ->
                        selectedGoal = goal
                        coroutineScope.launch {
                            assetOptions = viewModel.loadAssetOptions(goal.snapshot.goalId)
                            showAssetPicker = true
                        }
                    },
                    onAssetSelected = { asset ->
                        val goal = selectedGoal ?: return@ActiveExecutionContent
                        showAssetPicker = false
                        if (asset.isShared) {
                            navController.navigate(
                                Screen.AssetSharing.createRoute(
                                    assetId = asset.assetId,
                                    goalId = goal.snapshot.goalId,
                                    prefillCloseMonth = true
                                )
                            )
                        } else {
                            coroutineScope.launch {
                                isSuggesting = true
                                val suggestion = viewModel.suggestedContributionAmount(goal, asset.currency)
                                isSuggesting = false
                                navController.navigate(
                                    Screen.AddTransaction.createRoute(
                                        assetId = asset.assetId,
                                        prefillAmount = suggestion
                                    )
                                )
                            }
                        }
                    },
                    showAssetPicker = showAssetPicker,
                    assetOptions = assetOptions,
                    onDismissAssetPicker = { showAssetPicker = false }
                )
            }

            if (isSuggesting) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            }
        }
    }
}

@Composable
private fun EmptyExecutionState(
    canUndo: Boolean,
    isBusy: Boolean,
    onStart: () -> Unit,
    onUndo: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = Icons.Default.Refresh,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.primary
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "Not Started",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Start monthly execution to track your savings progress. A snapshot of your current plan will be saved.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 24.dp)
        )
        Spacer(modifier = Modifier.height(24.dp))
        Button(
            onClick = onStart,
            enabled = !isBusy
        ) {
            Icon(Icons.Default.PlayArrow, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Start Execution")
        }
        if (canUndo) {
            Spacer(modifier = Modifier.height(12.dp))
            Button(
                onClick = onUndo,
                enabled = !isBusy,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.secondaryContainer,
                    contentColor = MaterialTheme.colorScheme.onSecondaryContainer
                )
            ) {
                Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Undo Last Completion")
            }
        }
    }
}

@Composable
private fun ActiveExecutionContent(
    session: ExecutionSession,
    displayCurrency: String,
    remainingByGoalId: Map<String, Double>,
    remainingCurrencyByGoalId: Map<String, String>,
    totalRemainingDisplay: Double?,
    hasRateWarning: Boolean,
    canUndoStart: Boolean,
    isBusy: Boolean,
    // Fixed Budget Mode context
    isFixedBudgetMode: Boolean,
    monthlyBudget: Double,
    budgetCurrency: String,
    budgetProgress: Double,
    currentScheduledGoal: FixedBudgetGoalInfo?,
    nextUpGoal: FixedBudgetGoalInfo?,
    onComplete: () -> Unit,
    onUndoStart: () -> Unit,
    onDisplayCurrencySelected: (String) -> Unit,
    onAddToCloseMonth: (ExecutionGoalProgress) -> Unit,
    onAssetSelected: (ExecutionAssetOption) -> Unit,
    showAssetPicker: Boolean,
    assetOptions: List<ExecutionAssetOption>,
    onDismissAssetPicker: () -> Unit
) {
    var showCompletedSection by remember { mutableStateOf(true) }
    var currencyPickerExpanded by remember { mutableStateOf(false) }

    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Progress Header
        item {
            ProgressHeaderCard(
                session = session,
                displayCurrency = displayCurrency,
                totalRemainingDisplay = totalRemainingDisplay,
                hasRateWarning = hasRateWarning,
                onDisplayCurrencySelected = {
                    onDisplayCurrencySelected(it)
                    currencyPickerExpanded = false
                },
                currencyPickerExpanded = currencyPickerExpanded,
                onToggleCurrencyPicker = { currencyPickerExpanded = !currencyPickerExpanded }
            )
        }

        // Fixed Budget Mode Header (if enabled)
        if (isFixedBudgetMode && monthlyBudget > 0) {
            item {
                FixedBudgetExecutionHeader(
                    monthlyBudget = monthlyBudget,
                    budgetCurrency = budgetCurrency,
                    budgetProgress = budgetProgress,
                    currentGoal = currentScheduledGoal,
                    nextUpGoal = nextUpGoal
                )
            }
        }

        // Undo Banner (if within 24h window)
        if (canUndoStart) {
            item {
                UndoBanner(
                    startedAtMillis = session.record.startedAtMillis,
                    onUndo = onUndoStart,
                    isBusy = isBusy
                )
            }
        }

        // Active Goals Section
        item {
            ActiveGoalsSection(
                goals = session.activeGoals,
                remainingByGoalId = remainingByGoalId,
                remainingCurrencyByGoalId = remainingCurrencyByGoalId,
                onAddToCloseMonth = onAddToCloseMonth
            )
        }

        // Completed Goals Section (collapsible)
        if (session.completedGoals.isNotEmpty()) {
            item {
                CompletedGoalsSection(
                    goals = session.completedGoals,
                    isExpanded = showCompletedSection,
                    onToggle = { showCompletedSection = !showCompletedSection },
                    remainingByGoalId = remainingByGoalId,
                    remainingCurrencyByGoalId = remainingCurrencyByGoalId
                )
            }
        }

        // Action Buttons
        item {
            ActionButtonsSection(
                isBusy = isBusy,
                onComplete = onComplete
            )
        }
    }

    if (showAssetPicker) {
        AssetPickerDialog(
            options = assetOptions,
            onDismiss = onDismissAssetPicker,
            onAssetSelected = onAssetSelected
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProgressHeaderCard(
    session: ExecutionSession,
    displayCurrency: String,
    totalRemainingDisplay: Double?,
    hasRateWarning: Boolean,
    currencyPickerExpanded: Boolean,
    onToggleCurrencyPicker: () -> Unit,
    onDisplayCurrencySelected: (String) -> Unit
) {
    val monthLabel = session.record.monthLabel
    val formattedMonth = remember(monthLabel) {
        try {
            val ym = YearMonth.parse(monthLabel)
            ym.format(DateTimeFormatter.ofPattern("MMMM yyyy"))
        } catch (e: Exception) {
            monthLabel
        }
    }

    val progressPercent = session.overallProgress.coerceIn(0.0, 100.0)
    val progressColor = if (progressPercent >= 100) Color(0xFF4CAF50) else MaterialTheme.colorScheme.primary

    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Title row with status and month
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.Refresh,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Active This Month",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                }
                Text(
                    text = formattedMonth,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Display Currency",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                ExposedDropdownMenuBox(
                    expanded = currencyPickerExpanded,
                    onExpandedChange = { onToggleCurrencyPicker() }
                ) {
                    OutlinedTextField(
                        value = displayCurrency,
                        onValueChange = {},
                        readOnly = true,
                        modifier = Modifier
                            .menuAnchor(MenuAnchorType.PrimaryNotEditable),
                        label = { Text("Currency") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = currencyPickerExpanded) },
                        singleLine = true
                    )
                    ExposedDropdownMenu(
                        expanded = currencyPickerExpanded,
                        onDismissRequest = onToggleCurrencyPicker
                    ) {
                        executionDisplayCurrencies.forEach { currency ->
                            DropdownMenuItem(
                                text = { Text(currency) },
                                onClick = { onDisplayCurrencySelected(currency) }
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Progress bar
            LinearProgressIndicator(
                progress = { (progressPercent / 100.0).toFloat().coerceIn(0f, 1f) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp),
                color = progressColor,
                trackColor = MaterialTheme.colorScheme.surfaceVariant
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Stats row
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                // Percentage complete
                Column(horizontalAlignment = Alignment.Start) {
                    Text(
                        text = "${progressPercent.toInt()}%",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        color = if (progressPercent >= 100) progressColor else MaterialTheme.colorScheme.onSurface
                    )
                    Text(
                        text = "complete",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                // Goals funded
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = "${session.fulfilledCount}/${session.goals.size}",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "goals funded",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                // Total planned
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = formatCurrency(session.totalPlanned),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "planned",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            if (totalRemainingDisplay != null) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Remaining this month: ${formatCurrency(totalRemainingDisplay, displayCurrency)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else if (hasRateWarning) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Remaining this month: unavailable (rate missing)",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun UndoBanner(
    startedAtMillis: Long?,
    onUndo: () -> Unit,
    isBusy: Boolean
) {
    val timeRemaining = remember(startedAtMillis) {
        if (startedAtMillis == null) return@remember "—"
        val undoDeadline = startedAtMillis + TimeUnit.HOURS.toMillis(24)
        val remainingMillis = undoDeadline - System.currentTimeMillis()
        if (remainingMillis <= 0) return@remember "Expired"
        val hours = TimeUnit.MILLISECONDS.toHours(remainingMillis)
        val minutes = TimeUnit.MILLISECONDS.toMinutes(remainingMillis) % 60
        if (hours > 0) "${hours}h ${minutes}m" else "${minutes}m"
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.Undo,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        text = "Execution started",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = "Undo expires in $timeRemaining",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Button(
                onClick = onUndo,
                enabled = !isBusy
            ) {
                Text("Undo")
            }
        }
    }
}

@Composable
private fun ActiveGoalsSection(
    goals: List<ExecutionGoalProgress>,
    remainingByGoalId: Map<String, Double>,
    remainingCurrencyByGoalId: Map<String, String>,
    onAddToCloseMonth: (ExecutionGoalProgress) -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Active Goals (${goals.size})",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(12.dp))

            if (goals.isEmpty()) {
                Text(
                    text = "All goals funded! 🎉",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 16.dp),
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    goals.forEach { goal ->
                        GoalProgressCard(
                            goal = goal,
                            isFulfilled = false,
                            remainingDisplay = remainingByGoalId[goal.snapshot.goalId],
                            remainingCurrency = remainingCurrencyByGoalId[goal.snapshot.goalId],
                            onAddToCloseMonth = onAddToCloseMonth
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CompletedGoalsSection(
    goals: List<ExecutionGoalProgress>,
    isExpanded: Boolean,
    onToggle: () -> Unit,
    remainingByGoalId: Map<String, Double>,
    remainingCurrencyByGoalId: Map<String, String>
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onToggle() },
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.CheckCircle,
                        contentDescription = null,
                        tint = Color(0xFF4CAF50)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Completed This Month (${goals.size})",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                Icon(
                    imageVector = if (isExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                    contentDescription = if (isExpanded) "Collapse" else "Expand",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            AnimatedVisibility(visible = isExpanded) {
                Column(
                    modifier = Modifier.padding(top = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    goals.forEach { goal ->
                        GoalProgressCard(
                            goal = goal,
                            isFulfilled = true,
                            remainingDisplay = remainingByGoalId[goal.snapshot.goalId],
                            remainingCurrency = remainingCurrencyByGoalId[goal.snapshot.goalId],
                            onAddToCloseMonth = null
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun GoalProgressCard(
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
                modifier = Modifier.fillMaxWidth(),
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

@Composable
private fun ActionButtonsSection(
    isBusy: Boolean,
    onComplete: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Button(
            onClick = onComplete,
            enabled = !isBusy,
            colors = ButtonDefaults.buttonColors(
                containerColor = Color(0xFF4CAF50)
            ),
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Default.CheckCircle, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Finish This Month")
        }
    }
}

private fun formatCurrency(amount: Double, currency: String = "USD"): String {
    return "$currency ${String.format("%,.2f", amount)}"
}

@Composable
private fun AssetPickerDialog(
    options: List<ExecutionAssetOption>,
    onDismiss: () -> Unit,
    onAssetSelected: (ExecutionAssetOption) -> Unit
) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Select Asset") },
        text = {
            if (options.isEmpty()) {
                Text(
                    text = "No assets available.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    options.forEach { asset ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onAssetSelected(asset) }
                                .padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(asset.displayName, fontWeight = FontWeight.Medium)
                                if (asset.isShared) {
                                    Text(
                                        text = "Shared asset",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                            Text(asset.currency, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

/**
 * Fixed Budget Mode header showing budget progress and current scheduled goal.
 */
@Composable
private fun FixedBudgetExecutionHeader(
    monthlyBudget: Double,
    budgetCurrency: String,
    budgetProgress: Double,
    currentGoal: FixedBudgetGoalInfo?,
    nextUpGoal: FixedBudgetGoalInfo?
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Header with mode indicator
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.PlayArrow,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Fixed Budget Mode",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
                Text(
                    text = formatCurrency(monthlyBudget, budgetCurrency),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Budget progress bar
            Column {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "Budget Progress",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = "${budgetProgress.toInt()}%",
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.SemiBold,
                        color = if (budgetProgress >= 100) Color(0xFF4CAF50) else MaterialTheme.colorScheme.onSurface
                    )
                }
                Spacer(modifier = Modifier.height(4.dp))
                LinearProgressIndicator(
                    progress = { (budgetProgress / 100.0).toFloat().coerceIn(0f, 1f) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(6.dp),
                    color = if (budgetProgress >= 100) Color(0xFF4CAF50) else MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.surfaceVariant
                )
            }

            // Current goal being funded
            if (currentGoal != null) {
                Spacer(modifier = Modifier.height(12.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Currently Funding",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(modifier = Modifier.height(2.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (currentGoal.emoji != null) {
                                Text(
                                    text = currentGoal.emoji,
                                    style = MaterialTheme.typography.bodyMedium
                                )
                                Spacer(modifier = Modifier.width(4.dp))
                            }
                            Text(
                                text = currentGoal.goalName,
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.Medium
                            )
                        }
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text(
                            text = "${currentGoal.progress.toInt()}%",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        if (currentGoal.paymentsRemaining > 0) {
                            Text(
                                text = "${currentGoal.paymentsRemaining} payment${if (currentGoal.paymentsRemaining > 1) "s" else ""} left",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }

            // Next-up goal preview
            if (nextUpGoal != null && nextUpGoal.goalId != currentGoal?.goalId) {
                Spacer(modifier = Modifier.height(8.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "→",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Next: ",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (nextUpGoal.emoji != null) {
                        Text(
                            text = nextUpGoal.emoji,
                            style = MaterialTheme.typography.bodySmall
                        )
                        Spacer(modifier = Modifier.width(2.dp))
                    }
                    Text(
                        text = nextUpGoal.goalName,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}
