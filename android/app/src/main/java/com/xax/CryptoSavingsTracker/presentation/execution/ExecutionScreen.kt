package com.xax.CryptoSavingsTracker.presentation.execution

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionGoalProgress
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.abs

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExecutionScreen(
    navController: NavController,
    viewModel: ExecutionViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(uiState.error) {
        uiState.error?.let { error ->
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Execution") },
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
                ActiveExecutionState(
                    monthLabel = uiState.session!!.record.monthLabel,
                    startedAtMillis = uiState.session!!.record.startedAtMillis,
                    goals = uiState.session!!.goals,
                    isBusy = uiState.isBusy,
                    onComplete = viewModel::completeExecution
                )
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
        Text(
            text = "No active execution",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Start monthly execution to track progress from a baseline snapshot.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(24.dp))
        Button(
            onClick = onStart,
            enabled = !isBusy
        ) {
            Icon(Icons.Default.PlayArrow, contentDescription = null)
            Spacer(modifier = Modifier.padding(start = 8.dp))
            Text("Start Execution")
        }
        if (canUndo) {
            Spacer(modifier = Modifier.height(12.dp))
            Button(
                onClick = onUndo,
                enabled = !isBusy
            ) {
                Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = null)
                Spacer(modifier = Modifier.padding(start = 8.dp))
                Text("Undo Last Completion")
            }
        }
    }
}

@Composable
private fun ActiveExecutionState(
    monthLabel: String,
    startedAtMillis: Long?,
    goals: List<ExecutionGoalProgress>,
    isBusy: Boolean,
    onComplete: () -> Unit
) {
    val startedAtText = remember(startedAtMillis) {
        startedAtMillis?.let {
            val formatter = DateTimeFormatter.ofPattern("MMM d, yyyy 'at' HH:mm").withZone(ZoneId.systemDefault())
            formatter.format(Instant.ofEpochMilli(it))
        } ?: "—"
    }

    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = "Month: $monthLabel",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "Started: $startedAtText",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    Button(
                        onClick = onComplete,
                        enabled = !isBusy,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Default.CheckCircle, contentDescription = null)
                        Spacer(modifier = Modifier.padding(start = 8.dp))
                        Text("Complete Execution")
                    }
                }
            }
        }

        if (goals.isEmpty()) {
            item {
                Text(
                    text = "No goals in this execution.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        } else {
            items(goals, key = { it.snapshot.goalId }) { item ->
                ExecutionGoalCard(item = item)
            }
        }
    }
}

@Composable
private fun ExecutionGoalCard(item: ExecutionGoalProgress) {
    val snapshot = item.snapshot
    val delta = item.deltaSinceStart
    val deltaText = if (delta >= 0) "+${String.format("%,.2f", delta)}" else "-${String.format("%,.2f", abs(delta))}"

    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = snapshot.goalName,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(6.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "Start: ${snapshot.currency} ${String.format("%,.2f", item.baselineFunded)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = "Now: ${snapshot.currency} ${String.format("%,.2f", item.currentFunded)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = "Δ $deltaText ${snapshot.currency}",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                color = if (delta >= 0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error
            )
            if (snapshot.requiredAmount > 0) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Required: ${snapshot.currency} ${String.format("%,.2f", snapshot.requiredAmount)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
