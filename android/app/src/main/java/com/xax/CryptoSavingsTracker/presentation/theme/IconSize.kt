package com.xax.CryptoSavingsTracker.presentation.theme

import androidx.compose.ui.unit.dp

/**
 * Design system icon size tokens for consistent iconography.
 *
 * Usage:
 * - `Icon(imageVector = icon, modifier = Modifier.size(IconSize.standard))`
 */
object IconSize {
    /** Inline icons - 16dp. Within text, badges, chips, small indicators */
    val inline = 16.dp

    /** Small icons - 20dp. Buttons, list item trailing icons */
    val small = 20.dp

    /** Standard icons - 24dp. Navigation icons, most UI icons (Material default) */
    val standard = 24.dp

    /** Large icons - 32dp. Feature icons, emphasis, card headers */
    val large = 32.dp

    /** Hero icons - 48dp. Empty states, illustrations */
    val hero = 48.dp

    /** Feature icons - 64dp. Onboarding, splash elements, major illustrations */
    val feature = 64.dp
}
