package com.xax.CryptoSavingsTracker.debug

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.compose.rememberNavController
import com.xax.CryptoSavingsTracker.presentation.dashboard.DashboardScreen
import com.xax.CryptoSavingsTracker.presentation.planning.PlanningScreen
import com.xax.CryptoSavingsTracker.presentation.settings.SettingsScreen
import com.xax.CryptoSavingsTracker.presentation.theme.CryptoSavingsTrackerTheme
import dagger.hilt.android.AndroidEntryPoint

private enum class ProductionFlow(val raw: String) {
    Planning("planning"),
    Dashboard("dashboard"),
    Settings("settings");

    companion object {
        fun from(raw: String?): ProductionFlow {
            return entries.firstOrNull { it.raw == raw } ?: Planning
        }
    }
}

private enum class ProductionState(val raw: String) {
    Default("default"),
    Error("error"),
    Recovery("recovery");

    companion object {
        fun from(raw: String?): ProductionState {
            return entries.firstOrNull { it.raw == raw } ?: Default
        }
    }
}

@AndroidEntryPoint
class ProductionFlowCaptureActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Force onboarding as complete so real production flows can render.
        getSharedPreferences("onboarding_prefs", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("onboarding_completed", true)
            .apply()

        val flow = ProductionFlow.from(intent.getStringExtra("flow"))
        val state = ProductionState.from(intent.getStringExtra("state"))

        setContent {
            CryptoSavingsTrackerTheme {
                ProductionFlowCaptureScreen(flow = flow, state = state)
            }
        }
    }
}

@Composable
private fun ProductionFlowCaptureScreen(flow: ProductionFlow, state: ProductionState) {
    val navController = rememberNavController()

    Box(modifier = Modifier.fillMaxSize()) {
        when (flow) {
            ProductionFlow.Planning -> PlanningScreen(navController = navController)
            ProductionFlow.Dashboard -> DashboardScreen(navController = navController)
            ProductionFlow.Settings -> SettingsScreen(navController = navController)
        }

        Text(
            text = "PRODUCTION_CAPTURE:${flow.raw}:${state.raw}",
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier
                .align(Alignment.TopStart)
                .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.72f))
                .padding(horizontal = 8.dp, vertical = 4.dp)
        )
    }
}
