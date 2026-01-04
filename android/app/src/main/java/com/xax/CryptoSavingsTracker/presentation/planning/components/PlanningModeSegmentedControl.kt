package com.xax.CryptoSavingsTracker.presentation.planning.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.domain.model.PlanningMode
import com.xax.CryptoSavingsTracker.presentation.theme.CryptoSavingsTrackerTheme

/**
 * Segmented control for switching between Per Goal and Fixed Budget planning modes.
 */
@Composable
fun PlanningModeSegmentedControl(
    selectedMode: PlanningMode,
    onModeSelected: (PlanningMode) -> Unit,
    modifier: Modifier = Modifier
) {
    val modes = PlanningMode.entries

    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceVariant
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(4.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            modes.forEach { mode ->
                val isSelected = mode == selectedMode
                SegmentButton(
                    text = mode.displayName,
                    isSelected = isSelected,
                    onClick = { onModeSelected(mode) },
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
private fun SegmentButton(
    text: String,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val backgroundColor = if (isSelected) {
        MaterialTheme.colorScheme.primary
    } else {
        Color.Transparent
    }

    val textColor = if (isSelected) {
        MaterialTheme.colorScheme.onPrimary
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }

    Box(
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(backgroundColor)
            .clickable(onClick = onClick)
            .padding(vertical = 10.dp, horizontal = 16.dp)
            .semantics {
                role = Role.Tab
                contentDescription = if (isSelected) "$text, selected" else text
            },
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = if (isSelected) FontWeight.Medium else FontWeight.Normal,
            color = textColor
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun PlanningModeSegmentedControlPreview() {
    CryptoSavingsTrackerTheme {
        PlanningModeSegmentedControl(
            selectedMode = PlanningMode.PER_GOAL,
            onModeSelected = {},
            modifier = Modifier.padding(16.dp)
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun PlanningModeSegmentedControlFixedBudgetPreview() {
    CryptoSavingsTrackerTheme {
        PlanningModeSegmentedControl(
            selectedMode = PlanningMode.FIXED_BUDGET,
            onModeSelected = {},
            modifier = Modifier.padding(16.dp)
        )
    }
}
