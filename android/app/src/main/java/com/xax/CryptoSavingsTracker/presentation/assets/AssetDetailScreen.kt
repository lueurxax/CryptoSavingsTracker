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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.annotation.VisibleForTesting
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.ChainIds
import com.xax.CryptoSavingsTracker.domain.model.OnChainBalance
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.presentation.theme.BitcoinOrange
import com.xax.CryptoSavingsTracker.presentation.theme.EthereumBlue
import com.xax.CryptoSavingsTracker.presentation.theme.WithdrawalRed
import com.xax.CryptoSavingsTracker.presentation.theme.DepositGreen
import com.xax.CryptoSavingsTracker.presentation.theme.StablecoinGreen
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssetDetailScreen(
    navController: NavController,
    viewModel: AssetDetailViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

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
                title = { Text("Asset Details") },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    uiState.asset?.let { asset ->
                        IconButton(onClick = {
                            navController.navigate(
                                com.xax.CryptoSavingsTracker.presentation.navigation.Screen.EditAsset.createRoute(asset.id)
                            )
                        }) {
                            Icon(Icons.Default.Edit, contentDescription = "Edit")
                        }
                        IconButton(onClick = viewModel::showDeleteConfirmation) {
                            Icon(
                                Icons.Default.Delete,
                                contentDescription = "Delete",
                                tint = MaterialTheme.colorScheme.error
                            )
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
                uiState.asset == null -> {
                    Text(
                        text = "Asset not found",
                        modifier = Modifier.align(Alignment.Center),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                else -> {
                    AssetDetailContent(
                        asset = uiState.asset!!,
                        manualBalance = uiState.manualBalance,
                        currentBalance = uiState.currentBalance,
                        currentBalanceUsd = uiState.currentBalanceUsd,
                        isUsdLoading = uiState.isUsdLoading,
                        usdError = uiState.usdError,
                        onRefreshUsdBalance = viewModel::refreshUsdBalance,
                        recentManualTransactions = uiState.recentManualTransactions,
                        recentOnChainTransactions = uiState.recentOnChainTransactions,
                        onChainBalance = uiState.onChainBalance,
                        isOnChainLoading = uiState.isOnChainLoading,
                        onChainError = uiState.onChainError,
                        isOnChainTransactionsLoading = uiState.isOnChainTransactionsLoading,
                        onChainTransactionsError = uiState.onChainTransactionsError,
                        onRefreshOnChainBalance = viewModel::refreshOnChainBalance,
                        onAddTransaction = {
                            navController.navigate(
                                com.xax.CryptoSavingsTracker.presentation.navigation.Screen.AddTransaction.createRoute(uiState.asset!!.id)
                            )
                        },
                        onViewTransactions = {
                            navController.navigate(
                                com.xax.CryptoSavingsTracker.presentation.navigation.Screen.TransactionHistory.createRoute(uiState.asset!!.id)
                            )
                        }
                    )
                }
            }
        }

        // Delete confirmation dialog
        if (uiState.showDeleteConfirmation) {
            AlertDialog(
                onDismissRequest = viewModel::dismissDeleteConfirmation,
                title = { Text("Delete Asset") },
                text = {
                    Text("Are you sure you want to delete this ${uiState.asset?.currency} asset? This will also remove all associated transactions.")
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
    }
}

@Composable
@VisibleForTesting(otherwise = VisibleForTesting.PRIVATE)
internal fun AssetDetailContent(
    asset: Asset,
    manualBalance: Double,
    currentBalance: Double,
    currentBalanceUsd: Double?,
    isUsdLoading: Boolean,
    usdError: String?,
    onRefreshUsdBalance: () -> Unit,
    recentManualTransactions: List<Transaction>,
    recentOnChainTransactions: List<Transaction>,
    onChainBalance: OnChainBalance?,
    isOnChainLoading: Boolean,
    onChainError: String?,
    isOnChainTransactionsLoading: Boolean,
    onChainTransactionsError: String?,
    onRefreshOnChainBalance: () -> Unit,
    onAddTransaction: () -> Unit,
    onViewTransactions: () -> Unit
) {
    val clipboardManager = LocalClipboardManager.current
    val dateFormatter = remember {
        DateTimeFormatter.ofPattern("MMMM d, yyyy 'at' h:mm a")
            .withZone(ZoneId.systemDefault())
    }
    val currencyColor = getCurrencyColor(asset.currency)
    val hasOnChain = !asset.address.isNullOrBlank() && !asset.chainId.isNullOrBlank()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header with icon and currency
        Row(
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.AccountBalance,
                contentDescription = null,
                tint = currencyColor,
                modifier = Modifier.size(40.dp)
            )
            Spacer(modifier = Modifier.width(16.dp))
            Column {
                Text(
                    text = asset.currency,
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold
                )
                if (!asset.chainId.isNullOrBlank()) {
                    Text(
                        text = ChainIds.displayName(asset.chainId),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        // Balance card (iOS parity: show total balance, including on-chain when available)
        Card(
            modifier = Modifier.fillMaxWidth(),
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
                        text = "Balance",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    IconButton(onClick = if (hasOnChain) onRefreshOnChainBalance else onRefreshUsdBalance) {
                        Icon(
                            imageVector = Icons.Default.Refresh,
                            contentDescription = if (hasOnChain) "Refresh balance" else "Refresh USD value",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                if (hasOnChain && isOnChainLoading && onChainBalance == null) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp))
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            text = "Fetching on-chain balance…",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                } else {
                    Text(
                        text = "${String.format("%,.6f", currentBalance)} ${asset.currency}",
                        style = MaterialTheme.typography.displaySmall,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.testTag("assetDetailCurrentBalance"),
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }

                when {
                    currentBalanceUsd != null -> {
                        Text(
                            text = "≈ $${String.format("%,.2f", currentBalanceUsd)} USD",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    isUsdLoading -> {
                        Text(
                            text = "Fetching USD rate…",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    usdError != null -> {
                        Text(
                            text = usdError,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                    else -> {
                        Text(
                            text = "USD value unavailable",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                if (hasOnChain) {
                    Spacer(modifier = Modifier.height(6.dp))
                    if (onChainBalance != null) {
                        val chainPart = String.format("%,.6f", onChainBalance.balance)
                        val manualPart = String.format("%,.6f", manualBalance)
                        Text(
                            text = "Chain: $chainPart • Manual: $manualPart",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            text = "Fetched: ${dateFormatter.format(Instant.ofEpochMilli(onChainBalance.fetchedAtMillis))}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (onChainBalance.isStale) {
                            Text(
                                text = "Showing cached value (stale)",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    if (isOnChainLoading && onChainBalance != null) {
                        Text(
                            text = "Refreshing…",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    if (onChainError != null) {
                        Text(
                            text = onChainError,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                }
            }
        }

        // Address section (if crypto)
        if (!asset.address.isNullOrBlank()) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp)
                ) {
                    Text(
                        text = "Wallet Address",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = asset.address,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(
                            onClick = {
                                clipboardManager.setText(AnnotatedString(asset.address))
                            }
                        ) {
                            Icon(
                                Icons.Default.ContentCopy,
                                contentDescription = "Copy address"
                            )
                        }
                    }
                }
            }
        }

        // Info card
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp)
            ) {
                Text(
                    text = "Information",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.height(12.dp))

                DetailRow("Type", if (asset.isCryptoAsset) "Cryptocurrency" else "Fiat Account")
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

                if (!asset.chainId.isNullOrBlank()) {
                    DetailRow("Network", ChainIds.displayName(asset.chainId))
                    HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                }

                if (hasOnChain && manualBalance != 0.0) {
                    DetailRow("Manual Transactions", String.format("%,.6f", manualBalance))
                    HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                }

                DetailRow(
                    "Created",
                    dateFormatter.format(Instant.ofEpochMilli(asset.createdAt))
                )
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

                DetailRow(
                    "Last Updated",
                    dateFormatter.format(Instant.ofEpochMilli(asset.updatedAt))
                )
            }
        }

        // Recent Transactions section (matches iOS - combined list)
        val recentTransactions = remember(recentManualTransactions, recentOnChainTransactions) {
            (recentManualTransactions + recentOnChainTransactions)
                .sortedByDescending { it.dateMillis }
                .take(3)
        }

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Recent Transactions",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (hasOnChain) {
                            IconButton(onClick = onRefreshOnChainBalance) {
                                Icon(
                                    imageVector = Icons.Default.Refresh,
                                    contentDescription = "Refresh on-chain data",
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                        TextButton(onClick = onViewTransactions) {
                            Text("View All")
                        }
                    }
                }
                Spacer(modifier = Modifier.height(16.dp))
                if (recentTransactions.isEmpty()) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            text = if (hasOnChain) {
                                "No transactions yet. Tap refresh to load on-chain history or add a manual transaction."
                            } else {
                                "No transactions yet"
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (hasOnChain && isOnChainTransactionsLoading) {
                            Spacer(modifier = Modifier.height(8.dp))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                CircularProgressIndicator(modifier = Modifier.size(18.dp))
                                Spacer(modifier = Modifier.width(10.dp))
                                Text(
                                    text = "Fetching on-chain transactions…",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                        if (hasOnChain && onChainTransactionsError != null) {
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = onChainTransactionsError,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error
                            )
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        TextButton(onClick = onAddTransaction) {
                            Text("Add Transaction")
                        }
                    }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        recentTransactions.forEach { tx ->
                            TransactionPreviewRow(
                                transaction = tx,
                                currency = asset.currency
                            )
                        }
                        Spacer(modifier = Modifier.height(4.dp))
                        TextButton(onClick = onAddTransaction) {
                            Text("Add Transaction")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TransactionPreviewRow(
    transaction: Transaction,
    currency: String
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = if (transaction.isDeposit) "Deposit" else "Withdrawal",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = transaction.formattedDate(),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            val sourceLabel = when (transaction.source) {
                TransactionSource.MANUAL -> "Manual"
                TransactionSource.ON_CHAIN -> "On-chain"
                TransactionSource.IMPORT -> "Imported"
            }
            Text(
                text = sourceLabel,
                style = MaterialTheme.typography.bodySmall,
                color = if (transaction.source == TransactionSource.ON_CHAIN) {
                    MaterialTheme.colorScheme.tertiary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                }
            )
        }
        val sign = if (transaction.isDeposit) "+" else "-"
        val color = if (transaction.isDeposit) DepositGreen else WithdrawalRed
        Text(
            text = "$sign${String.format("%,.4f", transaction.absoluteAmount)} $currency",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
            color = color
        )
    }
}

@Composable
private fun DetailRow(
    label: String,
    value: String
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
            fontWeight = FontWeight.Medium
        )
    }
}

private fun getCurrencyColor(currency: String) = when (currency.uppercase()) {
    "BTC" -> BitcoinOrange
    "ETH" -> EthereumBlue
    "USDT", "USDC", "DAI" -> StablecoinGreen
    else -> EthereumBlue
}
