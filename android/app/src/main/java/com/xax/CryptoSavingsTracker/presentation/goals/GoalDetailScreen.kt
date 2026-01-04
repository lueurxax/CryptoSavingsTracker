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
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
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
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.presentation.common.AmountFormatters
import com.xax.CryptoSavingsTracker.presentation.navigation.Screen
import com.xax.CryptoSavingsTracker.presentation.theme.GoalAtRisk
import com.xax.CryptoSavingsTracker.presentation.theme.GoalBehind
import com.xax.CryptoSavingsTracker.presentation.theme.GoalCompleted
import com.xax.CryptoSavingsTracker.presentation.theme.GoalOnTrack
import com.xax.CryptoSavingsTracker.presentation.theme.IconSize
import com.xax.CryptoSavingsTracker.presentation.theme.Spacing
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
                                    text = { Text("Archive Goal") },
                                    onClick = {
                                        showMenu = false
                                        viewModel.showDeleteConfirmation()
                                    },
                                    leadingIcon = {
                                        Icon(
                                            Icons.Default.Archive,
                                            contentDescription = null
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
                    GoalDetailContent(
                        goal = uiState.goal!!,
                        fundedAmount = uiState.fundedAmount,  // Use fundedAmount to match iOS
                        progress = uiState.progress,
                        progressPercent = uiState.progressPercent,
                        onManageAllocations = {
                            navController.navigate(Screen.AllocationList.createRoute(uiState.goal!!.id))
                        }
                    )
                }
            }
        }

        // Archive goal dialog - 2-step flow for clearer UX
        if (uiState.showDeleteConfirmation) {
            var dialogStep by remember { mutableStateOf(0) }

            AlertDialog(
                onDismissRequest = {
                    dialogStep = 0
                    viewModel.dismissDeleteConfirmation()
                },
                title = {
                    Text(
                        if (dialogStep == 0) "What would you like to do?"
                        else "Choose Archive Type"
                    )
                },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        if (dialogStep == 0) {
                            // Step 1: Archive vs Delete
                            Text(
                                "\"${uiState.goal?.name}\"",
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold
                            )

                            // Archive button (primary action)
                            Button(
                                onClick = { dialogStep = 1 },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Archive,
                                    contentDescription = null,
                                    modifier = Modifier.size(IconSize.small)
                                )
                                Spacer(modifier = Modifier.width(Spacing.xs))
                                Text("Archive Goal")
                            }

                            // Delete button (destructive action)
                            OutlinedButton(
                                onClick = viewModel::confirmDelete,
                                modifier = Modifier.fillMaxWidth(),
                                colors = ButtonDefaults.outlinedButtonColors(
                                    contentColor = MaterialTheme.colorScheme.error
                                )
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Delete,
                                    contentDescription = null,
                                    modifier = Modifier.size(IconSize.small)
                                )
                                Spacer(modifier = Modifier.width(Spacing.xs))
                                Text("Delete Permanently")
                            }
                        } else {
                            // Step 2: Choose archive type

                            // Mark Finished option
                            OutlinedButton(
                                onClick = { viewModel.updateStatus(GoalLifecycleStatus.FINISHED) },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Column(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalAlignment = Alignment.Start
                                ) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Icon(
                                            imageVector = Icons.Default.CheckCircle,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.primary,
                                            modifier = Modifier.size(IconSize.small)
                                        )
                                        Spacer(modifier = Modifier.width(Spacing.xs))
                                        Text(
                                            "Mark as Finished",
                                            fontWeight = FontWeight.SemiBold
                                        )
                                    }
                                    Text(
                                        "Allocations are kept (treated as spent)",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }

                            // Cancel Goal option
                            OutlinedButton(
                                onClick = { viewModel.updateStatus(GoalLifecycleStatus.CANCELLED) },
                                modifier = Modifier.fillMaxWidth(),
                                colors = ButtonDefaults.outlinedButtonColors(
                                    contentColor = MaterialTheme.colorScheme.error
                                )
                            ) {
                                Column(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalAlignment = Alignment.Start
                                ) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Icon(
                                            imageVector = Icons.Default.Cancel,
                                            contentDescription = null,
                                            modifier = Modifier.size(IconSize.small)
                                        )
                                        Spacer(modifier = Modifier.width(Spacing.xs))
                                        Text(
                                            "Cancel Goal",
                                            fontWeight = FontWeight.SemiBold
                                        )
                                    }
                                    Text(
                                        "Allocations are freed back to unallocated",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                },
                confirmButton = { /* Actions are in text content */ },
                dismissButton = {
                    TextButton(
                        onClick = {
                            if (dialogStep == 1) {
                                dialogStep = 0
                            } else {
                                viewModel.dismissDeleteConfirmation()
                            }
                        }
                    ) {
                        Text(if (dialogStep == 1) "Back" else "Cancel")
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
private fun GoalDetailContent(
    goal: Goal,
    fundedAmount: Double,  // Actual funded amount (min of allocation vs balance, matches iOS)
    progress: Double,
    progressPercent: Int,
    onManageAllocations: () -> Unit = {}
) {
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
            .padding(Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        // Header with emoji/icon and name
        Row(
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (goal.emoji != null) {
                Text(
                    text = goal.emoji,
                    style = MaterialTheme.typography.headlineMedium
                )
            } else {
                Icon(
                    imageVector = Icons.Default.Flag,
                    contentDescription = null,
                    tint = statusColor,
                    modifier = Modifier.size(IconSize.large)
                )
            }
            Spacer(modifier = Modifier.width(Spacing.sm))
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
                modifier = Modifier.padding(Spacing.md)
            ) {
                Text(
                    text = "Target Amount",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                )
                Text(
                    text = AmountFormatters.formatDisplayCurrencyAmount(goal.targetAmount, goal.currency, isCrypto = false),
                    style = MaterialTheme.typography.displaySmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )
            }
        }

        // Progress section with real values
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(Spacing.md)
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
                        text = "$progressPercent%",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = statusColor
                    )
                }
                Spacer(modifier = Modifier.height(Spacing.xs))
                LinearProgressIndicator(
                    progress = { progress.toFloat().coerceIn(0f, 1f) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { contentDescription = "${goal.name} progress: $progressPercent percent complete" },
                    color = statusColor,
                    trackColor = MaterialTheme.colorScheme.surfaceVariant
                )
                Spacer(modifier = Modifier.height(Spacing.xs))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = AmountFormatters.formatDisplayCurrencyAmount(fundedAmount, goal.currency, isCrypto = false),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = AmountFormatters.formatDisplayCurrencyAmount(goal.targetAmount, goal.currency, isCrypto = false),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        // Allocations section
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(Spacing.md)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Allocations",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    TextButton(onClick = onManageAllocations) {
                        Text("Manage")
                    }
                }
                Spacer(modifier = Modifier.height(Spacing.xxs))
                Text(
                    text = "Allocate assets to fund this goal",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        // Link section
        goal.link?.let { link ->
            if (link.isNotEmpty()) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(Spacing.md)
                    ) {
                        Text(
                            text = "Link",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Spacer(modifier = Modifier.height(Spacing.xs))
                        Text(
                            text = link,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                }
            }
        }

        // Timeline section
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(Spacing.md)
            ) {
                Text(
                    text = "Timeline",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.height(Spacing.sm))

                DetailRow("Start Date", goal.startDate.format(dateFormatter))
                HorizontalDivider(modifier = Modifier.padding(vertical = Spacing.xs))
                DetailRow("Deadline", goal.deadline.format(dateFormatter))
                HorizontalDivider(modifier = Modifier.padding(vertical = Spacing.xs))
                DetailRow(
                    "Time Remaining",
                    when {
                        goal.lifecycleStatus == GoalLifecycleStatus.FINISHED -> "Finished"
                        goal.isOverdue() -> "Overdue by ${-daysRemaining} days"
                        daysRemaining == 0L -> "Due today"
                        daysRemaining == 1L -> "1 day left"
                        daysRemaining < 7L -> "$daysRemaining days left"
                        daysRemaining < 30L -> "${daysRemaining / 7} weeks left"
                        daysRemaining < 365L -> "${daysRemaining / 30} months left"
                        else -> "${daysRemaining / 365} years left"
                    },
                    valueColor = statusColor
                )
            }
        }

        // Reminders section
        if (goal.isReminderEnabled && goal.reminderFrequency != null) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(Spacing.md)
                ) {
                    Text(
                        text = "Reminders",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Spacer(modifier = Modifier.height(Spacing.xs))
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
                        modifier = Modifier.padding(Spacing.md)
                    ) {
                        Text(
                            text = "Description",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Spacer(modifier = Modifier.height(Spacing.xs))
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
        GoalLifecycleStatus.ACTIVE -> "Active" to GoalCompleted  // Blue to avoid conflict with green progress bars
        GoalLifecycleStatus.FINISHED -> "Finished" to GoalOnTrack  // Green for completed
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
            modifier = Modifier.padding(horizontal = Spacing.xs, vertical = Spacing.xxs)
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
