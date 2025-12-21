package com.xax.CryptoSavingsTracker.presentation.settings

import android.content.ClipData
import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.annotation.VisibleForTesting
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.BuildConfig

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    navController: NavController,
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val developerTapCount = rememberSaveable { mutableIntStateOf(0) }

    LaunchedEffect(uiState.saveMessage, uiState.cacheMessage) {
        // Clear transient messages after they are shown once (keeps UI clean without snackbars).
        if (uiState.saveMessage != null || uiState.cacheMessage != null) {
            kotlinx.coroutines.delay(2500)
            viewModel.clearMessages()
        }
    }

    LaunchedEffect(uiState.exportedCsvUris) {
        val uris = uiState.exportedCsvUris ?: return@LaunchedEffect
        if (uris.isEmpty()) return@LaunchedEffect

        val primary = uris.first()
        val clipData = ClipData.newRawUri("CryptoSavingsTracker CSV Export", primary).apply {
            for (uri in uris.drop(1)) addItem(ClipData.Item(uri))
        }

        val sendMultipleIntent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = "text/csv"
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            this.clipData = clipData
        }

        context.startActivity(Intent.createChooser(sendMultipleIntent, "Export Data (CSV)"))
        viewModel.consumeExportResult()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { paddingValues ->
        SettingsContent(
            uiState = uiState,
            onUpdateCoinGeckoApiKey = viewModel::updateCoinGeckoApiKey,
            onUpdateTatumApiKey = viewModel::updateTatumApiKey,
            onSave = viewModel::save,
            onClearCaches = viewModel::clearCaches,
            onExportCsv = viewModel::exportCsv,
            onImportData = { /* TODO: Implement import */ },
            onTapVersion = { developerTapCount.intValue += 1 },
            isDeveloperModeEnabled = developerTapCount.intValue >= 7,
            versionLabel = BuildConfig.VERSION_NAME,
            modifier = Modifier.padding(paddingValues)
        )
    }
}

@Composable
@VisibleForTesting(otherwise = VisibleForTesting.PRIVATE)
internal fun SettingsContent(
    uiState: SettingsUiState,
    onUpdateCoinGeckoApiKey: (String) -> Unit,
    onUpdateTatumApiKey: (String) -> Unit,
    onSave: () -> Unit,
    onClearCaches: () -> Unit,
    onExportCsv: () -> Unit,
    onImportData: () -> Unit,
    onTapVersion: () -> Unit,
    isDeveloperModeEnabled: Boolean,
    versionLabel: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = "Data",
            style = MaterialTheme.typography.titleMedium
        )

        Button(
            onClick = onExportCsv,
            modifier = Modifier
                .fillMaxWidth()
                .testTag("settingsExportCsvButton"),
            enabled = !uiState.isExportingCsv
        ) {
            if (uiState.isExportingCsv) {
                Box(modifier = Modifier.height(18.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.height(18.dp))
                }
            } else {
                Text("Export Data (CSV)")
            }
        }

        Button(
            onClick = onImportData,
            modifier = Modifier
                .fillMaxWidth()
                .testTag("settingsImportButton"),
            enabled = false
        ) {
            Text("Import Data (Coming Soon)")
        }

        if (uiState.exportMessage != null) {
            Text(
                text = uiState.exportMessage ?: "",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        if (uiState.exportErrorMessage != null) {
            Text(
                text = uiState.exportErrorMessage ?: "",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error
            )
        }

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "About",
            style = MaterialTheme.typography.titleMedium
        )

        Text(
            text = "Version $versionLabel",
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onTapVersion)
                .testTag("settingsVersion"),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        if (isDeveloperModeEnabled) {
            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "Developer",
                style = MaterialTheme.typography.titleMedium
            )

            Text(
                text = "API keys and cache controls are hidden to match iOS settings.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            OutlinedTextField(
                value = uiState.coinGeckoApiKey,
                onValueChange = onUpdateCoinGeckoApiKey,
                label = { Text("CoinGecko API Key (optional)") },
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("settingsCoinGeckoKey"),
                singleLine = true,
                visualTransformation = PasswordVisualTransformation()
            )

            OutlinedTextField(
                value = uiState.tatumApiKey,
                onValueChange = onUpdateTatumApiKey,
                label = { Text("Tatum API Key (optional; required for on-chain)") },
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("settingsTatumKey"),
                singleLine = true,
                visualTransformation = PasswordVisualTransformation()
            )

            if (uiState.saveMessage != null) {
                Text(
                    text = uiState.saveMessage ?: "",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Button(
                onClick = onSave,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("settingsSaveButton"),
                enabled = !uiState.isSaving
            ) {
                if (uiState.isSaving) {
                    Box(modifier = Modifier.height(18.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.height(18.dp))
                    }
                } else {
                    Text("Save API Keys")
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "Cache",
                style = MaterialTheme.typography.titleMedium
            )

            Text(
                text = "Clears cached exchange rates and on-chain balances (useful for testing/fallback behavior).",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (uiState.cacheMessage != null) {
                Text(
                    text = uiState.cacheMessage ?: "",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Button(
                onClick = onClearCaches,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("settingsClearCachesButton"),
                enabled = !uiState.isClearingCaches
            ) {
                if (uiState.isClearingCaches) {
                    Box(modifier = Modifier.height(18.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.height(18.dp))
                    }
                } else {
                    Text("Clear Caches")
                }
            }
        }
    }
}
