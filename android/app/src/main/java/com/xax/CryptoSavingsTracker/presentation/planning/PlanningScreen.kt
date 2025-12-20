package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.compose.runtime.Composable
import androidx.navigation.NavController

/**
 * Main Planning tab screen.
 * Delegates to MonthlyPlanningScreen for the actual implementation.
 */
@Composable
fun PlanningScreen(
    navController: NavController
) {
    MonthlyPlanningScreen(navController = navController)
}
