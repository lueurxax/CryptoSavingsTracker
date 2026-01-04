package com.xax.CryptoSavingsTracker.presentation.planning.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.domain.model.ScheduledGoalBlock

/**
 * A horizontal timeline visualization showing scheduled goal blocks
 * with a "You are here" indicator.
 */
@Composable
fun TimelineStepper(
    blocks: List<ScheduledGoalBlock>,
    currentPaymentNumber: Int,
    modifier: Modifier = Modifier
) {
    if (blocks.isEmpty()) return

    val totalPayments = blocks.sumOf { it.paymentCount }
    if (totalPayments == 0) return

    Column(
        modifier = modifier.fillMaxWidth()
    ) {
        // "You are here" label above the timeline
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(32.dp)
        ) {
            val progress = currentPaymentNumber.toFloat() / totalPayments
            val animatedProgress by animateFloatAsState(
                targetValue = progress,
                animationSpec = tween(durationMillis = 300),
                label = "progressAnimation"
            )

            // Position the indicator
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.BottomStart)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth()
                ) {
                    // Calculate spacer width based on animated progress
                    if (animatedProgress > 0.05f) {
                        Spacer(modifier = Modifier.weight(animatedProgress))
                    }

                    // "You are here" indicator
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.padding(horizontal = 4.dp)
                    ) {
                        Text(
                            text = "You are here",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                            fontWeight = FontWeight.Medium
                        )
                        Icon(
                            imageVector = Icons.Default.LocationOn,
                            contentDescription = "Current position",
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(20.dp)
                        )
                    }

                    // Fill remaining space
                    if (animatedProgress < 0.95f) {
                        Spacer(modifier = Modifier.weight(1f - animatedProgress))
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(4.dp))

        // Timeline track with goal segments
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(24.dp)
        ) {
            // Background track
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp)
                    .align(Alignment.Center)
                    .clip(RoundedCornerShape(4.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant)
            )

            // Goal segments
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp)
                    .align(Alignment.Center)
                    .clip(RoundedCornerShape(4.dp)),
                horizontalArrangement = Arrangement.Start
            ) {
                blocks.forEachIndexed { index, block ->
                    val weight = block.paymentCount.toFloat() / totalPayments
                    val color = getBlockColor(index, block.isComplete)

                    Box(
                        modifier = Modifier
                            .weight(weight)
                            .height(8.dp)
                            .background(color)
                    )
                }
            }

            // Progress indicator dot
            val progressFraction = currentPaymentNumber.toFloat() / totalPayments
            val animatedFraction by animateFloatAsState(
                targetValue = progressFraction,
                animationSpec = tween(durationMillis = 300),
                label = "dotAnimation"
            )

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.Center)
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth(animatedFraction.coerceIn(0f, 1f))
                        .align(Alignment.CenterStart)
                ) {
                    Box(
                        modifier = Modifier
                            .size(16.dp)
                            .align(Alignment.CenterEnd)
                            .offset(x = 8.dp)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.primary)
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Goal labels below the timeline
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Start
        ) {
            blocks.forEachIndexed { index, block ->
                val weight = block.paymentCount.toFloat() / totalPayments

                Box(
                    modifier = Modifier.weight(weight),
                    contentAlignment = Alignment.TopCenter
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.padding(horizontal = 2.dp)
                    ) {
                        // Emoji or abbreviated name
                        if (block.emoji?.isNotEmpty() == true) {
                            Text(
                                text = block.emoji,
                                style = MaterialTheme.typography.bodySmall
                            )
                        }

                        // Goal name (abbreviated if too long)
                        Text(
                            text = block.goalName,
                            style = MaterialTheme.typography.labelSmall,
                            color = if (block.isComplete) {
                                Color(0xFF4CAF50)
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            textAlign = TextAlign.Center
                        )

                        // Payment count
                        Text(
                            text = "${block.paymentCount}mo",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                        )
                    }
                }
            }
        }
    }
}

/**
 * Get color for a timeline block based on its index and completion status.
 */
@Composable
private fun getBlockColor(index: Int, isComplete: Boolean): Color {
    if (isComplete) {
        return Color(0xFF4CAF50) // Green for completed
    }

    // Cycle through accent colors for different goals
    val colors = listOf(
        MaterialTheme.colorScheme.primary,
        MaterialTheme.colorScheme.secondary,
        MaterialTheme.colorScheme.tertiary,
        Color(0xFFFF9800), // Orange
        Color(0xFF9C27B0), // Purple
        Color(0xFF00BCD4)  // Cyan
    )

    return colors[index % colors.size]
}

/**
 * Compact version of the timeline for smaller spaces.
 */
@Composable
fun CompactTimelineStepper(
    blocks: List<ScheduledGoalBlock>,
    currentPaymentNumber: Int,
    modifier: Modifier = Modifier
) {
    if (blocks.isEmpty()) return

    val totalPayments = blocks.sumOf { it.paymentCount }
    if (totalPayments == 0) return

    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(12.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant),
        horizontalArrangement = Arrangement.Start
    ) {
        val progressFraction = currentPaymentNumber.toFloat() / totalPayments

        blocks.forEachIndexed { index, block ->
            val weight = block.paymentCount.toFloat() / totalPayments
            val color = getBlockColor(index, block.isComplete)

            Box(
                modifier = Modifier
                    .weight(weight)
                    .height(12.dp)
                    .background(color.copy(alpha = 0.6f))
            )
        }
    }

    // Progress overlay
    val animatedProgress by animateFloatAsState(
        targetValue = currentPaymentNumber.toFloat() / totalPayments,
        animationSpec = tween(durationMillis = 300),
        label = "compactProgress"
    )

    Box(
        modifier = modifier
            .fillMaxWidth(animatedProgress.coerceIn(0f, 1f))
            .height(12.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(MaterialTheme.colorScheme.primary)
    )
}
