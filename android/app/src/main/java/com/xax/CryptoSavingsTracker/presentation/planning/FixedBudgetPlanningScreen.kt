package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.model.CompletionBehavior
import com.xax.CryptoSavingsTracker.domain.model.FeasibilityLevel
import com.xax.CryptoSavingsTracker.domain.model.FeasibilityResult
import com.xax.CryptoSavingsTracker.domain.model.FeasibilitySuggestion
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.InfeasibleGoal
import com.xax.CryptoSavingsTracker.domain.model.ScheduledGoalBlock
import com.xax.CryptoSavingsTracker.domain.model.ScheduledPayment
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleGreen
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleRed
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleYellow
import com.xax.CryptoSavingsTracker.presentation.theme.CryptoSavingsTrackerTheme
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Currency
import kotlin.math.max

/**
 * Main screen for Fixed Budget planning mode.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FixedBudgetPlanningScreen(
    navController: NavController,
    viewModel: FixedBudgetPlanningViewModel = hiltViewModel(),
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    val budgetSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val setupSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    // Load goals on first launch
    LaunchedEffect(Unit) {
        viewModel.loadGoalsFromRepository()
    }

    // Show toast via Snackbar
    LaunchedEffect(uiState.toastMessage) {
        uiState.toastMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearToast()
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Budget Summary Card
            BudgetSummaryCard(
                monthlyBudget = uiState.monthlyBudget,
                currency = uiState.currency,
                feasibility = uiState.feasibilityResult,
                onEditBudget = { viewModel.showBudgetEditor() }
            )

            // Infeasibility Warning (if applicable)
            if (!uiState.feasibilityResult.isFeasible) {
                InfeasibilityWarningCard(
                    result = uiState.feasibilityResult,
                    onSuggestionTap = { suggestion ->
                        viewModel.applySuggestion(suggestion)
                    }
                )
            }

            // Current Focus Card (if plan exists)
            uiState.currentFocusGoal?.let { focus ->
                CurrentFocusCard(
                    goalName = focus.goalName,
                    emoji = focus.emoji,
                    progress = focus.progress.toFloat(),
                    contributed = focus.contributed,
                    target = focus.target,
                    currency = uiState.currency,
                    estimatedCompletion = focus.estimatedCompletion
                )
            }

            // Schedule Section
            if (uiState.scheduleBlocks.isNotEmpty()) {
                ScheduleSection(
                    blocks = uiState.scheduleBlocks,
                    payments = uiState.schedulePayments,
                    currency = uiState.currency,
                    currentPaymentNumber = uiState.currentPaymentNumber,
                    goalRemainingById = uiState.goalRemainingById
                )
            }
        }

        // Recalculating Overlay
        AnimatedVisibility(
            visible = uiState.isRecalculating,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.fillMaxSize()
        ) {
            RecalculatingOverlay()
        }

        // Snackbar Host at bottom
        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(16.dp)
        ) { data ->
            Snackbar(
                snackbarData = data,
                shape = RoundedCornerShape(8.dp),
                containerColor = MaterialTheme.colorScheme.inverseSurface,
                contentColor = MaterialTheme.colorScheme.inverseOnSurface
            )
        }
    }

    // Budget Editor Bottom Sheet
    if (uiState.showBudgetEditor) {
        ModalBottomSheet(
            onDismissRequest = { viewModel.hideBudgetEditor() },
            sheetState = budgetSheetState
        ) {
            BudgetEditorContent(
                budget = uiState.editingBudget,
                currency = uiState.currency,
                minimumRequired = uiState.minimumRequired,
                onBudgetChange = { viewModel.updateEditingBudget(it) },
                onSave = {
                    viewModel.saveBudget()
                    scope.launch { budgetSheetState.hide() }
                },
                onCancel = {
                    viewModel.hideBudgetEditor()
                    scope.launch { budgetSheetState.hide() }
                }
            )
        }
    }

    // Setup Sheet (first-time onboarding)
    if (uiState.showSetupSheet) {
        ModalBottomSheet(
            onDismissRequest = { viewModel.cancelSetup() },
            sheetState = setupSheetState
        ) {
            FixedBudgetSetupContent(
                budget = uiState.editingBudget,
                currency = uiState.currency,
                minimumRequired = uiState.minimumRequired,
                completionBehavior = uiState.completionBehavior,
                onBudgetChange = { viewModel.updateEditingBudget(it) },
                onCompletionBehaviorChange = { viewModel.updateCompletionBehavior(it) },
                onComplete = {
                    viewModel.completeSetup()
                    scope.launch { setupSheetState.hide() }
                },
                onCancel = {
                    viewModel.cancelSetup()
                    scope.launch { setupSheetState.hide() }
                }
            )
        }
    }

    // Quick Fix Confirmation Dialog
    uiState.pendingQuickFix?.let { quickFix ->
        QuickFixConfirmationDialog(
            quickFix = quickFix,
            onConfirm = { viewModel.confirmQuickFix() },
            onDismiss = { viewModel.dismissQuickFix() }
        )
    }
}

// MARK: - Recalculating Overlay

@Composable
private fun RecalculatingOverlay(
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.8f))
            .semantics { liveRegion = LiveRegionMode.Polite },
        contentAlignment = Alignment.Center
    ) {
        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant
            ),
            elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    strokeWidth = 2.dp
                )
                Text(
                    text = "Updating schedule...",
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

// MARK: - Budget Summary Card

@Composable
private fun BudgetSummaryCard(
    monthlyBudget: Double,
    currency: String,
    feasibility: FeasibilityResult,
    onEditBudget: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Monthly Budget",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                TextButton(onClick = onEditBudget) {
                    Icon(
                        imageVector = Icons.Default.Edit,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Edit")
                }
            }

            Text(
                text = formatCurrency(monthlyBudget, currency),
                style = MaterialTheme.typography.headlineLarge.copy(
                    fontWeight = FontWeight.Bold
                ),
                modifier = Modifier.padding(vertical = 8.dp)
            )

            // Feasibility status
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(
                    imageVector = feasibilityIcon(feasibility.statusLevel),
                    contentDescription = null,
                    tint = feasibilityColor(feasibility.statusLevel),
                    modifier = Modifier.size(18.dp)
                )
                Text(
                    text = feasibility.statusDescription,
                    style = MaterialTheme.typography.bodyMedium,
                    color = feasibilityColor(feasibility.statusLevel)
                )
            }
        }
    }
}

// MARK: - Infeasibility Warning Card

@Composable
private fun InfeasibilityWarningCard(
    result: FeasibilityResult,
    onSuggestionTap: (FeasibilitySuggestion) -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = AccessibleYellow.copy(alpha = 0.1f)
        ),
        border = CardDefaults.outlinedCardBorder().copy(
            width = 1.dp,
            brush = androidx.compose.ui.graphics.SolidColor(AccessibleYellow.copy(alpha = 0.3f))
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Warning,
                    contentDescription = null,
                    tint = AccessibleYellow
                )
                Text(
                    text = "Budget Shortfall",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Text(
                text = "Your budget cannot meet all deadlines.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            // Infeasible goals
            result.infeasibleGoals.forEach { goal ->
                InfeasibleGoalRow(goal = goal)
            }

            // Quick fix suggestions
            if (result.suggestions.isNotEmpty()) {
                Divider()
                Text(
                    text = "Quick fixes:",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                result.suggestions.forEach { suggestion ->
                    SuggestionButton(
                        suggestion = suggestion,
                        onClick = { onSuggestionTap(suggestion) }
                    )
                }
            }
        }
    }
}

@Composable
private fun InfeasibleGoalRow(
    goal: InfeasibleGoal,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column {
            Text(
                text = goal.goalName,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = "Needs ${formatCurrency(goal.requiredMonthly, goal.currency)}/mo",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(
            text = "Shortfall: ${formatCurrency(goal.shortfall, goal.currency)}",
            style = MaterialTheme.typography.bodySmall,
            color = AccessibleRed
        )
    }
}

@Composable
private fun SuggestionButton(
    suggestion: FeasibilitySuggestion,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surface
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 10.dp, horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = suggestionIcon(suggestion),
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = suggestion.title,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f)
            )
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

// MARK: - Current Focus Card

@Composable
private fun CurrentFocusCard(
    goalName: String,
    emoji: String?,
    progress: Float,
    contributed: Double,
    target: Double,
    currency: String,
    estimatedCompletion: LocalDate?,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Current Focus",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Surface(
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.primary
                ) {
                    Text(
                        text = "NOW",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onPrimary,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                    )
                }
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (emoji != null) {
                    Text(
                        text = emoji,
                        fontSize = 24.sp
                    )
                }
                Text(
                    text = goalName,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
            }

            // Progress bar
            LinearProgressIndicator(
                progress = { progress.coerceIn(0f, 1f) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp)
                    .clip(RoundedCornerShape(4.dp)),
                color = MaterialTheme.colorScheme.primary
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row {
                    Text(
                        text = formatCurrency(contributed, currency),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = " of ${formatCurrency(target, currency)}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = "${(progress * 100).toInt()}%",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
                )
            }

            if (estimatedCompletion != null) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.CalendarMonth,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = "Completes: ${estimatedCompletion.format(DateTimeFormatter.ofPattern("MMM d, yyyy"))}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

// MARK: - Schedule Section

@Composable
private fun ScheduleSection(
    blocks: List<ScheduledGoalBlock>,
    payments: List<ScheduledPayment>,
    currency: String,
    currentPaymentNumber: Int,
    goalRemainingById: Map<String, Double>,
    modifier: Modifier = Modifier
) {
    var expandedGoals by remember { mutableStateOf(setOf<String>()) }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = "Upcoming Schedule",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )

        if (blocks.isNotEmpty()) {
            TimelineStepper(
                blocks = blocks,
                currentPaymentNumber = currentPaymentNumber
            )
        }

        blocks.forEach { block ->
            val details = paymentDetailsForGoal(block.goalId, payments)
            val isExpanded = expandedGoals.contains(block.goalId)
            ScheduleBlockCard(
                block = block,
                currency = currency,
                remainingAmount = goalRemainingById[block.goalId],
                isCurrent = block.startPaymentNumber <= currentPaymentNumber &&
                        block.endPaymentNumber >= currentPaymentNumber,
                isExpanded = isExpanded,
                onToggle = {
                    expandedGoals = if (isExpanded) {
                        expandedGoals - block.goalId
                    } else {
                        expandedGoals + block.goalId
                    }
                },
                paymentDetails = details
            )
        }
    }
}

private data class PaymentDetail(
    val date: LocalDate,
    val amount: Double,
    val paymentNumber: Int
)

private fun paymentDetailsForGoal(goalId: String, payments: List<ScheduledPayment>): List<PaymentDetail> {
    return payments.mapNotNull { payment ->
        val amount = payment.contributions
            .filter { it.goalId == goalId }
            .sumOf { it.amount }
        if (amount > 0.01) {
            PaymentDetail(payment.paymentDate, amount, payment.paymentNumber)
        } else {
            null
        }
    }
}

@Composable
private fun ScheduleBlockCard(
    block: ScheduledGoalBlock,
    currency: String,
    remainingAmount: Double?,
    isCurrent: Boolean,
    isExpanded: Boolean,
    onToggle: () -> Unit,
    paymentDetails: List<PaymentDetail>,
    modifier: Modifier = Modifier
) {
    val backgroundColor = if (isCurrent) {
        MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)
    } else {
        MaterialTheme.colorScheme.surfaceVariant
    }

    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = backgroundColor)
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = block.dateRange,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = "(${block.paymentCount} payment${if (block.paymentCount == 1) "" else "s"})",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (isCurrent) {
                    Surface(
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.primary
                    ) {
                        Text(
                            text = "NOW",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onPrimary,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                        )
                    }
                }
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                if (block.emoji != null) {
                    Text(text = block.emoji)
                }
                Text(
                    text = block.goalName,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
                )
            }

            if (remainingAmount != null) {
                Text(
                    text = "Planned: ${formatCurrency(block.totalAmount, currency)} of ${formatCurrency(remainingAmount, currency)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Text(
                    text = "${formatCurrency(block.totalAmount, currency)} total",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            if (remainingAmount != null) {
                val shortfall = (remainingAmount - block.totalAmount).coerceAtLeast(0.0)
                if (shortfall > 0.01) {
                    Text(
                        text = "Shortfall: ${formatCurrency(shortfall, currency)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }

            if (paymentDetails.isNotEmpty()) {
                TextButton(onClick = onToggle) {
                    Text(if (isExpanded) "Hide month-by-month" else "Show month-by-month")
                }
            }

            if (isExpanded) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    paymentDetails.forEach { detail ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text(
                                text = detail.date.format(DateTimeFormatter.ofPattern("MMM d, yyyy")),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Text(
                                text = formatCurrency(detail.amount, currency),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    if (remainingAmount != null) {
                        val shortfall = (remainingAmount - block.totalAmount).coerceAtLeast(0.0)
                        if (shortfall > 0.01) {
                            Text(
                                text = "Remaining after schedule: ${formatCurrency(shortfall, currency)}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TimelineStepper(
    blocks: List<ScheduledGoalBlock>,
    currentPaymentNumber: Int,
    modifier: Modifier = Modifier
) {
    BoxWithConstraints(
        modifier = modifier
            .fillMaxWidth()
            .height(16.dp)
    ) {
        val totalPayments = max(1, blocks.sumOf { it.paymentCount })
        val clampedIndex = (currentPaymentNumber - 1).coerceIn(0, totalPayments)
        val markerOffset = maxWidth * (clampedIndex.toFloat() / totalPayments.toFloat())

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.CenterStart),
            horizontalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            blocks.forEach { block ->
                Box(
                    modifier = Modifier
                        .weight(block.paymentCount.toFloat())
                        .height(10.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.2f))
                )
            }
        }

        Box(
            modifier = Modifier
                .offset(x = markerOffset)
                .width(2.dp)
                .height(16.dp)
                .background(MaterialTheme.colorScheme.primary)
        )
    }
}

// MARK: - Budget Editor Content

@Composable
private fun BudgetEditorContent(
    budget: Double,
    currency: String,
    minimumRequired: Double,
    onBudgetChange: (Double) -> Unit,
    onSave: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier
) {
    var budgetText by remember(budget) { mutableStateOf(if (budget > 0) budget.toString() else "") }
    var useMinimum by remember { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = "Edit Budget",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold
        )

        Text(
            text = "Monthly Savings Amount",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        OutlinedTextField(
            value = budgetText,
            onValueChange = { newValue ->
                budgetText = newValue
                newValue.toDoubleOrNull()?.let { onBudgetChange(it) }
            },
            label = { Text("Monthly Budget") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.fillMaxWidth()
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Use minimum required")
            Switch(
                checked = useMinimum,
                onCheckedChange = { checked ->
                    useMinimum = checked
                    if (checked) {
                        budgetText = String.format("%.2f", minimumRequired)
                        onBudgetChange(minimumRequired)
                    }
                }
            )
        }

        Text(
            text = "Minimum required: ${formatCurrency(minimumRequired, currency)}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(16.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            OutlinedButton(
                onClick = onCancel,
                modifier = Modifier.weight(1f)
            ) {
                Text("Cancel")
            }
            Button(
                onClick = onSave,
                modifier = Modifier.weight(1f)
            ) {
                Text("Save")
            }
        }
    }
}

// MARK: - Setup Sheet Content

@Composable
private fun FixedBudgetSetupContent(
    budget: Double,
    currency: String,
    minimumRequired: Double,
    completionBehavior: CompletionBehavior,
    onBudgetChange: (Double) -> Unit,
    onCompletionBehaviorChange: (CompletionBehavior) -> Unit,
    onComplete: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier
) {
    var step by remember { mutableIntStateOf(1) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        if (step == 1) {
            SetupStep1Content(
                budget = budget,
                currency = currency,
                minimumRequired = minimumRequired,
                onBudgetChange = onBudgetChange,
                onContinue = { step = 2 },
                onCancel = onCancel
            )
        } else {
            SetupStep2Content(
                completionBehavior = completionBehavior,
                onCompletionBehaviorChange = onCompletionBehaviorChange,
                onDone = onComplete,
                onBack = { step = 1 }
            )
        }
    }
}

@Composable
private fun SetupStep1Content(
    budget: Double,
    currency: String,
    minimumRequired: Double,
    onBudgetChange: (Double) -> Unit,
    onContinue: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier
) {
    var budgetText by remember(budget) { mutableStateOf(if (budget > 0) budget.toInt().toString() else "") }
    var useMinimum by remember { mutableStateOf(false) }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = "Set Your Budget",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold
        )

        Text(
            text = "How much can you save each month?",
            style = MaterialTheme.typography.titleMedium
        )

        OutlinedTextField(
            value = budgetText,
            onValueChange = { newValue ->
                budgetText = newValue
                newValue.toDoubleOrNull()?.let { onBudgetChange(it) }
            },
            label = { Text("Amount") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
            textStyle = MaterialTheme.typography.titleLarge
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Use minimum required")
            Switch(
                checked = useMinimum,
                onCheckedChange = { checked ->
                    useMinimum = checked
                    if (checked) {
                        budgetText = minimumRequired.toInt().toString()
                        onBudgetChange(minimumRequired)
                    }
                }
            )
        }

        Text(
            text = "Suggested minimum: ${formatCurrency(minimumRequired, currency)}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(16.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            OutlinedButton(
                onClick = onCancel,
                modifier = Modifier.weight(1f)
            ) {
                Text("Cancel")
            }
            Button(
                onClick = onContinue,
                modifier = Modifier.weight(1f),
                enabled = budgetText.isNotEmpty()
            ) {
                Text("Continue")
            }
        }
    }
}

@Composable
private fun SetupStep2Content(
    completionBehavior: CompletionBehavior,
    onCompletionBehaviorChange: (CompletionBehavior) -> Unit,
    onDone: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = "Completion Behavior",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold
        )

        Text(
            text = "What should happen when you complete a goal ahead of schedule?",
            style = MaterialTheme.typography.titleMedium
        )

        CompletionBehavior.entries.forEach { behavior ->
            CompletionBehaviorOption(
                behavior = behavior,
                isSelected = completionBehavior == behavior,
                onClick = { onCompletionBehaviorChange(behavior) }
            )
        }

        Text(
            text = "You can change this anytime in settings.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(16.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            OutlinedButton(
                onClick = onBack,
                modifier = Modifier.weight(1f)
            ) {
                Text("Back")
            }
            Button(
                onClick = onDone,
                modifier = Modifier.weight(1f)
            ) {
                Text("Done")
            }
        }
    }
}

@Composable
private fun CompletionBehaviorOption(
    behavior: CompletionBehavior,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(12.dp),
        color = if (isSelected) {
            MaterialTheme.colorScheme.primaryContainer
        } else {
            MaterialTheme.colorScheme.surfaceVariant
        }
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = behavior.displayName,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    text = behavior.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            RadioButton(
                selected = isSelected,
                onClick = onClick
            )
        }
    }
}

// MARK: - Quick Fix Confirmation Dialog

@Composable
private fun QuickFixConfirmationDialog(
    quickFix: PendingQuickFix,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(
                imageVector = when (quickFix.suggestion) {
                    is FeasibilitySuggestion.ExtendDeadline -> Icons.Default.Event
                    is FeasibilitySuggestion.ReduceTarget -> Icons.Default.RemoveCircle
                    is FeasibilitySuggestion.IncreaseBudget -> Icons.Default.ArrowUpward
                },
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(48.dp)
            )
        },
        title = {
            Text(
                text = quickFix.title,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
        },
        text = {
            Text(
                text = quickFix.description,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        },
        confirmButton = {
            Button(onClick = onConfirm) {
                Text(quickFix.actionButtonLabel)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

// MARK: - Helper Functions

private fun formatCurrency(amount: Double, currency: String): String {
    return try {
        val format = NumberFormat.getCurrencyInstance()
        format.currency = Currency.getInstance(currency)
        format.maximumFractionDigits = 0
        format.format(amount)
    } catch (e: Exception) {
        "$${String.format("%.0f", amount)}"
    }
}

private fun feasibilityIcon(level: FeasibilityLevel): ImageVector {
    return when (level) {
        FeasibilityLevel.ACHIEVABLE -> Icons.Default.CheckCircle
        FeasibilityLevel.AT_RISK -> Icons.Default.Warning
        FeasibilityLevel.CRITICAL -> Icons.Default.Cancel
    }
}

private fun feasibilityColor(level: FeasibilityLevel): Color {
    return when (level) {
        FeasibilityLevel.ACHIEVABLE -> AccessibleGreen
        FeasibilityLevel.AT_RISK -> AccessibleYellow
        FeasibilityLevel.CRITICAL -> AccessibleRed
    }
}

private fun suggestionIcon(suggestion: FeasibilitySuggestion): ImageVector {
    return when (suggestion) {
        is FeasibilitySuggestion.IncreaseBudget -> Icons.Default.ArrowUpward
        is FeasibilitySuggestion.ExtendDeadline -> Icons.Default.Event
        is FeasibilitySuggestion.ReduceTarget -> Icons.Default.RemoveCircle
    }
}

// MARK: - Previews

@Preview(showBackground = true)
@Composable
private fun BudgetSummaryCardPreview() {
    CryptoSavingsTrackerTheme {
        BudgetSummaryCard(
            monthlyBudget = 500.0,
            currency = "USD",
            feasibility = FeasibilityResult.EMPTY,
            onEditBudget = {},
            modifier = Modifier.padding(16.dp)
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun CurrentFocusCardPreview() {
    CryptoSavingsTrackerTheme {
        CurrentFocusCard(
            goalName = "Vacation Fund",
            emoji = "🏖️",
            progress = 0.45f,
            contributed = 450.0,
            target = 1000.0,
            currency = "USD",
            estimatedCompletion = LocalDate.now().plusMonths(2),
            modifier = Modifier.padding(16.dp)
        )
    }
}
