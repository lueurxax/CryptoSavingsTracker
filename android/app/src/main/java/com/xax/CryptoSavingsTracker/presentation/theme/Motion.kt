package com.xax.CryptoSavingsTracker.presentation.theme

import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing

/**
 * Design system motion tokens for consistent animations.
 *
 * Usage:
 * - `animateFloatAsState(targetValue, animationSpec = tween(Motion.normal))`
 * - `AnimatedVisibility(enter = fadeIn(animationSpec = tween(Motion.fast)))`
 */
object Motion {
    /** Instant - 0ms. No animation, immediate state change */
    const val instant = 0

    /** Fast - 150ms. Micro-interactions, state changes, button feedback */
    const val fast = 150

    /** Normal - 300ms. Standard transitions, most UI animations */
    const val normal = 300

    /** Slow - 500ms. Complex animations, page transitions, emphasis */
    const val slow = 500

    // Standard easing curves (Material Design)

    /** Standard easing - elements that begin and end at rest */
    val standardEasing = FastOutSlowInEasing

    /** Decelerate easing - elements entering the screen */
    val decelerateEasing = LinearOutSlowInEasing

    /** Accelerate easing - elements leaving the screen */
    val accelerateEasing = FastOutLinearInEasing
}
