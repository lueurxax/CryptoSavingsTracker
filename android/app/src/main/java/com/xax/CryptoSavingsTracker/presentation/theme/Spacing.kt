package com.xax.CryptoSavingsTracker.presentation.theme

import androidx.compose.ui.unit.dp

/**
 * Design system spacing tokens following a 4dp base grid.
 *
 * Usage:
 * - `.padding(Spacing.md)` for standard content padding
 * - `Arrangement.spacedBy(Spacing.sm)` for list item gaps
 * - `Spacer(modifier = Modifier.height(Spacing.lg))` for section breaks
 */
object Spacing {
    /** No spacing - 0dp */
    val none = 0.dp

    /** Extra extra small - 4dp. Minimal gaps, tight lists, divider margins */
    val xxs = 4.dp

    /** Extra small - 8dp. Icon-to-text gaps, chip internal padding */
    val xs = 8.dp

    /** Small - 12dp. List item internal spacing, form field gaps */
    val sm = 12.dp

    /** Medium - 16dp. Standard content padding, card padding */
    val md = 16.dp

    /** Large - 24dp. Section separators, major content gaps */
    val lg = 24.dp

    /** Extra large - 32dp. Screen section spacing */
    val xl = 32.dp

    /** Extra extra large - 48dp. Large section dividers, empty state spacing */
    val xxl = 48.dp

    /** Extra extra extra large - 64dp. Hero spacing, major visual breaks */
    val xxxl = 64.dp
}
