package com.xax.CryptoSavingsTracker.presentation.planning.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.domain.model.BudgetCalculatorPlan
import com.xax.CryptoSavingsTracker.domain.model.FeasibilitySuggestion
import com.xax.CryptoSavingsTracker.domain.model.FeasibilityLevel
import com.xax.CryptoSavingsTracker.domain.model.FeasibilityResult
import com.xax.CryptoSavingsTracker.domain.model.InfeasibleGoal
import com.xax.CryptoSavingsTracker.domain.model.ScheduledGoalBlock
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleGreen
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleRed
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleYellow
import java.text.NumberFormat
import java.util.Currency
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material3.HorizontalDivider
import com.xax.CryptoSavingsTracker.domain.model.GoalContribution
import com.xax.CryptoSavingsTracker.domain.model.ScheduledPayment

@Composable
fun BudgetEntryCard(
    onSetBudget: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f)
        )
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
                    text = "Plan by Budget",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Set a monthly amount and we'll calculate optimal contributions.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(modifier = Modifier.width(12.dp))
            Button(onClick = onSetBudget) {
                Text("Set Budget")
            }
        }
    }
}

@Composable
fun BudgetSummaryCard(
    budgetAmount: Double,
    budgetCurrency: String,
    feasibility: FeasibilityResult,
    isApplied: Boolean,
    currentFocusGoal: String?,
    currentFocusDeadline: LocalDate?,
    onEdit: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.25f)
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "Monthly Budget",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = formatCurrency(budgetAmount, budgetCurrency),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                TextButton(onClick = onEdit) {
                    Icon(
                        imageVector = Icons.Default.Edit,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Edit")
                }
            }

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
                    style = MaterialTheme.typography.bodySmall,
                    color = feasibilityColor(feasibility.statusLevel)
                )
            }

            if (!feasibility.isFeasible) {
                Text(
                    text = "Minimum required: ${formatCurrency(feasibility.minimumRequired, budgetCurrency)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            if (currentFocusGoal != null) {
                val focusLabel = if (currentFocusDeadline != null) {
                    val formatter = DateTimeFormatter.ofPattern("MMM d")
                    "Next: $currentFocusGoal (until ${currentFocusDeadline.format(formatter)})"
                } else {
                    "Next: $currentFocusGoal"
                }
                Text(
                    text = focusLabel,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            if (!isApplied) {
                Text(
                    text = "Budget is set but not applied to this month yet.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
fun BudgetNoticeCard(
    title: String,
    message: String,
    primaryActionLabel: String,
    onPrimaryAction: () -> Unit,
    secondaryActionLabel: String?,
    onSecondaryAction: (() -> Unit)?,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.45f)
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onPrimaryAction) {
                    Text(primaryActionLabel)
                }
                if (secondaryActionLabel != null && onSecondaryAction != null) {
                    OutlinedButton(onClick = onSecondaryAction) {
                        Text(secondaryActionLabel)
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BudgetCalculatorDialog(
    initialAmount: Double?,
    initialCurrency: String,
    feasibility: FeasibilityResult,
    previewPlan: BudgetCalculatorPlan?,
    timeline: List<ScheduledGoalBlock>,
    isLoading: Boolean,
    errorMessage: String?,
    availableCurrencies: List<String>,
    onDismiss: () -> Unit,
    onBudgetChange: (Double, String) -> Unit,
    onApply: (Double, String) -> Unit,
    onApplySuggestion: (FeasibilitySuggestion, Double, String) -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var budgetText by remember(initialAmount, initialCurrency) {
        mutableStateOf(if (initialAmount != null && initialAmount > 0) String.format("%,.2f", initialAmount) else "")
    }
    var selectedCurrency by remember(initialCurrency) { mutableStateOf(initialCurrency) }
    var currencyExpanded by remember { mutableStateOf(false) }
    var isAmountFocused by remember { mutableStateOf(false) }
    var selectedGoalBlock by remember { mutableStateOf<ScheduledGoalBlock?>(null) }
    val parsedAmount = budgetText.replace(",", "").toDoubleOrNull()
    val inputError = if (budgetText.isNotEmpty() && parsedAmount == null) "Enter a valid amount" else null
    val canApply = parsedAmount != null &&
        parsedAmount > 0 &&
        feasibility.isFeasible &&
        previewPlan != null &&
        !isLoading

    LaunchedEffect(budgetText, selectedCurrency) {
        val amount = parsedAmount ?: 0.0
        onBudgetChange(amount, selectedCurrency)
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = "Budget Plan",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )

            if (isLoading) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = "Monthly Savings Budget",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ExposedDropdownMenuBox(
                        expanded = currencyExpanded,
                        onExpandedChange = { currencyExpanded = it }
                    ) {
                        OutlinedTextField(
                            value = selectedCurrency,
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("Currency") },
                            modifier = Modifier
                                .width(140.dp)
                                .menuAnchor(MenuAnchorType.PrimaryNotEditable),
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = currencyExpanded) },
                            singleLine = true
                        )
                        ExposedDropdownMenu(
                            expanded = currencyExpanded,
                            onDismissRequest = { currencyExpanded = false }
                        ) {
                            availableCurrencies.forEach { currency ->
                                DropdownMenuItem(
                                    text = { Text(currency) },
                                    onClick = {
                                        selectedCurrency = currency
                                        currencyExpanded = false
                                    }
                                )
                            }
                        }
                    }
                    OutlinedTextField(
                        value = budgetText,
                        onValueChange = { newValue ->
                            val filtered = newValue.filter { it.isDigit() || it == '.' || it == ',' }
                            val withoutCommas = filtered.replace(",", "")
                            if (withoutCommas.count { it == '.' } <= 1) budgetText = withoutCommas
                        },
                        label = { Text("Amount") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        isError = inputError != null,
                        supportingText = inputError?.let { { Text(it) } },
                        singleLine = true,
                        modifier = Modifier
                            .weight(1f)
                            .onFocusChanged { focusState ->
                                if (isAmountFocused && !focusState.isFocused) {
                                    // Format on blur
                                    val amount = budgetText.replace(",", "").toDoubleOrNull()
                                    if (amount != null) {
                                        budgetText = String.format("%,.2f", amount)
                                    }
                                }
                                isAmountFocused = focusState.isFocused
                            }
                    )
                }
            }

            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                )
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
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
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    if (!feasibility.isFeasible) {
                        Text(
                            text = "Minimum required: ${formatCurrency(feasibility.minimumRequired, selectedCurrency)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Button(onClick = {
                            budgetText = String.format("%,.2f", feasibility.minimumRequired)
                        }) {
                            Icon(
                                imageVector = Icons.Default.ArrowUpward,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp)
                            )
                            Spacer(modifier = Modifier.width(6.dp))
                            Text("Use Minimum ${formatCurrency(feasibility.minimumRequired, selectedCurrency)}")
                        }
                    }
                }
            }

            if (!feasibility.isFeasible && feasibility.infeasibleGoals.isNotEmpty()) {
                InfeasibleGoalsCard(goals = feasibility.infeasibleGoals)
            }

            if (!feasibility.isFeasible && feasibility.suggestions.isNotEmpty()) {
                SuggestionsCard(
                    suggestions = feasibility.suggestions,
                    onSuggestionSelected = { suggestion ->
                        val amount = parsedAmount ?: 0.0
                        when (suggestion) {
                            is FeasibilitySuggestion.IncreaseBudget -> {
                                budgetText = String.format("%,.2f", suggestion.to)
                            }
                            else -> onApplySuggestion(suggestion, amount, selectedCurrency)
                        }
                    }
                )
            }

            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                )
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "This Month's Contribution",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    val contributions = previewPlan?.schedule?.firstOrNull()?.contributions.orEmpty()
                    if (contributions.isEmpty()) {
                        Text(
                            text = "Enter a budget to preview contributions.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        contributions.forEach { contribution ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(
                                    text = contribution.goalName,
                                    style = MaterialTheme.typography.bodySmall
                                )
                                Text(
                                    text = formatCurrency(contribution.amount, selectedCurrency),
                                    style = MaterialTheme.typography.bodySmall,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                        }
                    }
                }
            }

            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                )
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "Upcoming Schedule",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    if (timeline.isEmpty()) {
                        Text(
                            text = "Timeline preview will appear here.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        TimelineBar(blocks = timeline)

                        timeline.forEach { block ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { selectedGoalBlock = block }
                                    .padding(vertical = 4.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Row(
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    modifier = Modifier.weight(1f)
                                ) {
                                    if (block.emoji != null) {
                                        Text(text = block.emoji)
                                    }
                                    Column {
                                        Row(
                                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Text(
                                                text = block.goalName,
                                                style = MaterialTheme.typography.bodySmall,
                                                fontWeight = FontWeight.Medium
                                            )
                                            if (block.isComplete) {
                                                Icon(
                                                    imageVector = Icons.Default.CheckCircle,
                                                    contentDescription = null,
                                                    tint = AccessibleGreen,
                                                    modifier = Modifier.size(14.dp)
                                                )
                                            }
                                        }
                                        Text(
                                            text = block.dateRange,
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                        Row(
                                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                                        ) {
                                            Text(
                                                text = "Total: ${formatCurrency(block.totalAmount, selectedCurrency)}",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                            if (block.paymentCount > 0) {
                                                val monthlyAmount = block.totalAmount / block.paymentCount
                                                Row(
                                                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                                                    verticalAlignment = Alignment.CenterVertically
                                                ) {
                                                    Icon(
                                                        imageVector = Icons.Default.CalendarMonth,
                                                        contentDescription = null,
                                                        modifier = Modifier.size(12.dp),
                                                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                                                    )
                                                    Text(
                                                        text = "${formatCurrency(monthlyAmount, selectedCurrency)}/mo",
                                                        style = MaterialTheme.typography.labelSmall,
                                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                                Column(
                                    horizontalAlignment = Alignment.End,
                                    verticalArrangement = Arrangement.spacedBy(2.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.ChevronRight,
                                        contentDescription = "View details",
                                        modifier = Modifier.size(16.dp),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                    Text(
                                        text = "${block.paymentCount} payments",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
            }

            if (errorMessage != null) {
                Text(
                    text = errorMessage,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }

            if (!canApply && !feasibility.isFeasible) {
                Text(
                    text = "Resolve budget shortfall to save",
                    style = MaterialTheme.typography.labelSmall,
                    color = AccessibleYellow,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
            }

            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.08f)
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier.padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.Info,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = "Saving will update contribution amounts for all active goals.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedButton(
                    onClick = onDismiss,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Cancel")
                }
                Button(
                    onClick = {
                        val amount = parsedAmount ?: 0.0
                        if (amount > 0) onApply(amount, selectedCurrency)
                    },
                    enabled = canApply,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Save Budget Plan")
                }
            }

        }
    }

    // Show payment schedule sheet when a goal block is selected
    selectedGoalBlock?.let { block ->
        GoalPaymentScheduleSheet(
            block = block,
            plan = previewPlan,
            currency = selectedCurrency,
            onDismiss = { selectedGoalBlock = null }
        )
    }
}

@Composable
private fun InfeasibleGoalsCard(
    goals: List<InfeasibleGoal>,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.3f)
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "Budget Shortfall",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            goals.forEach { goal ->
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = goal.goalName,
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "Needs ${formatCurrency(goal.requiredMonthly, goal.currency)}/mo",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = "Shortfall: ${formatCurrency(goal.shortfall, goal.currency)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun SuggestionsCard(
    suggestions: List<FeasibilitySuggestion>,
    onSuggestionSelected: (FeasibilitySuggestion) -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.35f)
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "Quick fixes",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            suggestions.forEach { suggestion ->
                if (suggestion is FeasibilitySuggestion.IncreaseBudget) {
                    Button(
                        onClick = { onSuggestionSelected(suggestion) },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(
                            imageVector = suggestionIcon(suggestion),
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = suggestion.title,
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                } else {
                    OutlinedButton(
                        onClick = { onSuggestionSelected(suggestion) },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(
                            imageVector = suggestionIcon(suggestion),
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = suggestion.title,
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TimelineBar(
    blocks: List<ScheduledGoalBlock>,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(10.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        blocks.forEachIndexed { index, block ->
            Box(
                modifier = Modifier
                    .weight(block.paymentCount.toFloat())
                    .height(8.dp)
                    .background(timelineColor(index), shape = MaterialTheme.shapes.small)
            )
        }
    }
}

@Composable
private fun timelineColor(index: Int): Color {
    val palette = listOf(
        MaterialTheme.colorScheme.primary.copy(alpha = 0.6f),
        MaterialTheme.colorScheme.tertiary.copy(alpha = 0.6f),
        MaterialTheme.colorScheme.secondary.copy(alpha = 0.6f),
        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.6f)
    )
    return palette[index % palette.size]
}

private fun formatCurrency(amount: Double, currency: String): String {
    return "$currency ${String.format("%,.2f", amount)}"
}

private fun feasibilityIcon(level: FeasibilityLevel) = when (level) {
    FeasibilityLevel.ACHIEVABLE -> Icons.Default.CheckCircle
    FeasibilityLevel.AT_RISK -> Icons.Default.Warning
    FeasibilityLevel.CRITICAL -> Icons.Default.Cancel
}

private fun feasibilityColor(level: FeasibilityLevel): Color = when (level) {
    FeasibilityLevel.ACHIEVABLE -> AccessibleGreen
    FeasibilityLevel.AT_RISK -> AccessibleYellow
    FeasibilityLevel.CRITICAL -> AccessibleRed
}

private fun suggestionIcon(suggestion: FeasibilitySuggestion) = when (suggestion) {
    is FeasibilitySuggestion.IncreaseBudget -> Icons.Default.ArrowUpward
    is FeasibilitySuggestion.ExtendDeadline -> Icons.Default.Event
    is FeasibilitySuggestion.ReduceTarget -> Icons.Default.RemoveCircle
    is FeasibilitySuggestion.EditGoal -> Icons.Default.Edit
}

/**
 * Bottom sheet showing detailed payment schedule for a specific goal.
 * Matches iOS GoalPaymentScheduleSheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoalPaymentScheduleSheet(
    block: ScheduledGoalBlock,
    plan: BudgetCalculatorPlan?,
    currency: String,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    val goalPayments: List<Pair<ScheduledPayment, GoalContribution>> = remember(plan, block.goalId) {
        plan?.schedule?.mapNotNull { payment ->
            payment.contributions.firstOrNull { it.goalId == block.goalId }?.let { contribution ->
                payment to contribution
            }
        } ?: emptyList()
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 24.dp)
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (block.emoji != null) {
                        Text(
                            text = block.emoji,
                            style = MaterialTheme.typography.headlineMedium
                        )
                    }
                    Text(
                        text = block.goalName,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
                }
                TextButton(onClick = onDismiss) {
                    Text("Done")
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Summary Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                )
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text(
                                text = block.goalName,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                text = block.dateRange,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        if (block.isComplete) {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = Icons.Default.CheckCircle,
                                    contentDescription = null,
                                    tint = AccessibleGreen,
                                    modifier = Modifier.size(16.dp)
                                )
                                Text(
                                    text = "Completes",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = AccessibleGreen
                                )
                            }
                        }
                    }

                    HorizontalDivider()

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column {
                            Text(
                                text = "Total",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Text(
                                text = formatCurrency(block.totalAmount, currency),
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                text = "Payments",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Text(
                                text = "${block.paymentCount}",
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                        if (block.paymentCount > 0) {
                            Column(horizontalAlignment = Alignment.End) {
                                Text(
                                    text = "Per Month",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                val monthlyAmount = block.totalAmount / block.paymentCount
                                Text(
                                    text = formatCurrency(monthlyAmount, currency),
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Payment Schedule Section
            Text(
                text = "Payment Schedule",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )

            Spacer(modifier = Modifier.height(8.dp))

            if (goalPayments.isEmpty()) {
                Text(
                    text = "No payments scheduled.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.height(300.dp)
                ) {
                    items(goalPayments) { (payment, contribution) ->
                        PaymentScheduleRow(
                            payment = payment,
                            contribution = contribution,
                            currency = currency
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PaymentScheduleRow(
    payment: ScheduledPayment,
    contribution: GoalContribution,
    currency: String
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface
        ),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = payment.formattedDateFull,
                    style = MaterialTheme.typography.bodyMedium
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Payment #${payment.paymentNumber}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (contribution.isGoalComplete) {
                        Text(
                            text = "Complete",
                            style = MaterialTheme.typography.labelSmall,
                            color = AccessibleGreen,
                            modifier = Modifier
                                .background(
                                    color = AccessibleGreen.copy(alpha = 0.1f),
                                    shape = RoundedCornerShape(4.dp)
                                )
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        )
                    }
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    text = formatCurrency(contribution.amount, currency),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    text = "Running: ${formatCurrency(contribution.runningTotal, currency)}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
