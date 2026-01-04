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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionGoalProgress
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionSession
import com.xax.CryptoSavingsTracker.presentation.common.AmountFormatters
import com.xax.CryptoSavingsTracker.presentation.execution.components.EmptyExecutionState
import com.xax.CryptoSavingsTracker.presentation.execution.components.GoalProgressCard
import com.xax.CryptoSavingsTracker.presentation.execution.components.ProgressHeaderCard
import com.xax.CryptoSavingsTracker.presentation.execution.components.UndoBanner
import com.xax.CryptoSavingsTracker.presentation.execution.components.executionDisplayCurrencies
import com.xax.CryptoSavingsTracker.presentation.navigation.Screen
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.launch

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
                    lastRateUpdateMillis = uiState.lastRateUpdateMillis,
                    currentFocusGoal = uiState.currentFocusGoal,
                    canUndoStart = uiState.canUndoStart,
                    isBusy = uiState.isBusy,
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
private fun ActiveExecutionContent(
    session: ExecutionSession,
    displayCurrency: String,
    remainingByGoalId: Map<String, Double>,
    remainingCurrencyByGoalId: Map<String, String>,
    totalRemainingDisplay: Double?,
    hasRateWarning: Boolean,
    lastRateUpdateMillis: Long?,
    currentFocusGoal: ExecutionFocusGoal?,
    canUndoStart: Boolean,
    isBusy: Boolean,
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
                lastRateUpdateMillis = lastRateUpdateMillis,
                currentFocusGoal = currentFocusGoal,
                onDisplayCurrencySelected = {
                    onDisplayCurrencySelected(it)
                    currencyPickerExpanded = false
                },
                currencyPickerExpanded = currencyPickerExpanded,
                onToggleCurrencyPicker = { currencyPickerExpanded = !currencyPickerExpanded }
            )
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
