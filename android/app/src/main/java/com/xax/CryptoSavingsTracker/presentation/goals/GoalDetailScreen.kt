package com.xax.CryptoSavingsTracker.presentation.goals

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.presentation.navigation.Screen
import com.xax.CryptoSavingsTracker.presentation.theme.GoalAtRisk
import com.xax.CryptoSavingsTracker.presentation.theme.GoalBehind
import com.xax.CryptoSavingsTracker.presentation.theme.GoalCompleted
import com.xax.CryptoSavingsTracker.presentation.theme.GoalOnTrack
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoalDetailScreen(
    navController: NavController,
    viewModel: GoalDetailViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var showMenu by remember { mutableStateOf(false) }

    // Navigate back when deleted
    LaunchedEffect(uiState.isDeleted) {
        if (uiState.isDeleted) {
            navController.popBackStack()
        }
    }

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
                title = { Text("Goal Details") },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    uiState.goal?.let { goal ->
                        IconButton(onClick = {
                            navController.navigate(Screen.EditGoal.createRoute(goal.id))
                        }) {
                            Icon(Icons.Default.Edit, contentDescription = "Edit")
                        }
                        Box {
                            IconButton(onClick = { showMenu = true }) {
                                Icon(Icons.Default.MoreVert, contentDescription = "More options")
                            }
                            DropdownMenu(
                                expanded = showMenu,
                                onDismissRequest = { showMenu = false }
                            ) {
                                DropdownMenuItem(
                                    text = { Text("Change Status") },
                                    onClick = {
                                        showMenu = false
                                        viewModel.showStatusMenu()
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Delete", color = MaterialTheme.colorScheme.error) },
                                    onClick = {
                                        showMenu = false
                                        viewModel.showDeleteConfirmation()
                                    },
                                    leadingIcon = {
                                        Icon(
                                            Icons.Default.Delete,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.error
                                        )
                                    }
                                )
                            }
                        }
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
                uiState.goal == null -> {
                    Text(
                        text = "Goal not found",
                        modifier = Modifier.align(Alignment.Center),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                else -> {
                    GoalDetailContent(goal = uiState.goal!!)
                }
            }
        }

        // Delete confirmation dialog
        if (uiState.showDeleteConfirmation) {
            AlertDialog(
                onDismissRequest = viewModel::dismissDeleteConfirmation,
                title = { Text("Delete Goal") },
                text = {
                    Text("Are you sure you want to delete \"${uiState.goal?.name}\"? This action cannot be undone.")
                },
                confirmButton = {
                    TextButton(onClick = viewModel::confirmDelete) {
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

        // Status change dialog
        if (uiState.showStatusMenu) {
            AlertDialog(
                onDismissRequest = viewModel::dismissStatusMenu,
                title = { Text("Change Status") },
                text = {
                    Column {
                        GoalLifecycleStatus.entries.forEach { status ->
                            TextButton(
                                onClick = { viewModel.updateStatus(status) },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(
                                    text = status.displayName(),
                                    color = if (status == uiState.goal?.lifecycleStatus) {
                                        MaterialTheme.colorScheme.primary
                                    } else {
                                        MaterialTheme.colorScheme.onSurface
                                    }
                                )
                            }
                        }
                    }
                },
                confirmButton = {},
                dismissButton = {
                    TextButton(onClick = viewModel::dismissStatusMenu) {
                        Text("Cancel")
                    }
                }
            )
        }
    }
}

private fun GoalLifecycleStatus.displayName(): String = when (this) {
    GoalLifecycleStatus.ACTIVE -> "Active"
    GoalLifecycleStatus.FINISHED -> "Finished"
    GoalLifecycleStatus.CANCELLED -> "Cancelled"
    GoalLifecycleStatus.DELETED -> "Deleted"
}

@Composable
private fun GoalDetailContent(goal: Goal) {
    val dateFormatter = remember { DateTimeFormatter.ofPattern("MMMM d, yyyy") }
    val daysRemaining = goal.daysRemaining()
    val statusColor = when {
        goal.lifecycleStatus == GoalLifecycleStatus.FINISHED -> GoalCompleted
        goal.isOverdue() -> GoalAtRisk
        daysRemaining < 30 -> GoalBehind
        else -> GoalOnTrack
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header with icon and name
        Row(
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.Flag,
                contentDescription = null,
                tint = statusColor,
                modifier = Modifier.size(32.dp)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column {
                Text(
                    text = goal.name,
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold
                )
                StatusChip(status = goal.lifecycleStatus)
            }
        }

        // Target amount card
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer
            )
        ) {
            Column(
                modifier = Modifier.padding(16.dp)
            ) {
                Text(
                    text = "Target Amount",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                )
                Text(
                    text = "${goal.currency} ${String.format("%,.2f", goal.targetAmount)}",
                    style = MaterialTheme.typography.displaySmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )
            }
        }

        // Progress section (placeholder)
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "Progress",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "0%", // TODO: Connect to actual progress
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = statusColor
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
                LinearProgressIndicator(
                    progress = { 0f }, // TODO: Connect to actual progress
                    modifier = Modifier.fillMaxWidth(),
                    color = statusColor,
                )
                Spacer(modifier = Modifier.height(8.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "${goal.currency} 0.00",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = "${goal.currency} ${String.format("%,.2f", goal.targetAmount)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        // Timeline section
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp)
            ) {
                Text(
                    text = "Timeline",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.height(12.dp))

                DetailRow("Start Date", goal.startDate.format(dateFormatter))
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                DetailRow("Deadline", goal.deadline.format(dateFormatter))
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                DetailRow(
                    "Time Remaining",
                    when {
                        goal.lifecycleStatus == GoalLifecycleStatus.FINISHED -> "Finished"
                        goal.isOverdue() -> "Overdue by ${-daysRemaining} days"
                        daysRemaining == 0L -> "Due today"
                        daysRemaining == 1L -> "1 day"
                        else -> "$daysRemaining days"
                    },
                    valueColor = statusColor
                )
            }
        }

        // Reminders section
        if (goal.isReminderEnabled && goal.reminderFrequency != null) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp)
                ) {
                    Text(
                        text = "Reminders",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = goal.reminderFrequency.displayName(),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
        }

        // Description section
        goal.description?.let { description ->
            if (description.isNotEmpty()) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp)
                    ) {
                        Text(
                            text = "Description",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = description,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun StatusChip(status: GoalLifecycleStatus) {
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
private fun DetailRow(
    label: String,
    value: String,
    valueColor: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.onSurface
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = valueColor
        )
    }
}
