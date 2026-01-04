package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.compose.runtime.Composable
import androidx.navigation.NavController

/**
 * Main Planning tab screen.
 * Uses MonthlyPlanningContainer to automatically switch between
 * planning and execution views based on current state.
 */
@Composable
fun PlanningScreen(
    navController: NavController
) {
    MonthlyPlanningContainer(navController = navController)
}
