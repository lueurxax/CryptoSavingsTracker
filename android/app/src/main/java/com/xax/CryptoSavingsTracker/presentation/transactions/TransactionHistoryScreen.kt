package com.xax.CryptoSavingsTracker.presentation.transactions

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
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.presentation.navigation.Screen
import com.xax.CryptoSavingsTracker.presentation.theme.DepositGreen
import com.xax.CryptoSavingsTracker.presentation.theme.WithdrawalRed

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TransactionHistoryScreen(
    navController: NavController,
    viewModel: TransactionListViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var transactionToDelete by remember { mutableStateOf<Transaction?>(null) }

    LaunchedEffect(state.error) {
        state.error?.let { error ->
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(
                            text = "Transaction History",
                            style = MaterialTheme.typography.titleLarge
                        )
                        if (state.assetName.isNotEmpty()) {
                            Text(
                                text = state.assetName,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = {
                    navController.navigate(Screen.AddTransaction.createRoute(viewModel.getAssetId()))
                }
            ) {
                Icon(Icons.Default.Add, contentDescription = "Add Transaction")
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            when {
                state.isLoading -> {
                    CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center)
                    )
                }
                state.transactions.isEmpty() -> {
                    EmptyTransactionsState(
                        onAddTransaction = {
                            navController.navigate(Screen.AddTransaction.createRoute(viewModel.getAssetId()))
                        }
                    )
                }
                else -> {
                    TransactionList(
                        transactions = state.transactions,
                        currency = state.assetCurrency,
                        totalBalance = state.totalBalance,
                        depositCount = state.depositCount,
                        withdrawalCount = state.withdrawalCount,
                        onEditTransaction = { tx ->
                            if (tx.source == TransactionSource.MANUAL) {
                                navController.navigate(Screen.EditTransaction.createRoute(tx.id))
                            }
                        },
                        onDeleteTransaction = { transactionToDelete = it }
                    )
                }
            }
        }
    }

    // Delete confirmation dialog
    transactionToDelete?.let { transaction ->
        AlertDialog(
            onDismissRequest = { transactionToDelete = null },
            title = { Text("Delete Transaction") },
            text = {
                Text("Are you sure you want to delete this ${if (transaction.isDeposit) "deposit" else "withdrawal"} of ${formatAmount(transaction.absoluteAmount, state.assetCurrency)}?")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.deleteTransaction(transaction)
                        transactionToDelete = null
                    }
                ) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { transactionToDelete = null }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun TransactionList(
    transactions: List<Transaction>,
    currency: String,
    totalBalance: Double,
    depositCount: Int,
    withdrawalCount: Int,
    onEditTransaction: (Transaction) -> Unit,
    onDeleteTransaction: (Transaction) -> Unit
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Summary card
        item {
            SummaryCard(
                totalBalance = totalBalance,
                currency = currency,
                depositCount = depositCount,
                withdrawalCount = withdrawalCount
            )
            Spacer(modifier = Modifier.height(8.dp))
        }

        items(
            items = transactions,
            key = { it.id }
        ) { transaction ->
            TransactionCard(
                transaction = transaction,
                currency = currency,
                onEdit = { onEditTransaction(transaction) },
                onDelete = { onDeleteTransaction(transaction) }
            )
        }
    }
}

@Composable
private fun SummaryCard(
    totalBalance: Double,
    currency: String,
    depositCount: Int,
    withdrawalCount: Int
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = "Net Balance",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
            Text(
                text = formatAmount(totalBalance, currency),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = if (totalBalance >= 0) DepositGreen else WithdrawalRed
            )
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Default.ArrowDownward,
                        contentDescription = null,
                        tint = DepositGreen,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = "$depositCount deposits",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Default.ArrowUpward,
                        contentDescription = null,
                        tint = WithdrawalRed,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = "$withdrawalCount withdrawals",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        }
    }
}

@Composable
private fun TransactionCard(
    transaction: Transaction,
    currency: String,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    val isDeposit = transaction.isDeposit
    val amountColor = if (isDeposit) DepositGreen else WithdrawalRed
    val icon = if (isDeposit) Icons.Default.ArrowDownward else Icons.Default.ArrowUpward

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (transaction.source == TransactionSource.MANUAL) {
                    Modifier.clickable(onClick = onEdit)
                } else {
                    Modifier
                }
            )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Amount icon
            Icon(
                imageVector = icon,
                contentDescription = if (isDeposit) "Deposit" else "Withdrawal",
                tint = amountColor,
                modifier = Modifier.size(32.dp)
            )

            Spacer(modifier = Modifier.width(12.dp))

            // Transaction details
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = formatAmount(transaction.absoluteAmount, currency),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = amountColor
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    SourceBadge(source = transaction.source)
                }
                Text(
                    text = transaction.formattedDate(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                transaction.counterparty?.let { counterparty ->
                    Text(
                        text = if (isDeposit) "From: $counterparty" else "To: $counterparty",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                transaction.comment?.let { comment ->
                    Text(
                        text = comment,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2
                    )
                }
            }

            // Actions (only for manual transactions)
            if (transaction.source == TransactionSource.MANUAL) {
                IconButton(onClick = onEdit) {
                    Icon(
                        Icons.Default.Edit,
                        contentDescription = "Edit",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                IconButton(onClick = onDelete) {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = "Delete",
                        tint = MaterialTheme.colorScheme.error
                    )
                }
            }
        }
    }
}

@Composable
private fun SourceBadge(source: TransactionSource) {
    val (text, color) = when (source) {
        TransactionSource.MANUAL -> "Manual" to MaterialTheme.colorScheme.secondary
        TransactionSource.ON_CHAIN -> "On-Chain" to MaterialTheme.colorScheme.tertiary
        TransactionSource.IMPORT -> "Imported" to MaterialTheme.colorScheme.primary
    }

    Card(
        colors = CardDefaults.cardColors(
            containerColor = color.copy(alpha = 0.2f)
        )
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            color = color,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
        )
    }
}

@Composable
private fun EmptyTransactionsState(onAddTransaction: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            Icons.Default.Receipt,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "No Transactions Yet",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Add your first transaction to start tracking your balance",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(24.dp))
        FloatingActionButton(
            onClick = onAddTransaction
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Default.Add, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Add Transaction")
            }
        }
    }
}

private fun formatAmount(amount: Double, currency: String): String {
    return "$currency ${String.format("%.8f", amount).trimEnd('0').trimEnd('.')}"
}
