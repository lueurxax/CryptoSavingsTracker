package com.xax.CryptoSavingsTracker.presentation.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat

/**
 * App-wide shape system integrated with MaterialTheme.
 * Access via MaterialTheme.shapes.small, MaterialTheme.shapes.medium, etc.
 */
val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(4.dp),   // Chips, small badges
    small = RoundedCornerShape(8.dp),        // Buttons, text fields
    medium = RoundedCornerShape(12.dp),      // Cards, list items
    large = RoundedCornerShape(16.dp),       // Bottom sheets, dialogs
    extraLarge = RoundedCornerShape(24.dp)   // Full-screen modals
)

private val LightColorScheme = lightColorScheme(
    primary = Primary,
    onPrimary = OnPrimary,
    primaryContainer = Primary.copy(alpha = 0.12f),
    onPrimaryContainer = Primary,
    secondary = Secondary,
    onSecondary = OnSecondary,
    secondaryContainer = Secondary.copy(alpha = 0.12f),
    onSecondaryContainer = Secondary,
    tertiary = InfoBlue,
    onTertiary = OnPrimary,
    background = Background,
    onBackground = OnBackground,
    surface = Surface,
    onSurface = OnSurface,
    surfaceVariant = Background,
    onSurfaceVariant = OnSurface.copy(alpha = 0.7f),
    error = NegativeRed,
    onError = OnPrimary,
    errorContainer = NegativeRed.copy(alpha = 0.12f),
    onErrorContainer = NegativeRed
)

private val DarkColorScheme = darkColorScheme(
    primary = PrimaryDark,
    onPrimary = OnPrimaryDark,
    primaryContainer = PrimaryDark.copy(alpha = 0.12f),
    onPrimaryContainer = PrimaryDark,
    secondary = SecondaryDark,
    onSecondary = OnSecondaryDark,
    secondaryContainer = SecondaryDark.copy(alpha = 0.12f),
    onSecondaryContainer = SecondaryDark,
    tertiary = PrimaryDark,
    onTertiary = OnPrimaryDark,
    background = BackgroundDark,
    onBackground = OnBackgroundDark,
    surface = SurfaceDark,
    onSurface = OnSurfaceDark,
    surfaceVariant = SurfaceDark,
    onSurfaceVariant = OnSurfaceDark.copy(alpha = 0.7f),
    error = NegativeRed,
    onError = OnPrimary,
    errorContainer = NegativeRed.copy(alpha = 0.12f),
    onErrorContainer = NegativeRed
)

@Composable
fun CryptoSavingsTrackerTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    // Dynamic color is available on Android 12+
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        shapes = AppShapes,
        content = content
    )
}
