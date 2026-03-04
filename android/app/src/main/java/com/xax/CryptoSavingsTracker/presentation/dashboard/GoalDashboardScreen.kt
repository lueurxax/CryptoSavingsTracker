package com.xax.CryptoSavingsTracker.presentation.dashboard

import android.provider.Settings
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.presentation.common.AmountFormatters
import com.xax.CryptoSavingsTracker.presentation.navigation.Screen
import com.xax.CryptoSavingsTracker.presentation.theme.VisualComponentDefaults
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoalDashboardScreen(
    navController: NavController,
    viewModel: GoalDashboardViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val scene = uiState.sceneModel
    val snackbarHostState = remember { SnackbarHostState() }
    val coroutineScope = rememberCoroutineScope()

    var diagnosticsPayload by remember { mutableStateOf<DiagnosticsPayload?>(null) }
    var openedTracked by rememberSaveable { mutableStateOf(false) }
    var lastPrimaryCtaFingerprint by rememberSaveable { mutableStateOf<String?>(null) }
    val reduceMotion = prefersReducedMotion()
    val transitionDuration = if (reduceMotion) 80 else 220

    LaunchedEffect(scene?.goalId) {
        if (!openedTracked && scene != null) {
            viewModel.trackDashboardOpened()
            openedTracked = true
        }
    }

    LaunchedEffect(scene?.nextAction?.resolverState?.wireId, scene?.nextAction?.primaryCta?.id) {
        val nextAction = scene?.nextAction ?: return@LaunchedEffect
        val fingerprint = "${nextAction.resolverState.wireId}|${nextAction.primaryCta.id}"
        if (fingerprint != lastPrimaryCtaFingerprint) {
            viewModel.trackPrimaryCtaShown(nextAction)
            lastPrimaryCtaFingerprint = fingerprint
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Goal Dashboard") },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = viewModel::refresh) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
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
                uiState.isLoading && scene == null -> {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                }

                uiState.errorMessage != null && scene == null -> {
                    ErrorView(
                        message = uiState.errorMessage ?: "Failed to load goal dashboard",
                        onRetry = viewModel::refresh
                    )
                }

                scene != null -> {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxSize()
                            .animateContentSize(animationSpec = tween(durationMillis = transitionDuration)),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        item {
                            DashboardModuleCard(
                                title = "Goal Snapshot",
                                tag = "goal_dashboard.goal_snapshot",
                                surface = DashboardCardSurface.PRIMARY
                            ) {
                                SnapshotModule(
                                    scene = scene,
                                    onAction = { actionId ->
                                        handleAction(
                                            actionId = actionId,
                                            scene = scene,
                                            navController = navController,
                                            onRefresh = viewModel::refresh,
                                            showMessage = { message ->
                                                coroutineScope.launch { snackbarHostState.showSnackbar(message) }
                                            }
                                        )
                                    }
                                )
                            }
                        }

                        item {
                            DashboardModuleCard(
                                title = "Next Action",
                                tag = "goal_dashboard.next_action",
                                surface = DashboardCardSurface.EMPHASIS
                            ) {
                                NextActionModule(
                                    scene = scene,
                                    onPrimaryTapped = {
                                        viewModel.trackPrimaryCtaTapped(scene.nextAction)
                                        handleAction(
                                            actionId = scene.nextAction.primaryCta.id,
                                            scene = scene,
                                            navController = navController,
                                            onRefresh = viewModel::refresh,
                                            showMessage = { message ->
                                                coroutineScope.launch { snackbarHostState.showSnackbar(message) }
                                            }
                                        )
                                    },
                                    onSecondaryTapped = { actionId ->
                                        handleAction(
                                            actionId = actionId,
                                            scene = scene,
                                            navController = navController,
                                            onRefresh = viewModel::refresh,
                                            showMessage = { message ->
                                                coroutineScope.launch { snackbarHostState.showSnackbar(message) }
                                            }
                                        )
                                    },
                                    onOpenDiagnostics = {
                                        diagnosticsPayload = scene.nextAction.diagnostics
                                    }
                                )
                            }
                        }

                        item {
                            DashboardModuleCard(
                                title = "Forecast and Deadline Risk",
                                tag = "goal_dashboard.forecast_risk",
                                surface = DashboardCardSurface.PRIMARY
                            ) {
                                ForecastModule(
                                    scene = scene,
                                    onAction = { actionId ->
                                        handleAction(
                                            actionId = actionId,
                                            scene = scene,
                                            navController = navController,
                                            onRefresh = viewModel::refresh,
                                            showMessage = { message ->
                                                coroutineScope.launch { snackbarHostState.showSnackbar(message) }
                                            }
                                        )
                                    }
                                )
                            }
                        }

                        item {
                            DashboardModuleCard(
                                title = "Contributions and Activity",
                                tag = "goal_dashboard.contribution_activity",
                                surface = DashboardCardSurface.PRIMARY
                            ) {
                                ContributionModule(
                                    scene = scene,
                                    onAction = { actionId ->
                                        handleAction(
                                            actionId = actionId,
                                            scene = scene,
                                            navController = navController,
                                            onRefresh = viewModel::refresh,
                                            showMessage = { message ->
                                                coroutineScope.launch { snackbarHostState.showSnackbar(message) }
                                            }
                                        )
                                    }
                                )
                            }
                        }

                        item {
                            DashboardModuleCard(
                                title = "Allocation Health",
                                tag = "goal_dashboard.allocation_health",
                                surface = DashboardCardSurface.PRIMARY
                            ) {
                                AllocationModule(
                                    scene = scene,
                                    onAction = { actionId ->
                                        handleAction(
                                            actionId = actionId,
                                            scene = scene,
                                            navController = navController,
                                            onRefresh = viewModel::refresh,
                                            showMessage = { message ->
                                                coroutineScope.launch { snackbarHostState.showSnackbar(message) }
                                            }
                                        )
                                    }
                                )
                            }
                        }

                        item {
                            DashboardModuleCard(
                                title = "Utilities",
                                tag = "goal_dashboard.utilities",
                                surface = DashboardCardSurface.SECONDARY
                            ) {
                                UtilitiesModule(
                                    scene = scene,
                                    onAction = { actionId ->
                                        handleAction(
                                            actionId = actionId,
                                            scene = scene,
                                            navController = navController,
                                            onRefresh = viewModel::refresh,
                                            showMessage = { message ->
                                                coroutineScope.launch { snackbarHostState.showSnackbar(message) }
                                            }
                                        )
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    diagnosticsPayload?.let { payload ->
        DiagnosticsDialog(
            payload = payload,
            onDismiss = { diagnosticsPayload = null }
        )
    }
}

@Composable
private fun ErrorView(
    message: String,
    onRetry: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = message,
            color = MaterialTheme.colorScheme.error
        )
        Button(onClick = onRetry) {
            Text("Retry")
        }
    }
}

@Composable
private fun SnapshotModule(
    scene: GoalDashboardSceneModel,
    onAction: (String) -> Unit
) {
    val snapshot = scene.snapshot
    when (snapshot.moduleState) {
        GoalDashboardModuleState.LOADING -> {
            Text("Loading snapshot…", modifier = Modifier.testTag("goal_dashboard.goal_snapshot.loading"))
            ProgressWithSpacing()
        }

        GoalDashboardModuleState.ERROR, GoalDashboardModuleState.STALE -> {
            Text(
                text = "Snapshot is not up to date.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.testTag("goal_dashboard.goal_snapshot.${snapshot.moduleState.wireId}")
            )
            RecoveryButton(
                title = if (snapshot.moduleState == GoalDashboardModuleState.ERROR) "Retry Data Sync" else "Refresh Snapshot",
                onClick = { onAction("refresh_data") }
            )
        }

        GoalDashboardModuleState.EMPTY -> {
            Text(
                text = "No snapshot data is available yet.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.testTag("goal_dashboard.goal_snapshot.empty")
            )
        }

        GoalDashboardModuleState.READY -> {
            val funded = AmountFormatters.formatDisplayCurrencyAmount(
                snapshot.currentAmount.toDouble(),
                scene.currency,
                isCrypto = false
            )
            val target = AmountFormatters.formatDisplayCurrencyAmount(
                snapshot.targetAmount.toDouble(),
                scene.currency,
                isCrypto = false
            )
            val remaining = AmountFormatters.formatDisplayCurrencyAmount(
                snapshot.remainingAmount.toDouble(),
                scene.currency,
                isCrypto = false
            )

            Text("$funded of $target", fontWeight = FontWeight.SemiBold)
            Text(
                text = "Remaining: $remaining",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            snapshot.daysRemaining?.let { days ->
                Text(
                    text = "$days days left",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun NextActionModule(
    scene: GoalDashboardSceneModel,
    onPrimaryTapped: () -> Unit,
    onSecondaryTapped: (String) -> Unit,
    onOpenDiagnostics: () -> Unit
) {
    val nextAction = scene.nextAction
    Text(
        text = GoalDashboardCopyCatalog.text(nextAction.reasonCopyKey),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.testTag("goal_dashboard.next_action.${nextAction.moduleState.wireId}")
    )
    Spacer(modifier = Modifier.height(8.dp))

    Button(
        onClick = onPrimaryTapped,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(nextAction.primaryCta.title)
    }

    if (nextAction.moduleState == GoalDashboardModuleState.ERROR && nextAction.diagnostics != null) {
        Spacer(modifier = Modifier.height(6.dp))
        TextButton(onClick = onOpenDiagnostics) {
            Text("View Diagnostics")
        }
    }

    nextAction.secondaryCta?.let { secondary ->
        Spacer(modifier = Modifier.height(6.dp))
        TextButton(onClick = { onSecondaryTapped(secondary.id) }) {
            Text(secondary.title)
        }
    }
}

@Composable
private fun ForecastModule(
    scene: GoalDashboardSceneModel,
    onAction: (String) -> Unit
) {
    val forecast = scene.forecastRisk
    when (forecast.moduleState) {
        GoalDashboardModuleState.LOADING -> {
            Text("Loading forecast…", modifier = Modifier.testTag("goal_dashboard.forecast_risk.loading"))
            ProgressWithSpacing()
            ForecastExplainabilityRows(
                assumptionText = "Based on available contribution history.",
                updatedAt = null,
                confidence = null
            )
        }

        GoalDashboardModuleState.EMPTY -> {
            Text(
                GoalDashboardCopyCatalog.text("dashboard.forecast.empty"),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.testTag("goal_dashboard.forecast_risk.empty")
            )
            ForecastExplainabilityRows(
                assumptionText = "Needs more contribution history.",
                updatedAt = forecast.updatedAt,
                confidence = forecast.confidence
            )
        }

        GoalDashboardModuleState.ERROR -> {
            Text(
                text = "Forecast data is unavailable right now.",
                modifier = Modifier.testTag("goal_dashboard.forecast_risk.error")
            )
            ForecastExplainabilityRows(
                assumptionText = "Based on available contribution history before the error.",
                updatedAt = forecast.updatedAt,
                confidence = null
            )
            RecoveryButton(title = "Retry Forecast", onClick = { onAction("refresh_data") })
        }

        GoalDashboardModuleState.STALE, GoalDashboardModuleState.READY -> {
            forecast.status?.let { status ->
                StatusChip(status = status)
            }
            forecast.projectedAmount?.let { projected ->
                Text(
                    text = "Projected by deadline: " + AmountFormatters.formatDisplayCurrencyAmount(
                        projected.toDouble(),
                        scene.currency,
                        isCrypto = false
                    ),
                    fontWeight = FontWeight.SemiBold
                )
            }
            ForecastExplainabilityRows(
                assumptionText = "Based on last ${forecast.assumptionWindowDays ?: 0} days of contributions.",
                updatedAt = forecast.updatedAt,
                confidence = forecast.confidence
            )
            if (forecast.moduleState == GoalDashboardModuleState.STALE) {
                RecoveryButton(title = "Refresh Forecast", onClick = { onAction("refresh_data") })
            }
        }
    }
}

@Composable
private fun ContributionModule(
    scene: GoalDashboardSceneModel,
    onAction: (String) -> Unit
) {
    val activity = scene.contributionActivity
    when (activity.moduleState) {
        GoalDashboardModuleState.LOADING -> {
            Text("Loading activity…", modifier = Modifier.testTag("goal_dashboard.contribution_activity.loading"))
            ProgressWithSpacing()
        }

        GoalDashboardModuleState.ERROR, GoalDashboardModuleState.STALE -> {
            Text(
                text = "Activity data is out of date.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.testTag("goal_dashboard.contribution_activity.${activity.moduleState.wireId}")
            )
            RecoveryButton(
                title = if (activity.moduleState == GoalDashboardModuleState.ERROR) "Reload Activity" else "Refresh Activity",
                onClick = { onAction("refresh_data") }
            )
        }

        GoalDashboardModuleState.EMPTY, GoalDashboardModuleState.READY -> {
            Text(
                text = "This month: " + AmountFormatters.formatDisplayCurrencyAmount(
                    activity.monthContributionSum.toDouble(),
                    scene.currency,
                    isCrypto = false
                ),
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(6.dp))
            if (activity.recentRows.isEmpty()) {
                Text("No recent contributions.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                activity.recentRows.forEach { row ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(formatContributionDate(row.date))
                        Text(
                            AmountFormatters.formatDisplayCurrencyAmount(
                                row.amount.toDouble(),
                                scene.currency,
                                isCrypto = false
                            )
                        )
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                }
            }
        }
    }
}

@Composable
private fun AllocationModule(
    scene: GoalDashboardSceneModel,
    onAction: (String) -> Unit
) {
    val allocation = scene.allocationHealth
    when (allocation.moduleState) {
        GoalDashboardModuleState.LOADING -> {
            Text("Loading allocation health…", modifier = Modifier.testTag("goal_dashboard.allocation_health.loading"))
            ProgressWithSpacing()
        }

        GoalDashboardModuleState.ERROR, GoalDashboardModuleState.STALE -> {
            Text(
                text = "Allocation health needs refresh.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.testTag("goal_dashboard.allocation_health.${allocation.moduleState.wireId}")
            )
            RecoveryButton(
                title = if (allocation.moduleState == GoalDashboardModuleState.ERROR) "Recompute Allocation Health" else "Refresh Allocations",
                onClick = { onAction("refresh_data") }
            )
        }

        GoalDashboardModuleState.EMPTY -> {
            Text("No allocations yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        GoalDashboardModuleState.READY -> {
            if (allocation.overAllocated) {
                Text(
                    text = "Some assets are over-allocated.",
                    color = VisualComponentDefaults.statusWarningColor(),
                    fontWeight = FontWeight.SemiBold
                )
            } else if ((allocation.concentrationRatio ?: 0.0) > 0.7) {
                Text(
                    text = "Allocation is concentrated in a single asset.",
                    color = VisualComponentDefaults.statusWarningColor()
                )
            } else {
                Text(
                    text = "Allocation looks balanced.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            allocation.topAssets.forEach { asset ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(asset.assetCurrency)
                    Text("${(asset.weightRatio * 100).toInt()}%")
                }
            }
        }
    }
}

@Composable
private fun UtilitiesModule(
    scene: GoalDashboardSceneModel,
    onAction: (String) -> Unit
) {
    val utilities = scene.utilities
    when (utilities.moduleState) {
        GoalDashboardModuleState.LOADING -> {
            Text("Loading utilities…", modifier = Modifier.testTag("goal_dashboard.utilities.loading"))
            ProgressWithSpacing()
        }

        GoalDashboardModuleState.ERROR -> {
            Text("Utility actions are temporarily unavailable.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            RecoveryButton(title = "Open Goal Details", onClick = { onAction("edit_goal") })
        }

        GoalDashboardModuleState.STALE -> {
            Text("Showing previous utility actions.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            RecoveryButton(title = "Continue", onClick = { onAction("continue_last_data") })
        }

        GoalDashboardModuleState.EMPTY -> {
            Text("No utility actions available.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        GoalDashboardModuleState.READY -> {
            utilities.actions.forEach { action ->
                Button(
                    onClick = { onAction(action.id) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(action.title)
                }
                Spacer(modifier = Modifier.height(6.dp))
            }
        }
    }
}

@Composable
private fun ForecastExplainabilityRows(
    assumptionText: String,
    updatedAt: Instant?,
    confidence: GoalDashboardForecastConfidence?
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(assumptionText, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(
            text = "Updated ${updatedAt?.let { formatContributionDate(it) } ?: "recently"}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = "Confidence: ${confidence?.wireId?.replaceFirstChar { it.uppercase() } ?: "Unavailable"}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun StatusChip(status: GoalDashboardRiskStatus) {
    val iconToken: String
    val text: String
    val color: Color
    val accessibilityLabel: String
    val icon = when (status) {
        GoalDashboardRiskStatus.ON_TRACK -> {
            iconToken = "checkmark.circle.fill"
            text = "On Track"
            color = VisualComponentDefaults.statusSuccessColor()
            accessibilityLabel = "On track: current pace can reach deadline"
            Icons.Default.CheckCircle
        }

        GoalDashboardRiskStatus.AT_RISK -> {
            iconToken = "exclamationmark.triangle.fill"
            text = "At Risk"
            color = VisualComponentDefaults.statusWarningColor()
            accessibilityLabel = "At risk: current pace may miss deadline"
            Icons.Default.Warning
        }

        GoalDashboardRiskStatus.OFF_TRACK -> {
            iconToken = "xmark.octagon.fill"
            text = "Off Track"
            color = VisualComponentDefaults.statusErrorColor()
            accessibilityLabel = "Off track: current pace will miss deadline"
            Icons.Default.Error
        }
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier
            .semantics { contentDescription = accessibilityLabel }
            .testTag("goal_dashboard.status_chip.${status.wireId}")
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color
        )
        Text(
            text = text,
            color = color,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = iconToken,
            style = MaterialTheme.typography.labelSmall,
            color = Color.Transparent
        )
    }
}

@Composable
private fun RecoveryButton(
    title: String,
    onClick: () -> Unit
) {
    TextButton(onClick = onClick) {
        Text(title)
    }
}

@Composable
private fun ProgressWithSpacing() {
    Spacer(modifier = Modifier.height(4.dp))
    CircularProgressIndicator()
}

@Composable
private fun DiagnosticsDialog(
    payload: DiagnosticsPayload,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Close")
            }
        },
        title = { Text("Diagnostics") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Reason: ${payload.reasonCode}")
                Text("Last Successful Refresh: ${payload.lastSuccessfulRefreshAt?.let { formatContributionDate(it) } ?: "Unavailable"}")
                Text("Next Step: ${GoalDashboardCopyCatalog.text(payload.nextStepCopyKey)}")
            }
        }
    )
}

private fun handleAction(
    actionId: String,
    scene: GoalDashboardSceneModel,
    navController: NavController,
    onRefresh: () -> Unit,
    showMessage: (String) -> Unit
) {
    val primaryAssetId = scene.allocationHealth.topAssets.firstOrNull()?.assetId

    when (actionId) {
        "refresh_data", "retry_data_sync" -> onRefresh()
        "view_goal_history", "view_history" -> navController.navigate(Screen.PlanHistory.route)
        "create_new_goal" -> navController.navigate(Screen.AddGoal.route)
        "edit_goal", "resume_goal" -> navController.navigate(Screen.EditGoal.createRoute(scene.goalId))
        "rebalance_allocations", "open_allocation_health" -> navController.navigate(Screen.AllocationList.createRoute(scene.goalId))
        "add_first_asset", "add_asset" -> navController.navigate(Screen.AddAsset.route)
        "add_first_contribution", "add_contribution", "log_contribution" -> {
            if (primaryAssetId == null) {
                showMessage("Add or allocate an asset first")
            } else {
                navController.navigate(Screen.AddTransaction.createRoute(primaryAssetId))
            }
        }

        "plan_this_month" -> navController.navigate(Screen.MonthlyPlanning.route)
        "open_goal_details" -> navController.popBackStack()
        "open_activity" -> {
            if (primaryAssetId == null) {
                showMessage("No transaction history available")
            } else {
                navController.navigate(Screen.TransactionHistory.createRoute(primaryAssetId))
            }
        }

        "continue_last_data", "open_forecast", "view_diagnostics" -> Unit
        else -> Unit
    }
}

@Composable
private fun DashboardModuleCard(
    title: String,
    tag: String,
    surface: DashboardCardSurface,
    content: @Composable () -> Unit
) {
    val colors = when (surface) {
        DashboardCardSurface.PRIMARY -> VisualComponentDefaults.goalDashboardPrimaryCardColors()
        DashboardCardSurface.SECONDARY -> VisualComponentDefaults.goalDashboardSecondaryCardColors()
        DashboardCardSurface.EMPHASIS -> VisualComponentDefaults.goalDashboardEmphasisCardColors()
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag(tag),
        colors = colors,
        border = VisualComponentDefaults.goalDashboardCardBorder(),
        elevation = VisualComponentDefaults.goalDashboardCardElevation()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            content()
        }
    }
}

@Composable
private fun prefersReducedMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        runCatching {
            Settings.Global.getFloat(
                context.contentResolver,
                Settings.Global.ANIMATOR_DURATION_SCALE,
                1f
            ) == 0f
        }.getOrDefault(false)
    }
}

private fun formatContributionDate(date: Instant): String {
    val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd").withZone(ZoneId.systemDefault())
    return formatter.format(date)
}

private enum class DashboardCardSurface {
    PRIMARY,
    SECONDARY,
    EMPHASIS
}
