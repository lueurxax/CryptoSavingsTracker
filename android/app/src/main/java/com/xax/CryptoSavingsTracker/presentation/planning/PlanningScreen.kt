package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.presentation.config.VisualSystemFlow
import com.xax.CryptoSavingsTracker.presentation.config.VisualSystemRollout

/**
 * Main Planning tab screen.
 * Uses MonthlyPlanningContainer to automatically switch between
 * planning and execution views based on current state.
 */
@Composable
fun PlanningScreen(
    navController: NavController
) {
    val context = LocalContext.current
    val rollout = remember(context) { VisualSystemRollout.from(context) }
    val visualEnabled = remember(rollout) { rollout.isEnabled(VisualSystemFlow.PLANNING) }
    if (visualEnabled) {
        MonthlyPlanningContainer(
            navController = navController
        )
    } else {
        // Legacy fallback entrypoint for rollout rollback path.
        MonthlyPlanningScreen(
            navController = navController
        )
    }
}
