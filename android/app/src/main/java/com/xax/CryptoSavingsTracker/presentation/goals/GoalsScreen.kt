package com.xax.CryptoSavingsTracker.presentation.goals

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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GoalWithProgress
import com.xax.CryptoSavingsTracker.presentation.navigation.Screen
import com.xax.CryptoSavingsTracker.presentation.theme.GoalAtRisk
import com.xax.CryptoSavingsTracker.presentation.theme.GoalBehind
import com.xax.CryptoSavingsTracker.presentation.theme.GoalCompleted
import com.xax.CryptoSavingsTracker.presentation.theme.GoalOnTrack
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoalsScreen(
    navController: NavController,
    viewModel: GoalListViewModel = hiltViewModel()
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
                title = { Text("Goals") }
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { navController.navigate(Screen.AddGoal.route) }
            ) {
                Icon(Icons.Default.Add, contentDescription = "Add Goal")
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Filter chips
            GoalFilterChips(
                selectedFilter = uiState.selectedFilter,
                onFilterSelected = viewModel::setFilter
            )

            if (uiState.isLoading) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            } else if (uiState.goals.isEmpty()) {
                EmptyGoalsState(
                    filter = uiState.selectedFilter,
                    onAddGoal = { navController.navigate(Screen.AddGoal.route) }
                )
            } else {
                LazyColumn(
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    items(
                        items = uiState.goals,
                        key = { it.goal.id }
                    ) { goalWithProgress ->
                        GoalCard(
                            goalWithProgress = goalWithProgress,
                            onClick = { navController.navigate(Screen.GoalDetail.createRoute(goalWithProgress.goal.id)) },
                            onLongClick = { viewModel.requestDeleteGoal(goalWithProgress.goal) }
                        )
                    }
                }
            }
        }

        // Delete confirmation dialog
        uiState.showDeleteConfirmation?.let { goal ->
            AlertDialog(
                onDismissRequest = viewModel::dismissDeleteConfirmation,
                title = { Text("Delete Goal") },
                text = { Text("Are you sure you want to delete \"${goal.name}\"? This action cannot be undone.") },
                confirmButton = {
                    TextButton(onClick = viewModel::confirmDeleteGoal) {
                        Text("Delete", color = MaterialTheme.colorScheme.error)
                    }
                },
                dismissButton = {
                    TextButton(onClick = viewModel::dismissDeleteConfirmation) {
                        Text("Cancel")
                    }
                }
            )
        }
    }
}

@Composable
private fun GoalFilterChips(
    selectedFilter: GoalFilter,
    onFilterSelected: (GoalFilter) -> Unit
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        items(GoalFilter.entries) { filter ->
            FilterChip(
                selected = selectedFilter == filter,
                onClick = { onFilterSelected(filter) },
                label = { Text(filter.displayName()) }
            )
        }
    }
}

private fun GoalFilter.displayName(): String = when (this) {
    GoalFilter.ALL -> "All"
    GoalFilter.ACTIVE -> "Active"
    GoalFilter.FINISHED -> "Finished"
    GoalFilter.CANCELLED -> "Cancelled"
    GoalFilter.DELETED -> "Deleted"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GoalCard(
    goalWithProgress: GoalWithProgress,
    onClick: () -> Unit,
    onLongClick: () -> Unit
) {
    val goal = goalWithProgress.goal
    val dateFormatter = remember { DateTimeFormatter.ofPattern("MMM d, yyyy") }
    val daysRemaining = goal.daysRemaining()
    val statusColor = when {
        goal.lifecycleStatus == GoalLifecycleStatus.FINISHED -> GoalCompleted
        goal.isOverdue() -> GoalAtRisk
        daysRemaining < 30 -> GoalBehind
        else -> GoalOnTrack
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.Flag,
                        contentDescription = null,
                        tint = statusColor,
                        modifier = Modifier.size(24.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = goal.name,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                StatusBadge(status = goal.lifecycleStatus)
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Progress and target amount (uses fundedAmount to match iOS)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "${goal.currency} ${String.format("%,.2f", goalWithProgress.fundedAmount)}",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary
                )
                Text(
                    text = "${goalWithProgress.progressPercent}%",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = statusColor
                )
            }

            Text(
                text = "of ${goal.currency} ${String.format("%,.2f", goal.targetAmount)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Progress bar with real progress
            LinearProgressIndicator(
                progress = { goalWithProgress.progress.toFloat().coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
                color = statusColor,
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Deadline info
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "Deadline: ${goal.deadline.format(dateFormatter)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = when {
                        goal.lifecycleStatus == GoalLifecycleStatus.FINISHED -> "Finished"
                        goal.isOverdue() -> "Overdue by ${-daysRemaining} days"
                        daysRemaining == 0L -> "Due today"
                        daysRemaining == 1L -> "1 day left"
                        else -> "$daysRemaining days left"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Medium,
                    color = statusColor
                )
            }
        }
    }
}

@Composable
private fun StatusBadge(status: GoalLifecycleStatus) {
    val (text, color) = when (status) {
        GoalLifecycleStatus.ACTIVE -> "Active" to GoalOnTrack
        GoalLifecycleStatus.FINISHED -> "Finished" to GoalCompleted
        GoalLifecycleStatus.CANCELLED -> "Cancelled" to GoalAtRisk
        GoalLifecycleStatus.DELETED -> "Deleted" to GoalBehind
    }

    Card(
        colors = CardDefaults.cardColors(
            containerColor = color.copy(alpha = 0.15f)
        )
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            color = color,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
        )
    }
}

@Composable
private fun EmptyGoalsState(
    filter: GoalFilter,
    onAddGoal: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.Flag,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = if (filter == GoalFilter.ALL) "No goals yet" else "No ${filter.displayName().lowercase()} goals",
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = if (filter == GoalFilter.ALL) {
                "Create your first savings goal to start tracking your progress"
            } else {
                "Goals with this status will appear here"
            },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (filter == GoalFilter.ALL) {
            Spacer(modifier = Modifier.height(24.dp))
            TextButton(onClick = onAddGoal) {
                Icon(Icons.Default.Add, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Add Goal")
            }
        }
    }
}
