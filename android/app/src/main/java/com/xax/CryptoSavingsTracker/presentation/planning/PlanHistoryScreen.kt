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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.AlertDialog
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
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.abs

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlanHistoryScreen(
    navController: NavController,
    viewModel: PlanHistoryViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val expandedByMonth = remember { mutableStateMapOf<String, Boolean>() }

    LaunchedEffect(uiState.error) {
        uiState.error?.let { error ->
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Execution History") },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        if (uiState.groups.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "No completed executions yet.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(uiState.groups, key = { it.monthLabel }) { group ->
                    MonthGroupCard(
                        group = group,
                        expanded = expandedByMonth[group.monthLabel] ?: false,
                        onToggleExpanded = {
                            val current = expandedByMonth[group.monthLabel] ?: false
                            expandedByMonth[group.monthLabel] = !current
                        },
                        isUndoing = uiState.isUndoing,
                        onRequestUndo = { recordId -> viewModel.requestUndo(recordId) }
                    )
                }
            }
        }

        if (uiState.showUndoConfirmationForRecordId != null) {
            AlertDialog(
                onDismissRequest = viewModel::dismissUndo,
                title = { Text("Undo Completion?") },
                text = { Text("This will reopen the execution for this month (24h window).") },
                confirmButton = {
                    TextButton(
                        onClick = viewModel::confirmUndo,
                        enabled = !uiState.isUndoing
                    ) {
                        Text("Undo")
                    }
                },
                dismissButton = {
                    TextButton(onClick = viewModel::dismissUndo) { Text("Cancel") }
                }
            )
        }
    }
}

@Composable
private fun MonthGroupCard(
    group: PlanHistoryMonthGroup,
    expanded: Boolean,
    onToggleExpanded: () -> Unit,
    isUndoing: Boolean,
    onRequestUndo: (String) -> Unit
) {
    val formatter = DateTimeFormatter.ofPattern("MMM d, yyyy 'at' HH:mm").withZone(ZoneId.systemDefault())
    val completedText = formatter.format(Instant.ofEpochMilli(group.latestCompletedAtMillis))

    val delta = group.summaryActual - group.summaryRequired
    val deltaText = if (delta >= 0) "+${String.format("%,.2f", delta)}" else "-${String.format("%,.2f", abs(delta))}"

    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = group.monthLabel,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Completed: $completedText",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "Required: ${String.format("%,.2f", group.summaryRequired)}",
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = "Actual: ${String.format("%,.2f", group.summaryActual)}",
                style = MaterialTheme.typography.bodyMedium
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = "Δ $deltaText",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                color = if (delta >= 0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error
            )
            Spacer(modifier = Modifier.height(6.dp))
            TextButton(onClick = onToggleExpanded) {
                Icon(
                    imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = null
                )
                Text(if (expanded) "Hide events" else "Show events")
            }
            group.undoRecordId?.let { undoRecordId ->
                Spacer(modifier = Modifier.height(6.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Undo available (24h window).",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Button(
                        onClick = { onRequestUndo(undoRecordId) },
                        enabled = !isUndoing
                    ) {
                        Text("Undo")
                    }
                }
            }
            if (expanded) {
                Spacer(modifier = Modifier.height(8.dp))
                group.events.forEach { event ->
                    EventRow(event = event, formatter = formatter)
                }
            }
        }
    }
}

@Composable
private fun EventRow(
    event: PlanHistoryRow,
    formatter: DateTimeFormatter
) {
    val completedText = formatter.format(Instant.ofEpochMilli(event.completedAtMillis))
    Text(
        text = completedText,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
    Text(
        text = "Event #${event.sequence}",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
    if (event.isUndone) {
        val undoneText = event.undoneAtMillis?.let { formatter.format(Instant.ofEpochMilli(it)) } ?: "unknown time"
        Text(
            text = "Undone at $undoneText",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.tertiary
        )
    } else {
        Text(
            text = if (event.isUndoAvailable) "Undo available" else "Undo expired",
            style = MaterialTheme.typography.bodySmall,
            color = if (event.isUndoAvailable) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
    Text(
        text = "Required ${String.format("%,.2f", event.totalRequired)} · Actual ${String.format("%,.2f", event.totalActual)}",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
    Spacer(modifier = Modifier.height(8.dp))
}
