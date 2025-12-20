package com.xax.CryptoSavingsTracker.presentation.dashboard

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.clickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.presentation.navigation.Screen
import com.patrykandpatrick.vico.compose.cartesian.CartesianChartHost
import com.patrykandpatrick.vico.compose.cartesian.axis.rememberBottom
import com.patrykandpatrick.vico.compose.cartesian.axis.rememberStart
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLineCartesianLayer
import com.patrykandpatrick.vico.compose.common.ProvideVicoTheme
import com.patrykandpatrick.vico.compose.m3.common.rememberM3VicoTheme
import com.patrykandpatrick.vico.core.cartesian.data.CartesianChartModelProducer
import com.patrykandpatrick.vico.core.cartesian.data.CartesianValueFormatter
import com.patrykandpatrick.vico.core.cartesian.data.lineSeries
import com.patrykandpatrick.vico.compose.cartesian.rememberCartesianChart
import com.patrykandpatrick.vico.core.cartesian.axis.HorizontalAxis
import com.patrykandpatrick.vico.core.cartesian.axis.VerticalAxis

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    navController: NavController,
    viewModel: DashboardViewModel = hiltViewModel()
) {
    val uiState = viewModel.uiState.collectAsState().value

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Dashboard") },
                actions = {
                    IconButton(onClick = { navController.navigate(Screen.Settings.route) }) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                    IconButton(onClick = viewModel::refresh) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
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
                        Button(onClick = viewModel::refresh) {
                            Text("Retry")
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        Button(onClick = { navController.navigate(Screen.Settings.route) }) {
                            Text("Open Settings")
                        }
                    }
                }
                else -> {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                Text(
                                    text = "Portfolio Total (USD)",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Text(
                                    text = uiState.totalUsd?.let { "$${String.format("%,.2f", it)}" } ?: "—",
                                    style = MaterialTheme.typography.headlineLarge
                                )
                            }
                        }

                        if (uiState.portfolioLast30Days.isNotEmpty()) {
                            Card(modifier = Modifier.fillMaxWidth()) {
                                Column(modifier = Modifier.padding(16.dp)) {
                                    Text(
                                        text = "Last 30 days (USD)",
                                        style = MaterialTheme.typography.titleMedium
                                    )
                                    Spacer(modifier = Modifier.height(12.dp))
                                    PortfolioLineChart(
                                        labels = uiState.portfolioLast30Days.map { it.label },
                                        values = uiState.portfolioLast30Days.map { it.usdTotal }
                                    )
                                    if (uiState.hasMissingUsdRates) {
                                        Spacer(modifier = Modifier.height(8.dp))
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Text(
                                                text = "Some currencies couldn’t be converted to USD (try again later).",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                            Button(onClick = { navController.navigate(Screen.Settings.route) }) {
                                                Text("Settings")
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if (uiState.activeGoals.isNotEmpty()) {
                            Card(modifier = Modifier.fillMaxWidth()) {
                                Column(modifier = Modifier.padding(16.dp)) {
                                    Text(
                                        text = "Goals",
                                        style = MaterialTheme.typography.titleMedium
                                    )
                                    Spacer(modifier = Modifier.height(12.dp))
                                    uiState.activeGoals.forEach { goalWithProgress ->
                                        Text(
                                            text = goalWithProgress.goal.name,
                                            style = MaterialTheme.typography.bodyLarge,
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .clickable {
                                                    navController.navigate(Screen.GoalDetail.createRoute(goalWithProgress.goal.id))
                                                }
                                                .semantics { contentDescription = "Open goal ${goalWithProgress.goal.name}" }
                                        )
                                        Spacer(modifier = Modifier.height(6.dp))
                                        LinearProgressIndicator(
                                            progress = { goalWithProgress.progress.toFloat() },
                                            modifier = Modifier.fillMaxWidth()
                                        )
                                        Spacer(modifier = Modifier.height(4.dp))
                                        Text(
                                            text = "${goalWithProgress.progressPercent}% • Deadline: ${goalWithProgress.goal.deadline}",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                        Spacer(modifier = Modifier.height(12.dp))
                                    }
                                }
                            }
                        }

                        if (uiState.assets.isEmpty()) {
                            Text(
                                text = "Add assets to see your portfolio here.",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Button(onClick = { navController.navigate(Screen.AddAsset.route) }) {
                                Icon(Icons.Default.Add, contentDescription = "Add Asset")
                                Spacer(modifier = Modifier.width(8.dp))
                                Text("Add Asset")
                            }
                        } else {
                            Text(
                                text = "Assets",
                                style = MaterialTheme.typography.titleMedium
                            )
                            uiState.assets.forEach { summary ->
                                Card(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable {
                                            navController.navigate(Screen.AssetDetail.createRoute(summary.asset.id))
                                        }
                                        .semantics { contentDescription = "Open asset ${summary.asset.currency}" }
                                ) {
                                    Column(modifier = Modifier.padding(16.dp)) {
                                        Text(
                                            text = summary.asset.displayName(),
                                            style = MaterialTheme.typography.titleMedium
                                        )
                                        Spacer(modifier = Modifier.height(8.dp))
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Text(
                                                text = "${String.format("%,.4f", summary.manualBalance)} ${summary.asset.currency}",
                                                style = MaterialTheme.typography.bodyLarge
                                            )
                                            Text(
                                                text = summary.usdValue?.let { "$${String.format("%,.2f", it)}" } ?: "—",
                                                style = MaterialTheme.typography.bodyLarge,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                        if (summary.usdValue == null) {
                                            Spacer(modifier = Modifier.height(6.dp))
                                            Row(verticalAlignment = Alignment.CenterVertically) {
                                                Spacer(modifier = Modifier.width(2.dp))
                                                Text(
                                                    text = "USD value unavailable",
                                                    style = MaterialTheme.typography.bodySmall,
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PortfolioLineChart(
    labels: List<String>,
    values: List<Double>
) {
    val modelProducer = remember { CartesianChartModelProducer() }

    LaunchedEffect(values) {
        modelProducer.runTransaction {
            if (values.isNotEmpty()) {
                lineSeries { series(values) }
            }
        }
    }

    val theme = rememberM3VicoTheme()
    val bottomAxisFormatter = remember(labels) {
        CartesianValueFormatter { _, value, _ ->
            val index = value.toInt()
            labels.getOrNull(index) ?: index.toString()
        }
    }

    val chart = rememberCartesianChart(
        rememberLineCartesianLayer(),
        startAxis = VerticalAxis.rememberStart(),
        bottomAxis = HorizontalAxis.rememberBottom(
            valueFormatter = bottomAxisFormatter,
            itemPlacer = remember { HorizontalAxis.ItemPlacer.aligned(spacing = 5) }
        )
    )

    ProvideVicoTheme(theme) {
        CartesianChartHost(
            chart = chart,
            modelProducer = modelProducer,
            modifier = Modifier
                .fillMaxWidth()
                .height(180.dp)
                .semantics { contentDescription = "Portfolio value line chart" }
        )
    }
}
