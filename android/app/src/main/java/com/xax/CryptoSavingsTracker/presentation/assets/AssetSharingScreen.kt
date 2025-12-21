package com.xax.CryptoSavingsTracker.presentation.assets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
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
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.presentation.common.AmountFormatters
import com.xax.CryptoSavingsTracker.presentation.navigation.Screen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssetSharingScreen(
    navController: NavController,
    viewModel: AssetSharingViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(uiState.asset?.displayName() ?: "Asset Sharing") },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(
                        onClick = viewModel::showAddAllocation,
                        enabled = !uiState.isLoading
                    ) {
                        Icon(Icons.Default.Add, contentDescription = "Add Allocation")
                    }
                }
            )
        }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            when {
                uiState.isLoading -> {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                }
                uiState.error != null -> {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Text(
                            text = uiState.error ?: "Failed to load",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.error
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        Button(onClick = viewModel::refresh) { Text("Retry") }
                    }
                }
                uiState.asset == null -> {
                    Text(
                        text = "Asset not found",
                        modifier = Modifier.align(Alignment.Center),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                else -> {
                    AssetSharingContent(
                        uiState = uiState,
                        onEditAllocation = { goalId, allocationId ->
                            navController.navigate(Screen.EditAllocation.createRoute(goalId, allocationId))
                        },
                        modifier = Modifier.fillMaxSize()
                    )
                }
            }

            if (uiState.showAddAllocationDialog) {
                AddAllocationDialog(
                    uiState = uiState,
                    onDismiss = viewModel::dismissAddAllocation,
                    onSelectGoal = viewModel::selectGoal,
                    onAmountChange = viewModel::setAmountInput,
                    onMax = viewModel::setMaxAmount,
                    onSave = viewModel::saveAllocation
                )
            }
        }
    }
}

@Composable
private fun AssetSharingContent(
    uiState: AssetSharingUiState,
    onEditAllocation: (goalId: String, allocationId: String) -> Unit,
    modifier: Modifier = Modifier
) {
    val asset = uiState.asset ?: return
    val isCrypto = asset.isCryptoAsset

    LazyColumn(
        modifier = modifier.padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("assetSharingSummary"),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.35f))
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Default.Warning,
                            contentDescription = null,
                            tint = Color(0xFFFF9800)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = "Unallocated",
                            style = MaterialTheme.typography.titleMedium,
                            color = Color(0xFFFF9800)
                        )
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = AmountFormatters.formatDisplayCurrencyAmount(uiState.unallocatedAmount, asset.currency, isCrypto = isCrypto),
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "Total: ${AmountFormatters.formatDisplayCurrencyAmount(uiState.totalBalance, asset.currency, isCrypto = isCrypto)} • " +
                            "Allocated: ${AmountFormatters.formatDisplayCurrencyAmount(uiState.totalAllocated, asset.currency, isCrypto = isCrypto)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (uiState.isOverAllocated) {
                        Spacer(modifier = Modifier.height(6.dp))
                        Text(
                            text = "Warning: allocations exceed balance.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                }
            }
        }

        item {
            Text(
                text = "Allocations",
                style = MaterialTheme.typography.titleMedium
            )
        }

        if (uiState.allocations.isEmpty()) {
            item {
                Text(
                    text = "No allocations yet. Add one to assign this asset to a goal.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        } else {
            items(uiState.allocations, key = { it.allocationId }) { row ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("assetSharingAllocation_${row.allocationId}"),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(text = row.goalName, style = MaterialTheme.typography.titleMedium)
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = AmountFormatters.formatDisplayCurrencyAmount(row.amount, asset.currency, isCrypto = isCrypto),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        IconButton(onClick = { onEditAllocation(row.goalId, row.allocationId) }) {
                            Icon(Icons.Default.Edit, contentDescription = "Edit Allocation")
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddAllocationDialog(
    uiState: AssetSharingUiState,
    onDismiss: () -> Unit,
    onSelectGoal: (String) -> Unit,
    onAmountChange: (String) -> Unit,
    onMax: () -> Unit,
    onSave: () -> Unit
) {
    val goals = uiState.activeGoals
    val selectedGoal = goals.firstOrNull { it.id == uiState.selectedGoalId }
    var isExpanded by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Allocation") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                ExposedDropdownMenuBox(
                    expanded = isExpanded,
                    onExpandedChange = { isExpanded = it },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    OutlinedTextField(
                        value = selectedGoal?.name ?: "",
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Goal") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = isExpanded) },
                        modifier = Modifier
                            .menuAnchor()
                            .fillMaxWidth()
                            .testTag("assetSharingGoalPicker")
                    )
                    ExposedDropdownMenu(
                        expanded = isExpanded,
                        onDismissRequest = { isExpanded = false }
                    ) {
                        goals.forEach { goal ->
                            DropdownMenuItem(
                                text = { Text(goal.name) },
                                onClick = {
                                    onSelectGoal(goal.id)
                                    isExpanded = false
                                }
                            )
                        }
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedTextField(
                        value = uiState.amountInput,
                        onValueChange = onAmountChange,
                        label = { Text("Amount") },
                        modifier = Modifier
                            .weight(1f)
                            .testTag("assetSharingAmountInput"),
                        singleLine = true
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    TextButton(onClick = onMax, enabled = !uiState.isSaving) { Text("MAX") }
                }

                if (uiState.amountError != null) {
                    Text(
                        text = uiState.amountError ?: "",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onSave, enabled = !uiState.isSaving) { Text("Save") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !uiState.isSaving) { Text("Cancel") }
        }
    )
}

