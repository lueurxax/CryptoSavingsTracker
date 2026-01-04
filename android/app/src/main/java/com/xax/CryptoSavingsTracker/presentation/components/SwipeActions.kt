package com.xax.CryptoSavingsTracker.presentation.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleGreen
import com.xax.CryptoSavingsTracker.presentation.theme.AccessibleRed
import kotlin.math.roundToInt

/**
 * Swipe action configuration
 */
data class SwipeAction(
    val icon: ImageVector,
    val label: String,
    val color: Color,
    val onClick: () -> Unit
)

/**
 * Swipeable list item with reveal actions
 * Supports left and right swipe gestures with customizable actions
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SwipeableListItem(
    modifier: Modifier = Modifier,
    leftAction: SwipeAction? = null,
    rightAction: SwipeAction? = null,
    content: @Composable () -> Unit
) {
    var offsetX by remember { mutableFloatStateOf(0f) }
    val haptic = LocalHapticFeedback.current
    val density = LocalDensity.current
    val actionWidth = with(density) { 80.dp.toPx() }

    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { dismissValue ->
            when (dismissValue) {
                SwipeToDismissBoxValue.StartToEnd -> {
                    leftAction?.onClick?.invoke()
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    false // Don't dismiss, just trigger action
                }
                SwipeToDismissBoxValue.EndToStart -> {
                    rightAction?.onClick?.invoke()
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    false // Don't dismiss, just trigger action
                }
                SwipeToDismissBoxValue.Settled -> true
            }
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        modifier = modifier,
        backgroundContent = {
            val direction = dismissState.dismissDirection

            val backgroundColor by animateColorAsState(
                targetValue = when (direction) {
                    SwipeToDismissBoxValue.StartToEnd -> leftAction?.color ?: Color.Transparent
                    SwipeToDismissBoxValue.EndToStart -> rightAction?.color ?: Color.Transparent
                    else -> Color.Transparent
                },
                label = "background_color"
            )

            val iconScale by animateFloatAsState(
                targetValue = if (dismissState.targetValue != SwipeToDismissBoxValue.Settled) 1.2f else 1f,
                label = "icon_scale"
            )

            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .background(backgroundColor)
                    .padding(horizontal = 20.dp),
                horizontalArrangement = when (direction) {
                    SwipeToDismissBoxValue.StartToEnd -> Arrangement.Start
                    SwipeToDismissBoxValue.EndToStart -> Arrangement.End
                    else -> Arrangement.Center
                },
                verticalAlignment = Alignment.CenterVertically
            ) {
                when (direction) {
                    SwipeToDismissBoxValue.StartToEnd -> {
                        leftAction?.let { action ->
                            Icon(
                                imageVector = action.icon,
                                contentDescription = action.label,
                                tint = Color.White,
                                modifier = Modifier.scale(iconScale)
                            )
                        }
                    }
                    SwipeToDismissBoxValue.EndToStart -> {
                        rightAction?.let { action ->
                            Icon(
                                imageVector = action.icon,
                                contentDescription = action.label,
                                tint = Color.White,
                                modifier = Modifier.scale(iconScale)
                            )
                        }
                    }
                    else -> {}
                }
            }
        },
        enableDismissFromStartToEnd = leftAction != null,
        enableDismissFromEndToStart = rightAction != null
    ) {
        content()
    }
}

/**
 * Predefined swipe actions for common use cases
 */
object SwipeActions {
    fun delete(onDelete: () -> Unit) = SwipeAction(
        icon = Icons.Default.Delete,
        label = "Delete",
        color = AccessibleRed,
        onClick = onDelete
    )

    fun edit(onEdit: () -> Unit) = SwipeAction(
        icon = Icons.Default.Edit,
        label = "Edit",
        color = Color(0xFF2196F3), // Blue
        onClick = onEdit
    )

    fun share(onShare: () -> Unit) = SwipeAction(
        icon = Icons.Default.Share,
        label = "Share",
        color = AccessibleGreen,
        onClick = onShare
    )
}

/**
 * Example usage: Transaction list item with swipe actions
 */
@Composable
fun SwipeableTransactionItem(
    modifier: Modifier = Modifier,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    content: @Composable () -> Unit
) {
    SwipeableListItem(
        modifier = modifier,
        leftAction = SwipeActions.edit(onEdit),
        rightAction = SwipeActions.delete(onDelete),
        content = content
    )
}

/**
 * Example usage: Asset list item with swipe to delete
 */
@Composable
fun SwipeableAssetItem(
    modifier: Modifier = Modifier,
    onDelete: () -> Unit,
    content: @Composable () -> Unit
) {
    SwipeableListItem(
        modifier = modifier,
        rightAction = SwipeActions.delete(onDelete),
        content = content
    )
}

/**
 * Example usage: Goal list item with swipe actions
 */
@Composable
fun SwipeableGoalItem(
    modifier: Modifier = Modifier,
    onEdit: () -> Unit,
    onShare: () -> Unit,
    content: @Composable () -> Unit
) {
    SwipeableListItem(
        modifier = modifier,
        leftAction = SwipeActions.share(onShare),
        rightAction = SwipeActions.edit(onEdit),
        content = content
    )
}
