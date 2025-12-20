package com.xax.CryptoSavingsTracker.presentation.transactions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
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
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.presentation.theme.DepositGreen
import com.xax.CryptoSavingsTracker.presentation.theme.WithdrawalRed
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditTransactionScreen(
    navController: NavController,
    viewModel: EditTransactionViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var showDatePicker by remember { mutableStateOf(false) }

    LaunchedEffect(state.isSaved) {
        if (state.isSaved) {
            navController.popBackStack()
        }
    }

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
                        Text("Edit Transaction")
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
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (state.isLoading && state.assetId.isEmpty()) {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
                return@Column
            }

            if (!state.isEditable) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            text = "This transaction can’t be edited.",
                            style = MaterialTheme.typography.bodyLarge
                        )
                        Text(
                            text = "Only manual transactions are editable.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            // Transaction Type Selection
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp)
                ) {
                    Text(
                        text = "Transaction Type",
                        style = MaterialTheme.typography.titleMedium
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        FilterChip(
                            selected = state.transactionType == TransactionType.DEPOSIT,
                            onClick = { viewModel.setTransactionType(TransactionType.DEPOSIT) },
                            enabled = state.isEditable,
                            label = { Text("Deposit") },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.ArrowDownward,
                                    contentDescription = null,
                                    tint = if (state.transactionType == TransactionType.DEPOSIT)
                                        DepositGreen else MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = DepositGreen.copy(alpha = 0.2f)
                            ),
                            modifier = Modifier.weight(1f)
                        )
                        FilterChip(
                            selected = state.transactionType == TransactionType.WITHDRAWAL,
                            onClick = { viewModel.setTransactionType(TransactionType.WITHDRAWAL) },
                            enabled = state.isEditable,
                            label = { Text("Withdrawal") },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.ArrowUpward,
                                    contentDescription = null,
                                    tint = if (state.transactionType == TransactionType.WITHDRAWAL)
                                        WithdrawalRed else MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = WithdrawalRed.copy(alpha = 0.2f)
                            ),
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }

            OutlinedTextField(
                value = state.amount,
                onValueChange = viewModel::setAmount,
                enabled = state.isEditable,
                label = { Text("Amount (${state.assetCurrency})") },
                placeholder = { Text("0.00") },
                isError = state.amountError != null,
                supportingText = state.amountError?.let { { Text(it) } },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            OutlinedTextField(
                value = state.date.format(DateTimeFormatter.ofPattern("MMM d, yyyy")),
                onValueChange = { },
                label = { Text("Date") },
                readOnly = true,
                trailingIcon = {
                    IconButton(onClick = { showDatePicker = true }, enabled = state.isEditable) {
                        Icon(Icons.Default.CalendarMonth, contentDescription = "Select date")
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            OutlinedTextField(
                value = state.counterparty,
                onValueChange = viewModel::setCounterparty,
                enabled = state.isEditable,
                label = {
                    Text(if (state.transactionType == TransactionType.DEPOSIT)
                        "From (optional)" else "To (optional)")
                },
                placeholder = { Text("Wallet address or description") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            OutlinedTextField(
                value = state.comment,
                onValueChange = viewModel::setComment,
                enabled = state.isEditable,
                label = { Text("Notes (optional)") },
                placeholder = { Text("Add a note about this transaction") },
                modifier = Modifier.fillMaxWidth(),
                minLines = 2,
                maxLines = 4
            )

            Spacer(modifier = Modifier.height(16.dp))

            Button(
                onClick = viewModel::save,
                enabled = state.isEditable && state.isValid && !state.isLoading,
                modifier = Modifier.fillMaxWidth()
            ) {
                if (state.isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.padding(end = 8.dp),
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                }
                Text("Save Changes")
            }
        }
    }

    if (showDatePicker) {
        val datePickerState = rememberDatePickerState(
            initialSelectedDateMillis = state.date
                .atStartOfDay(ZoneId.systemDefault())
                .toInstant()
                .toEpochMilli()
        )

        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        datePickerState.selectedDateMillis?.let { millis ->
                            val selectedDate = Instant.ofEpochMilli(millis)
                                .atZone(ZoneId.systemDefault())
                                .toLocalDate()
                            viewModel.setDate(selectedDate)
                        }
                        showDatePicker = false
                    }
                ) { Text("OK") }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) { Text("Cancel") }
            }
        ) {
            DatePicker(state = datePickerState)
        }
    }
}

