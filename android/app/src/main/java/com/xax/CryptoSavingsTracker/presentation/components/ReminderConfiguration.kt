package com.xax.CryptoSavingsTracker.presentation.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.domain.model.ReminderFrequency
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/**
 * Extension to get approximate days for a frequency (used for UI preview calculations).
 * Note: For monthly, iOS uses actual calendar months via DateComponents(month: 1).
 * For preview purposes, we use 30 days as an approximation.
 */
fun ReminderFrequency.approximateDays(): Int = when (this) {
    ReminderFrequency.WEEKLY -> 7
    ReminderFrequency.BIWEEKLY -> 14
    ReminderFrequency.MONTHLY -> 30
}

/**
 * Add days/month to date based on frequency.
 * Matches iOS DateComponents behavior where monthly adds actual month.
 */
fun LocalDate.plusFrequency(frequency: ReminderFrequency): LocalDate = when (frequency) {
    ReminderFrequency.WEEKLY -> this.plusDays(7)
    ReminderFrequency.BIWEEKLY -> this.plusDays(14)
    ReminderFrequency.MONTHLY -> this.plusMonths(1)
}

/**
 * Reminder configuration state
 */
data class ReminderState(
    val isEnabled: Boolean = false,
    val frequency: ReminderFrequency = ReminderFrequency.WEEKLY,
    val reminderTime: LocalTime = LocalTime.of(9, 0),
    val firstReminderDate: LocalDate? = null
)

/**
 * Reminder Configuration UI matching iOS ReminderConfigurationView
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReminderConfiguration(
    state: ReminderState,
    onStateChange: (ReminderState) -> Unit,
    startDate: LocalDate,
    deadline: LocalDate,
    modifier: Modifier = Modifier
) {
    var showTimePicker by remember { mutableStateOf(false) }
    var showDatePicker by remember { mutableStateOf(false) }

    // Calculate total reminders using proper frequency-based date addition
    val totalReminders = remember(state, startDate, deadline) {
        if (!state.isEnabled) return@remember 0
        var count = 0
        var currentDate = state.firstReminderDate ?: startDate
        while (currentDate <= deadline) {
            count++
            currentDate = currentDate.plusFrequency(state.frequency)
        }
        count
    }

    // Next reminder preview
    val nextReminderPreview = remember(state, startDate) {
        if (!state.isEnabled) return@remember null
        val baseDate = state.firstReminderDate ?: startDate
        baseDate.atTime(state.reminderTime)
            .format(DateTimeFormatter.ofPattern("MMM d, yyyy 'at' h:mm a"))
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Enable/Disable Toggle
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Enable Reminders",
                style = MaterialTheme.typography.bodyLarge
            )
            Switch(
                checked = state.isEnabled,
                onCheckedChange = { enabled ->
                    onStateChange(state.copy(isEnabled = enabled))
                }
            )
        }

        AnimatedVisibility(visible = state.isEnabled) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                // Frequency Selection
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "Reminder Frequency",
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Medium
                    )

                    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                        ReminderFrequency.entries.forEachIndexed { index, frequency ->
                            SegmentedButton(
                                selected = state.frequency == frequency,
                                onClick = { onStateChange(state.copy(frequency = frequency)) },
                                shape = SegmentedButtonDefaults.itemShape(
                                    index = index,
                                    count = ReminderFrequency.entries.size
                                )
                            ) {
                                Text(
                                    text = frequency.displayName(),
                                    style = MaterialTheme.typography.labelSmall
                                )
                            }
                        }
                    }
                }

                // Time Selection
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "Reminder Time",
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Medium
                    )

                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { showTimePicker = true },
                        shape = RoundedCornerShape(8.dp),
                        color = MaterialTheme.colorScheme.surfaceVariant
                    ) {
                        Row(
                            modifier = Modifier.padding(16.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    Icons.Default.Schedule,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary
                                )
                                Text(state.reminderTime.format(DateTimeFormatter.ofPattern("h:mm a")))
                            }
                        }
                    }
                }

                // First Reminder Date Selection
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "First Reminder Date",
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Medium
                    )

                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { showDatePicker = true },
                        shape = RoundedCornerShape(8.dp),
                        color = MaterialTheme.colorScheme.surfaceVariant
                    ) {
                        Row(
                            modifier = Modifier.padding(16.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    Icons.Default.CalendarMonth,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary
                                )
                                Text(
                                    (state.firstReminderDate ?: startDate)
                                        .format(DateTimeFormatter.ofPattern("MMM d, yyyy"))
                                )
                            }
                        }
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Subsequent reminders will follow the selected frequency",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )

                        if (state.firstReminderDate != null && state.firstReminderDate != startDate) {
                            TextButton(
                                onClick = { onStateChange(state.copy(firstReminderDate = null)) }
                            ) {
                                Text(
                                    text = "Reset",
                                    style = MaterialTheme.typography.labelSmall
                                )
                            }
                        }
                    }
                }

                // Schedule Preview
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                    color = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                Icons.Default.CalendarMonth,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(20.dp)
                            )
                            Text(
                                text = "Schedule Preview",
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.Medium
                            )
                        }

                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(
                                    text = "Pattern:",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Text(
                                    text = "${state.frequency.displayName()} reminders",
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.Medium
                                )
                            }

                            nextReminderPreview?.let { preview ->
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text(
                                        text = "Next:",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                    Text(
                                        text = preview,
                                        style = MaterialTheme.typography.labelSmall,
                                        fontWeight = FontWeight.Medium,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                }
                            }

                            if (totalReminders > 0) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text(
                                        text = "Total:",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                    Text(
                                        text = "$totalReminders reminder${if (totalReminders == 1) "" else "s"}",
                                        style = MaterialTheme.typography.labelSmall,
                                        fontWeight = FontWeight.Medium
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Time Picker Dialog
    if (showTimePicker) {
        val timePickerState = rememberTimePickerState(
            initialHour = state.reminderTime.hour,
            initialMinute = state.reminderTime.minute
        )

        AlertDialog(
            onDismissRequest = { showTimePicker = false },
            title = { Text("Select Reminder Time") },
            text = {
                TimePicker(state = timePickerState)
            },
            confirmButton = {
                TextButton(onClick = {
                    onStateChange(
                        state.copy(
                            reminderTime = LocalTime.of(
                                timePickerState.hour,
                                timePickerState.minute
                            )
                        )
                    )
                    showTimePicker = false
                }) {
                    Text("OK")
                }
            },
            dismissButton = {
                TextButton(onClick = { showTimePicker = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Date Picker Dialog
    if (showDatePicker) {
        val datePickerState = rememberDatePickerState(
            initialSelectedDateMillis = (state.firstReminderDate ?: startDate)
                .toEpochDay() * 24 * 60 * 60 * 1000
        )

        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    datePickerState.selectedDateMillis?.let { millis ->
                        val selectedDate = LocalDate.ofEpochDay(millis / (24 * 60 * 60 * 1000))
                        if (selectedDate >= startDate && selectedDate <= deadline) {
                            onStateChange(state.copy(firstReminderDate = selectedDate))
                        }
                    }
                    showDatePicker = false
                }) {
                    Text("OK")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) {
                    Text("Cancel")
                }
            }
        ) {
            DatePicker(state = datePickerState)
        }
    }
}
