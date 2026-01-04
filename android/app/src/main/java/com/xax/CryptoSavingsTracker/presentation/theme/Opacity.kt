package com.xax.CryptoSavingsTracker.presentation.theme

/**
 * Design system opacity tokens for consistent transparency levels.
 *
 * Usage:
 * - `color.copy(alpha = Opacity.disabled)` for disabled states
 * - `color.copy(alpha = Opacity.secondary)` for secondary text
 */
object Opacity {
    /** Fully transparent - 0% */
    const val transparent = 0f

    /** Disabled state - 38%. Material Design standard for disabled elements */
    const val disabled = 0.38f

    /** Scrim overlay - 32%. Background overlays, modal scrims */
    const val scrim = 0.32f

    /** Secondary content - 60%. Secondary text, icons, hints */
    const val secondary = 0.6f

    /** High emphasis - 87%. Material Design standard for high emphasis text */
    const val emphasis = 0.87f

    /** Fully opaque - 100% */
    const val full = 1f
}
