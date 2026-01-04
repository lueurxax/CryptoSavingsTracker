package com.xax.CryptoSavingsTracker.presentation.theme

import androidx.compose.ui.unit.dp

/**
 * Design system elevation tokens for consistent shadow/depth hierarchy.
 *
 * Usage:
 * - `CardDefaults.cardElevation(defaultElevation = Elevation.card)`
 * - `.shadow(Elevation.tooltip, shape)`
 */
object Elevation {
    /** No elevation - 0dp. Flat surfaces */
    val none = 0.dp

    /** Card elevation - 2dp. Standard cards, list items */
    val card = 2.dp

    /** Raised elevation - 4dp. Floating action buttons, raised buttons */
    val raised = 4.dp

    /** Navigation elevation - 6dp. Bottom navigation, app bars */
    val navigation = 6.dp

    /** Tooltip elevation - 8dp. Tooltips, popovers, dropdown menus */
    val tooltip = 8.dp

    /** Modal elevation - 16dp. Bottom sheets, dialogs, full-screen modals */
    val modal = 16.dp
}
