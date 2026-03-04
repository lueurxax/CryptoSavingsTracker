package com.xax.CryptoSavingsTracker.presentation.theme

import androidx.compose.foundation.BorderStroke
import androidx.compose.material3.CardColors
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

object VisualComponentDefaults {
    @Composable
    fun planningHeaderCardColors(): CardColors {
        return CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    }

    @Composable
    fun planningGoalRowCardColors(): CardColors {
        return CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    }

    @Composable
    fun dashboardSummaryCardColors(): CardColors {
        return CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    }

    @Composable
    fun settingsSectionRowColors(): CardColors {
        return CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    }

    @Composable
    fun planningHeaderCardBorder(): BorderStroke {
        return BorderStroke(1.dp, planningSurfaceStroke())
    }

    @Composable
    fun planningGoalRowCardBorder(): BorderStroke {
        return BorderStroke(1.dp, planningSurfaceStroke())
    }

    @Composable
    fun dashboardSummaryCardBorder(): BorderStroke {
        return BorderStroke(1.dp, planningSurfaceStroke())
    }

    @Composable
    fun settingsSectionRowBorder(): BorderStroke {
        return BorderStroke(1.dp, planningSurfaceStroke())
    }

    @Composable
    fun planningHeaderCardElevation() = CardDefaults.cardElevation(
        defaultElevation = Elevation.card,
        pressedElevation = Elevation.none
    )

    @Composable
    fun planningGoalRowCardElevation() = CardDefaults.cardElevation(
        defaultElevation = Elevation.none,
        pressedElevation = Elevation.none
    )

    @Composable
    fun dashboardSummaryCardElevation() = CardDefaults.cardElevation(
        defaultElevation = Elevation.card,
        pressedElevation = Elevation.none
    )

    @Composable
    fun settingsSectionRowElevation() = CardDefaults.cardElevation(
        defaultElevation = Elevation.none,
        pressedElevation = Elevation.none
    )

    @Composable
    private fun planningSurfaceStroke(): Color {
        return MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.72f)
    }
}
