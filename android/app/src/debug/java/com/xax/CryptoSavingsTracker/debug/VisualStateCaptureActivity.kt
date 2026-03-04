package com.xax.CryptoSavingsTracker.debug

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleBlue
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleGreen
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleRed
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleYellow
import com.xax.CryptoSavingsTracker.presentation.theme.CryptoSavingsTrackerTheme
import com.xax.CryptoSavingsTracker.presentation.theme.Elevation

private enum class VisualState(val raw: String) {
    Default("default"),
    Pressed("pressed"),
    Disabled("disabled"),
    Error("error"),
    Loading("loading"),
    Empty("empty"),
    Stale("stale"),
    Recovery("recovery");

    companion object {
        fun from(raw: String?): VisualState {
            return entries.firstOrNull { it.raw == raw } ?: Default
        }
    }
}

private enum class VisualComponent(val raw: String) {
    PlanningHeaderCard("planning.header_card"),
    PlanningGoalRow("planning.goal_row"),
    DashboardSummaryCard("dashboard.summary_card"),
    SettingsSectionRow("settings.section_row");

    companion object {
        fun from(raw: String?): VisualComponent {
            return entries.firstOrNull { it.raw == raw } ?: PlanningHeaderCard
        }
    }
}

class VisualStateCaptureActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val component = VisualComponent.from(intent.getStringExtra("component"))
        val state = VisualState.from(intent.getStringExtra("state"))
        val captureKey = "CAPTURE:${component.raw}:${state.raw}"

        setContent {
            CryptoSavingsTrackerTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    VisualStateCaptureScreen(
                        component = component,
                        state = state,
                        captureKey = captureKey,
                    )
                }
            }
        }
    }
}

@Composable
private fun VisualStateCaptureScreen(
    component: VisualComponent,
    state: VisualState,
    captureKey: String,
) {
    val tint = stateTint(state)
    val alpha = if (state == VisualState.Disabled) 0.45f else 1f
    val elevation = if (state == VisualState.Pressed) Elevation.none else Elevation.card

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = "Visual State Capture",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = "${component.raw} • ${state.raw}",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = captureKey,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Card(
            modifier = Modifier
                .fillMaxWidth()
                .alpha(alpha),
            elevation = CardDefaults.cardElevation(defaultElevation = elevation),
            shape = RoundedCornerShape(16.dp)
        ) {
            when (component) {
                VisualComponent.PlanningHeaderCard -> PlanningHeaderBody(state = state, tint = tint)
                VisualComponent.PlanningGoalRow -> PlanningGoalRowBody(state = state, tint = tint)
                VisualComponent.DashboardSummaryCard -> DashboardSummaryBody(state = state, tint = tint)
                VisualComponent.SettingsSectionRow -> SettingsSectionBody(state = state, tint = tint)
            }
        }
    }
}

@Composable
private fun PlanningHeaderBody(state: VisualState, tint: Color) {
    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Monthly Planning", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text("Required: 1,250 USD", style = MaterialTheme.typography.bodyMedium)
        StateFooter(state = state, tint = tint)
    }
}

@Composable
private fun PlanningGoalRowBody(state: VisualState, tint: Color) {
    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Emergency Fund", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(8.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(0.62f)
                    .height(8.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(tint)
            )
        }
        StateFooter(state = state, tint = tint)
    }
}

@Composable
private fun DashboardSummaryBody(state: VisualState, tint: Color) {
    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Projected Progress", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            Metric("This month", "63%")
            Metric("At risk goals", "1")
        }
        StateFooter(state = state, tint = tint)
    }
}

@Composable
private fun SettingsSectionBody(state: VisualState, tint: Color) {
    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .width(10.dp)
                        .height(10.dp)
                        .clip(RoundedCornerShape(5.dp))
                        .background(tint)
                )
                Spacer(modifier = Modifier.width(10.dp))
                Text("Budget Notifications", style = MaterialTheme.typography.bodyLarge)
            }
            Text("Enabled", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        StateFooter(state = state, tint = tint)
    }
}

@Composable
private fun Metric(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun StateFooter(state: VisualState, tint: Color) {
    when (state) {
        VisualState.Loading -> {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(
                    modifier = Modifier
                        .width(16.dp)
                        .height(16.dp),
                    strokeWidth = 2.dp,
                    color = tint
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("Loading latest values", style = MaterialTheme.typography.bodySmall)
            }
        }
        VisualState.Empty -> {
            Text("No items available", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        VisualState.Stale -> {
            Text("Data may be stale", style = MaterialTheme.typography.bodySmall, color = tint, fontWeight = FontWeight.Medium)
        }
        VisualState.Error -> {
            Text("Action required", style = MaterialTheme.typography.bodySmall, color = tint, fontWeight = FontWeight.SemiBold)
        }
        VisualState.Recovery -> {
            Text("Recovered successfully", style = MaterialTheme.typography.bodySmall, color = tint, fontWeight = FontWeight.Medium)
        }
        else -> {
            Text("State: ${state.raw}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun stateTint(state: VisualState): Color {
    return when (state) {
        VisualState.Error -> AccessibleRed
        VisualState.Stale -> AccessibleYellow
        VisualState.Recovery -> AccessibleGreen
        VisualState.Pressed -> AccessibleBlue
        VisualState.Loading -> AccessibleBlue
        VisualState.Disabled -> Color(0xFF9E9E9E)
        VisualState.Empty -> Color(0xFF757575)
        VisualState.Default -> AccessibleBlue
    }
}
