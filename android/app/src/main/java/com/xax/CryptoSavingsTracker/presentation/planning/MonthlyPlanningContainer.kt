package com.xax.CryptoSavingsTracker.presentation.planning

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.model.ExecutionStatus

/**
 * Container that handles view switching between Monthly Planning and Execution screens.
 * Automatically shows the appropriate view based on current execution state.
 *
 * - No active execution → Shows MonthlyPlanningScreen
 * - Active execution (EXECUTING) → Shows MonthlyExecutionScreen
 */
@Composable
fun MonthlyPlanningContainer(
    navController: NavController,
    planningViewModel: MonthlyPlanningViewModel = hiltViewModel(),
    executionViewModel: MonthlyExecutionViewModel = hiltViewModel()
) {
    val planningState by planningViewModel.uiState.collectAsState()
    val executionState by executionViewModel.uiState.collectAsState()

    // Determine which view to show based on execution state
    val hasActiveExecution = executionState.record?.status == ExecutionStatus.EXECUTING

    Box(modifier = Modifier.fillMaxSize()) {
        when {
            // Still loading - show spinner
            executionState.isLoading && planningState.isLoading -> {
                CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.Center)
                )
            }

            // Active execution - show execution tracking screen
            hasActiveExecution -> {
                MonthlyExecutionScreen(
                    navController = navController,
                    viewModel = executionViewModel
                )
            }

            // No active execution - show planning screen
            else -> {
                MonthlyPlanningScreen(
                    navController = navController,
                    viewModel = planningViewModel
                )
            }
        }
    }
}
