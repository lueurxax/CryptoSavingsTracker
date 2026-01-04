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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
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
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.model.ChainIds

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddEditAssetScreen(
    navController: NavController,
    viewModel: AddEditAssetViewModel = hiltViewModel()
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
                title = { Text(if (uiState.isEditMode) "Edit Asset" else "Add Asset") },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { paddingValues ->
        if (uiState.isLoading && uiState.isEditMode && uiState.currency.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues)
                    .padding(16.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Asset type toggle
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Cryptocurrency Asset",
                        style = MaterialTheme.typography.bodyLarge
                    )
                    Switch(
                        checked = uiState.isCryptoAsset,
                        onCheckedChange = viewModel::updateIsCryptoAsset
                    )
                }

                Text(
                    text = if (uiState.isCryptoAsset) {
                        "Add a crypto wallet with on-chain balance tracking"
                    } else {
                        "Add a fiat account for manual balance tracking"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                // Currency selection
                CurrencyDropdown(
                    selectedCurrency = uiState.currency,
                    onCurrencySelected = viewModel::selectCurrency,
                    onCurrencyChanged = viewModel::updateCurrency,
                    error = uiState.currencyError,
                    isCrypto = uiState.isCryptoAsset
                )

                // Chain selection (only for crypto)
                if (uiState.isCryptoAsset) {
                    // Show auto-detected indicator
                    val isAutoDetected = !uiState.chainId.isNullOrBlank() &&
                        ChainIds.predictChain(uiState.currency) == uiState.chainId

                    ChainDropdown(
                        selectedChain = uiState.chainId,
                        onChainSelected = viewModel::updateChainId,
                        isAutoDetected = isAutoDetected
                    )

                    // Wallet address
                    OutlinedTextField(
                        value = uiState.address,
                        onValueChange = viewModel::updateAddress,
                        label = { Text("Wallet Address") },
                        placeholder = { Text("0x...") },
                        modifier = Modifier.fillMaxWidth(),
                        isError = uiState.addressError != null,
                        supportingText = uiState.addressError?.let { { Text(it) } }
                            ?: { Text("Optional — add to enable on-chain balance tracking") },
                        singleLine = true
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                // Save button
                Button(
                    onClick = viewModel::saveAsset,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !uiState.isLoading
                ) {
                    if (uiState.isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.padding(end = 8.dp),
                            color = MaterialTheme.colorScheme.onPrimary
                        )
                    }
                    Text(if (uiState.isEditMode) "Save Changes" else "Add Asset")
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CurrencyDropdown(
    selectedCurrency: String,
    onCurrencySelected: (String) -> Unit,
    onCurrencyChanged: (String) -> Unit,
    error: String?,
    isCrypto: Boolean
) {
    var expanded by remember { mutableStateOf(false) }

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it }
    ) {
        OutlinedTextField(
            value = selectedCurrency,
            onValueChange = onCurrencyChanged,
            label = { Text("Currency") },
            placeholder = { Text(if (isCrypto) "e.g., BTC, ETH" else "e.g., USD, EUR") },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(MenuAnchorType.PrimaryEditable),
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            isError = error != null,
            supportingText = error?.let { { Text(it) } },
            singleLine = true
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            val currencies = if (isCrypto) {
                AddEditAssetViewModel.availableCurrencies
            } else {
                listOf("USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD")
            }
            currencies.forEach { currency ->
                DropdownMenuItem(
                    text = { Text(currency) },
                    onClick = {
                        onCurrencySelected(currency)
                        expanded = false
                    }
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChainDropdown(
    selectedChain: String?,
    onChainSelected: (String?) -> Unit,
    isAutoDetected: Boolean = false
) {
    var expanded by remember { mutableStateOf(false) }

    Column {
        ExposedDropdownMenuBox(
            expanded = expanded,
            onExpandedChange = { expanded = it }
        ) {
            OutlinedTextField(
                value = selectedChain?.let { ChainIds.displayName(it) } ?: "Select network",
                onValueChange = {},
                readOnly = true,
                label = { Text("Network") },
                modifier = Modifier
                    .fillMaxWidth()
                    .menuAnchor(MenuAnchorType.PrimaryNotEditable),
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                supportingText = if (isAutoDetected) {
                    { Text("Auto-detected from currency", color = MaterialTheme.colorScheme.primary) }
                } else null
            )
            ExposedDropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false }
            ) {
                AddEditAssetViewModel.availableChains.forEach { chain ->
                    DropdownMenuItem(
                        text = { Text(ChainIds.displayName(chain)) },
                        onClick = {
                            onChainSelected(chain)
                            expanded = false
                        }
                    )
                }
            }
        }
    }
}
