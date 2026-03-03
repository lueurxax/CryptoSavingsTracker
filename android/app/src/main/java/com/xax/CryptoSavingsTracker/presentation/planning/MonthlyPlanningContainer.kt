package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.model.UiCycleState
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionActionCopyCatalog
import com.xax.CryptoSavingsTracker.domain.usecase.execution.MonthlyCycleAction
import com.xax.CryptoSavingsTracker.domain.usecase.execution.MonthlyCycleActionGate
import com.xax.CryptoSavingsTracker.presentation.execution.ExecutionViewModel
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale
import kotlinx.coroutines.launch

/**
 * Canonical planning container.
 * - Planning remains the primary screen for monthly-cycle actions.
 * - Execution is opened as a detail route.
 */
@Composable
fun MonthlyPlanningContainer(
    navController: NavController,
    planningViewModel: MonthlyPlanningViewModel = hiltViewModel(),
    executionViewModel: ExecutionViewModel = hiltViewModel(),
    cycleStateViewModel: MonthlyCycleStateViewModel = hiltViewModel()
) {
    val cycleState by cycleStateViewModel.state.collectAsState()
    val executionState by executionViewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    LaunchedEffect(executionState.error) {
        executionState.error?.let { message ->
            snackbarHostState.showSnackbar(message)
            executionViewModel.clearError()
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        MonthlyPlanningScreen(
            navController = navController,
            viewModel = planningViewModel
        )

        MonthlyCycleActionStrip(
            cycleState = cycleState,
            isBusy = executionState.isBusy,
            onStartTracking = { month ->
                val decision = MonthlyCycleActionGate.evaluate(cycleState, MonthlyCycleAction.START_TRACKING)
                if (decision.allowed) {
                    executionViewModel.startExecution(month)
                } else {
                    resolveBlockedActionMessage(decision, cycleState)?.let { message ->
                        scope.launch { snackbarHostState.showSnackbar(message) }
                    }
                }
            },
            onFinishMonth = {
                val decision = MonthlyCycleActionGate.evaluate(cycleState, MonthlyCycleAction.FINISH_MONTH)
                if (decision.allowed) {
                    executionViewModel.completeExecution()
                } else {
                    resolveBlockedActionMessage(decision, cycleState)?.let { message ->
                        scope.launch { snackbarHostState.showSnackbar(message) }
                    }
                }
            },
            onUndoStart = {
                val decision = MonthlyCycleActionGate.evaluate(cycleState, MonthlyCycleAction.UNDO_START)
                if (decision.allowed) {
                    executionViewModel.undoStartExecution()
                } else {
                    resolveBlockedActionMessage(decision, cycleState)?.let { message ->
                        scope.launch { snackbarHostState.showSnackbar(message) }
                    }
                }
            },
            onUndoFinish = {
                val decision = MonthlyCycleActionGate.evaluate(cycleState, MonthlyCycleAction.UNDO_COMPLETION)
                if (decision.allowed) {
                    executionViewModel.undoLastCompletion()
                } else {
                    resolveBlockedActionMessage(decision, cycleState)?.let { message ->
                        scope.launch { snackbarHostState.showSnackbar(message) }
                    }
                }
            },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(12.dp)
        )

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 100.dp, start = 12.dp, end = 12.dp)
        )
    }
}

private fun resolveBlockedActionMessage(
    decision: com.xax.CryptoSavingsTracker.domain.usecase.execution.MonthlyCycleActionDecision,
    state: UiCycleState
): String? {
    val formatter = DateTimeFormatter.ofPattern("MMMM yyyy", Locale.getDefault())
    val monthDisplay = formatMonthLabel(stateMonthLabel(state), formatter)
    return when (decision.blockedCopyKey) {
        com.xax.CryptoSavingsTracker.domain.usecase.execution.MonthlyCycleBlockedCopyKey.START_BLOCKED_ALREADY_EXECUTING ->
            ExecutionActionCopyCatalog.startBlockedAlreadyExecuting(monthDisplay)
        com.xax.CryptoSavingsTracker.domain.usecase.execution.MonthlyCycleBlockedCopyKey.START_BLOCKED_CLOSED_MONTH ->
            ExecutionActionCopyCatalog.startBlockedClosedMonth()
        com.xax.CryptoSavingsTracker.domain.usecase.execution.MonthlyCycleBlockedCopyKey.FINISH_BLOCKED_NO_EXECUTING ->
            ExecutionActionCopyCatalog.finishBlockedNoExecuting()
        com.xax.CryptoSavingsTracker.domain.usecase.execution.MonthlyCycleBlockedCopyKey.UNDO_START_EXPIRED ->
            ExecutionActionCopyCatalog.undoStartExpired(monthDisplay)
        com.xax.CryptoSavingsTracker.domain.usecase.execution.MonthlyCycleBlockedCopyKey.UNDO_COMPLETION_EXPIRED ->
            ExecutionActionCopyCatalog.undoCompletionExpired(monthDisplay)
        com.xax.CryptoSavingsTracker.domain.usecase.execution.MonthlyCycleBlockedCopyKey.RECORD_CONFLICT ->
            ExecutionActionCopyCatalog.recordConflict()
        null -> decision.blockedMessage
    }
}

private fun stateMonthLabel(state: UiCycleState): String {
    return when (state) {
        is UiCycleState.Planning -> state.monthLabel
        is UiCycleState.Executing -> state.monthLabel
        is UiCycleState.Closed -> state.monthLabel
        is UiCycleState.Conflict -> state.monthLabel ?: ""
    }
}

@Composable
private fun MonthlyCycleActionStrip(
    cycleState: UiCycleState,
    isBusy: Boolean,
    onStartTracking: (String) -> Unit,
    onFinishMonth: () -> Unit,
    onUndoStart: () -> Unit,
    onUndoFinish: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        BoxWithConstraints(modifier = Modifier.padding(12.dp)) {
            val monthFormatter = DateTimeFormatter.ofPattern("MMMM yyyy", Locale.getDefault())
            val compactFormatter = DateTimeFormatter.ofPattern("MMM yyyy", Locale.getDefault())
            val fallbackMode = when {
                maxWidth >= 360.dp -> 0
                maxWidth >= 300.dp -> 1
                else -> 2
            }

            when (cycleState) {
                is UiCycleState.Planning -> {
                    val monthFull = formatMonthLabel(cycleState.monthLabel, monthFormatter)
                    val monthCompact = formatMonthLabel(cycleState.monthLabel, compactFormatter)
                    val label = when (fallbackMode) {
                        0 -> "Start Tracking $monthFull"
                        1 -> "Start $monthFull"
                        else -> "Start $monthCompact"
                    }
                    val accessibility = "Start Tracking $monthFull"
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        StateBadge(
                            icon = Icons.Default.Description,
                            title = "Planning",
                            subtitle = "Planning for $monthFull"
                        )
                        FilledTonalButton(
                            onClick = { onStartTracking(cycleState.monthLabel) },
                            enabled = !isBusy,
                            modifier = Modifier
                                .fillMaxWidth()
                                .semantics { contentDescription = accessibility }
                        ) {
                            Text(label)
                        }
                    }
                }

                is UiCycleState.Executing -> {
                    val monthFull = formatMonthLabel(cycleState.monthLabel, monthFormatter)
                    val undoStartReason = ExecutionActionCopyCatalog.undoStartExpired(monthFull)
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        StateBadge(
                            icon = Icons.AutoMirrored.Filled.ShowChart,
                            title = "Tracking",
                            subtitle = "Tracking contributions for $monthFull"
                        )
                        Button(
                            onClick = onFinishMonth,
                            enabled = !isBusy && cycleState.canFinish,
                            modifier = Modifier
                                .fillMaxWidth()
                                .semantics { contentDescription = "Finish $monthFull" }
                        ) {
                            Text("Finish $monthFull")
                        }
                        OutlinedButton(
                            onClick = onUndoStart,
                            enabled = !isBusy && cycleState.canUndoStart,
                            modifier = Modifier
                                .fillMaxWidth()
                                .semantics { contentDescription = "Back to Planning $monthFull" }
                        ) {
                            Text("Back to Planning $monthFull")
                        }
                        if (!cycleState.canUndoStart) {
                            Text(
                                text = undoStartReason,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }

                is UiCycleState.Closed -> {
                    val monthFull = formatMonthLabel(cycleState.monthLabel, monthFormatter)
                    val undoCompletionReason = ExecutionActionCopyCatalog.undoCompletionExpired(monthFull)
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        StateBadge(
                            icon = Icons.Default.CheckCircle,
                            title = "Completed",
                            subtitle = "Month $monthFull completed"
                        )
                        if (cycleState.canUndoCompletion) {
                            OutlinedButton(
                                onClick = onUndoFinish,
                                enabled = !isBusy,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .semantics { contentDescription = "Undo Finish $monthFull" }
                            ) {
                                Text("Undo Finish $monthFull")
                            }
                        } else {
                            Text(
                                text = undoCompletionReason,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }

                is UiCycleState.Conflict -> {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.Warning,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = ExecutionActionCopyCatalog.recordConflict(),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun StateBadge(
    icon: ImageVector,
    title: String,
    subtitle: String
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary
        )
        Spacer(modifier = Modifier.width(8.dp))
        Column {
            Text(
                text = title,
                style = MaterialTheme.typography.labelLarge
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
    Spacer(modifier = Modifier.height(4.dp))
}

private fun formatMonthLabel(monthLabel: String, formatter: DateTimeFormatter): String {
    return try {
        YearMonth.parse(monthLabel).format(formatter)
    } catch (_: DateTimeParseException) {
        monthLabel
    }
}
