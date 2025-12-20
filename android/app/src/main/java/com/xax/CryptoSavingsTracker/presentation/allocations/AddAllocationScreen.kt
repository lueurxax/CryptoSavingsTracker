package com.xax.CryptoSavingsTracker.presentation.allocations

import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.presentation.theme.BitcoinOrange
import com.xax.CryptoSavingsTracker.presentation.theme.EthereumBlue
import com.xax.CryptoSavingsTracker.presentation.theme.StablecoinGreen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddAllocationScreen(
    navController: NavController,
    viewModel: AddAllocationViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Navigate back when saved
    LaunchedEffect(uiState.isSaved) {
        if (uiState.isSaved) {
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
                title = { Text("Add Allocation") },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
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
                    AddAllocationContent(
                        goalName = uiState.goal!!.name,
                        availableAssets = uiState.availableAssets,
                        selectedAsset = uiState.selectedAsset,
                        amount = uiState.amount,
                        amountError = uiState.amountError,
                        isSaving = uiState.isSaving,
                        onAssetSelected = viewModel::selectAsset,
                        onAmountChanged = viewModel::updateAmount,
                        onMaxClicked = viewModel::setMaxAmount,
                        onSave = viewModel::saveAllocation
                    )
                }
            }
        }
    }
}

@Composable
private fun AddAllocationContent(
    goalName: String,
    availableAssets: List<AssetForAllocation>,
    selectedAsset: AssetForAllocation?,
    amount: String,
    amountError: String?,
    isSaving: Boolean,
    onAssetSelected: (AssetForAllocation) -> Unit,
    onAmountChanged: (String) -> Unit,
    onMaxClicked: () -> Unit,
    onSave: () -> Unit
) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header
        item {
            Text(
                text = "Allocate funds to \"$goalName\"",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        // Asset selection
        item {
            Text(
                text = "Select an asset",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
        }

        if (availableAssets.isEmpty()) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                    )
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            text = "No assets available",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "Add assets with positive balance to allocate funds",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        } else {
            items(
                items = availableAssets,
                key = { it.asset.id }
            ) { assetForAllocation ->
                AssetSelectionCard(
                    assetForAllocation = assetForAllocation,
                    isSelected = selectedAsset?.asset?.id == assetForAllocation.asset.id,
                    onClick = { onAssetSelected(assetForAllocation) }
                )
            }
        }

    // Amount input (only show if asset is selected)
    if (selectedAsset != null) {
        item {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Allocation amount (${selectedAsset.asset.currency})",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
        }

            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.Top
                ) {
                    OutlinedTextField(
                        value = amount,
                        onValueChange = onAmountChanged,
                        label = { Text("Amount") },
                        placeholder = { Text("Enter amount") },
                        modifier = Modifier.weight(1f),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        isError = amountError != null,
                        supportingText = amountError?.let { { Text(it) } },
                        singleLine = true
                    )
                    TextButton(
                        onClick = onMaxClicked,
                        modifier = Modifier.padding(top = 8.dp)
                    ) {
                        Text("MAX")
                    }
                }
            }

            item {
                Text(
                    text = "Available: ${selectedAsset.asset.currency} ${String.format("%,.2f", selectedAsset.availableBalance)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // Save button
            item {
                Spacer(modifier = Modifier.height(8.dp))
                Button(
                    onClick = onSave,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isSaving && amount.isNotEmpty()
                ) {
                    if (isSaving) {
                        CircularProgressIndicator(
                            modifier = Modifier
                                .size(20.dp)
                                .padding(end = 8.dp),
                            color = MaterialTheme.colorScheme.onPrimary,
                            strokeWidth = 2.dp
                        )
                    }
                    Text("Add Allocation")
                }
            }
        }
    }
}

@Composable
private fun AssetSelectionCard(
    assetForAllocation: AssetForAllocation,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    val asset = assetForAllocation.asset
    val currencyColor = getCurrencyColor(asset.currency)

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        border = if (isSelected) {
            BorderStroke(2.dp, MaterialTheme.colorScheme.primary)
        } else {
            null
        },
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected) {
                MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
            } else {
                MaterialTheme.colorScheme.surface
            }
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
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
                        text = asset.displayName(),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = "Available: ${asset.currency} ${String.format("%,.2f", assetForAllocation.availableBalance)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (assetForAllocation.alreadyAllocated > 0) {
                        Text(
                            text = "Allocated elsewhere: ${String.format("%,.2f", assetForAllocation.alreadyAllocated)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                        )
                    }
                }
            }
            if (isSelected) {
                Icon(
                    imageVector = Icons.Default.Check,
                    contentDescription = "Selected",
                    tint = MaterialTheme.colorScheme.primary
                )
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
