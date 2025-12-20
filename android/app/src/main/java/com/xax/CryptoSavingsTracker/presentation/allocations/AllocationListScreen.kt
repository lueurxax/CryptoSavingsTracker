package com.xax.CryptoSavingsTracker.presentation.allocations

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
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
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
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.presentation.navigation.Screen
import com.xax.CryptoSavingsTracker.presentation.theme.BitcoinOrange
import com.xax.CryptoSavingsTracker.presentation.theme.EthereumBlue
import com.xax.CryptoSavingsTracker.presentation.theme.StablecoinGreen
import kotlin.math.min

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AllocationListScreen(
    navController: NavController,
    viewModel: AllocationListViewModel = hiltViewModel()
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
                title = { Text("Allocations") },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        },
        floatingActionButton = {
            uiState.goal?.let { goal ->
                FloatingActionButton(
                    onClick = {
                        navController.navigate(Screen.AddAllocation.createRoute(goal.id))
                    }
                ) {
                    Icon(Icons.Default.Add, contentDescription = "Add Allocation")
                }
            }
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
                    AllocationListContent(
                        goal = uiState.goal!!,
                        allocations = uiState.allocations,
                        totalAllocated = uiState.totalAllocated,
                        totalFunded = uiState.totalFunded,
                        hasOverAllocatedAssets = uiState.hasOverAllocatedAssets,
                        onDeleteAllocation = viewModel::requestDeleteAllocation,
                        onAddAllocation = {
                            navController.navigate(Screen.AddAllocation.createRoute(uiState.goal!!.id))
                        }
                    )
                }
            }
        }

        // Delete confirmation dialog
        uiState.showDeleteConfirmation?.let { allocation ->
            val assetName = uiState.allocations.find { it.allocation.id == allocation.id }?.assetDisplayName ?: "this asset"
            AlertDialog(
                onDismissRequest = viewModel::dismissDeleteConfirmation,
                title = { Text("Delete Allocation") },
                text = {
                    Text("Remove allocation of ${String.format("%,.2f", allocation.amount)} from $assetName?")
                },
                confirmButton = {
                    TextButton(onClick = viewModel::confirmDeleteAllocation) {
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
private fun AllocationListContent(
    goal: com.xax.CryptoSavingsTracker.domain.model.Goal,
    allocations: List<AllocationWithDetails>,
    totalAllocated: Double,
    totalFunded: Double,
    hasOverAllocatedAssets: Boolean,
    onDeleteAllocation: (com.xax.CryptoSavingsTracker.domain.model.Allocation) -> Unit,
    onAddAllocation: () -> Unit
) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Over-allocation warning banner
        if (hasOverAllocatedAssets) {
            item {
                OverAllocationWarningCard()
            }
        }

        // Summary card
        item {
            AllocationSummaryCard(
                goalName = goal.name,
                goalCurrency = goal.currency,
                targetAmount = goal.targetAmount,
                totalAllocated = totalAllocated,
                totalFunded = totalFunded
            )
        }

        if (allocations.isEmpty()) {
            item {
                EmptyAllocationsState(onAddAllocation = onAddAllocation)
            }
        } else {
            items(
                items = allocations,
                key = { it.allocation.id }
            ) { allocationWithDetails ->
                AllocationCard(
                    allocationWithDetails = allocationWithDetails,
                    goalCurrency = goal.currency,
                    onDelete = { onDeleteAllocation(allocationWithDetails.allocation) }
                )
            }
        }
    }
}

@Composable
private fun OverAllocationWarningCard() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Over-Allocated Assets",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onErrorContainer
                )
                Text(
                    text = "Some assets have allocations exceeding their balance. Please reduce allocations or add funds.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.8f)
                )
            }
        }
    }
}

@Composable
private fun AllocationSummaryCard(
    goalName: String,
    goalCurrency: String,
    targetAmount: Double,
    totalAllocated: Double,
    totalFunded: Double
) {
    // Progress is based on funded amount (actual backing), not just allocated
    val progress = if (targetAmount > 0) {
        min(totalFunded / targetAmount, 1.0)
    } else {
        0.0
    }
    val progressPercent = (progress * 100).toInt()
    val hasUnderfunding = totalFunded < totalAllocated - 0.01

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
                text = goalName,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Allocated: $goalCurrency ${String.format("%,.2f", totalAllocated)} / ${String.format("%,.2f", targetAmount)}",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f)
            )
            if (hasUnderfunding) {
                Text(
                    text = "Funded: $goalCurrency ${String.format("%,.2f", totalFunded)}",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.error
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            LinearProgressIndicator(
                progress = { progress.toFloat() },
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "$progressPercent% funded",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
            )
        }
    }
}

@Composable
private fun AllocationCard(
    allocationWithDetails: AllocationWithDetails,
    goalCurrency: String,
    onDelete: () -> Unit
) {
    val allocation = allocationWithDetails.allocation
    val asset = allocationWithDetails.asset
    val currencyColor = getCurrencyColor(asset?.currency)

    // Visual warning states
    val isOverAllocated = allocationWithDetails.isAssetOverAllocated
    val isUnderfunded = allocationWithDetails.isUnderfunded
    val hasWarning = isOverAllocated || isUnderfunded

    val cardContainerColor = when {
        isOverAllocated -> MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.3f)
        isUnderfunded -> MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.3f)
        else -> MaterialTheme.colorScheme.surface
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        colors = CardDefaults.cardColors(containerColor = cardContainerColor)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.weight(1f)
                ) {
                    Icon(
                        imageVector = Icons.Default.AccountBalance,
                        contentDescription = null,
                        tint = currencyColor,
                        modifier = Modifier.size(32.dp)
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Column {
                        Text(
                            text = allocationWithDetails.assetDisplayName,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = "Balance: ${asset?.currency ?: "?"} ${String.format("%,.2f", allocationWithDetails.assetBalance)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(
                        horizontalAlignment = Alignment.End
                    ) {
                        Text(
                            text = "$goalCurrency ${String.format("%,.2f", allocation.amount)}",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = if (hasWarning) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
                        )
                        if (isUnderfunded) {
                            Text(
                                text = "Funded: ${String.format("%,.2f", allocationWithDetails.fundedAmount)}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error
                            )
                        }
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    IconButton(onClick = onDelete) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = "Delete allocation",
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                }
            }

            // Warning message for over-allocated assets
            if (isOverAllocated) {
                Spacer(modifier = Modifier.height(8.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.Warning,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = "Asset over-allocated by ${String.format("%,.2f", allocationWithDetails.assetTotalAllocated - allocationWithDetails.assetBalance)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
        }
    }
}

@Composable
private fun EmptyAllocationsState(
    onAddAllocation: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = Icons.Default.AccountBalance,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "No allocations yet",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Allocate assets to fund this goal",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(16.dp))
            TextButton(onClick = onAddAllocation) {
                Icon(Icons.Default.Add, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Add Allocation")
            }
        }
    }
}

private fun getCurrencyColor(currency: String?) = when (currency?.uppercase()) {
    "BTC" -> BitcoinOrange
    "ETH" -> EthereumBlue
    "USDT", "USDC", "DAI" -> StablecoinGreen
    else -> EthereumBlue
}
