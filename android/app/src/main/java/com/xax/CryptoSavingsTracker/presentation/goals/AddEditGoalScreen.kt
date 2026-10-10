package com.xax.CryptoSavingsTracker.presentation.goals

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.domain.navigation.NavigationJourney
import com.xax.CryptoSavingsTracker.presentation.navigation.NavigationRuntimeViewModel
import com.xax.CryptoSavingsTracker.domain.model.ReminderFrequency
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

internal enum class GoalReminderPermissionState {
    NOT_REQUIRED,
    GRANTED,
    REQUIRED
}

internal enum class GoalReminderEnableEffect {
    ENABLE,
    REQUEST_PERMISSION
}

internal data class GoalReminderPermissionResult(
    val enableReminder: Boolean,
    val showDenial: Boolean
)

internal const val GOAL_REMINDER_SWITCH_TAG = "goal_reminder_switch"
internal const val GOAL_REMINDER_PERMISSION_DENIED_TAG = "goal_reminder_permission_denied"

internal fun goalReminderPermissionState(
    sdkInt: Int,
    isPermissionGranted: Boolean
): GoalReminderPermissionState = when {
    sdkInt < 33 -> GoalReminderPermissionState.NOT_REQUIRED
    isPermissionGranted -> GoalReminderPermissionState.GRANTED
    else -> GoalReminderPermissionState.REQUIRED
}

internal fun goalReminderEnableEffect(
    permissionState: GoalReminderPermissionState
): GoalReminderEnableEffect = when (permissionState) {
    GoalReminderPermissionState.NOT_REQUIRED,
    GoalReminderPermissionState.GRANTED -> GoalReminderEnableEffect.ENABLE
    GoalReminderPermissionState.REQUIRED -> GoalReminderEnableEffect.REQUEST_PERMISSION
}

internal fun goalReminderPermissionResult(granted: Boolean) = GoalReminderPermissionResult(
    enableReminder = granted,
    showDenial = !granted
)

internal inline fun applyGoalReminderPermissionResult(
    granted: Boolean,
    onPermissionStateChanged: (GoalReminderPermissionState) -> Unit,
    onDenialChanged: (Boolean) -> Unit,
    onReminderEnabledChanged: (Boolean) -> Unit
) {
    onPermissionStateChanged(
        if (granted) GoalReminderPermissionState.GRANTED else GoalReminderPermissionState.REQUIRED
    )
    val result = goalReminderPermissionResult(granted)
    onDenialChanged(result.showDenial)
    onReminderEnabledChanged(result.enableReminder)
}

internal fun reconcileEnabledReminderWithPermission(
    reminderEnabled: Boolean,
    permissionState: GoalReminderPermissionState
): GoalReminderPermissionResult {
    val permissionMissing = reminderEnabled &&
        permissionState == GoalReminderPermissionState.REQUIRED
    return GoalReminderPermissionResult(
        enableReminder = reminderEnabled && !permissionMissing,
        showDenial = permissionMissing
    )
}

internal fun currentGoalReminderPermissionState(context: Context): GoalReminderPermissionState =
    goalReminderPermissionState(
        sdkInt = Build.VERSION.SDK_INT,
        isPermissionGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    )

internal fun goalReminderSaveResult(
    reminderEnabled: Boolean,
    readPermissionState: () -> GoalReminderPermissionState
): GoalReminderPermissionResult = reconcileEnabledReminderWithPermission(
    reminderEnabled = reminderEnabled,
    permissionState = readPermissionState()
)

internal class GoalReminderPermissionLifecycleObserver(
    private val readPermissionState: () -> GoalReminderPermissionState,
    private val onPermissionStateChanged: (GoalReminderPermissionState) -> Unit
) : DefaultLifecycleObserver {
    override fun onResume(owner: LifecycleOwner) {
        onPermissionStateChanged(readPermissionState())
    }
}

@Composable
internal fun GoalReminderPermissionLifecycleEffect(
    readPermissionState: () -> GoalReminderPermissionState,
    onPermissionStateChanged: (GoalReminderPermissionState) -> Unit,
    lifecycleOwner: LifecycleOwner = LocalLifecycleOwner.current
) {
    DisposableEffect(lifecycleOwner, readPermissionState, onPermissionStateChanged) {
        val observer = GoalReminderPermissionLifecycleObserver(
            readPermissionState = readPermissionState,
            onPermissionStateChanged = onPermissionStateChanged
        )
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddEditGoalScreen(
    navController: NavController,
    runtimeViewModel: NavigationRuntimeViewModel = hiltViewModel(),
    viewModel: AddEditGoalViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current
    var hasStartedFlow by remember { mutableStateOf(false) }
    var reminderPermissionDenied by remember { mutableStateOf(false) }
    var reminderPermissionState by remember(context) {
        mutableStateOf(currentGoalReminderPermissionState(context))
    }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        applyGoalReminderPermissionResult(
            granted = granted,
            onPermissionStateChanged = { reminderPermissionState = it },
            onDenialChanged = { reminderPermissionDenied = it },
            onReminderEnabledChanged = viewModel::updateReminderEnabled
        )
    }

    GoalReminderPermissionLifecycleEffect(
        readPermissionState = { currentGoalReminderPermissionState(context) },
        onPermissionStateChanged = { refreshedState ->
            reminderPermissionState = refreshedState
        }
    )

    LaunchedEffect(uiState.isEditMode) {
        if (!hasStartedFlow) {
            hasStartedFlow = true
            runtimeViewModel.telemetryTracker.flowStarted(
                journeyId = NavigationJourney.GOAL_CREATE_EDIT,
                entryPoint = if (uiState.isEditMode) "edit_goal_screen" else "add_goal_screen"
            )
        }
    }

    // Navigate back when saved
    LaunchedEffect(uiState.isSaved) {
        if (uiState.isSaved) {
            runtimeViewModel.telemetryTracker.flowCompleted(
                journeyId = NavigationJourney.GOAL_CREATE_EDIT,
                result = "saved"
            )
            runtimeViewModel.telemetryTracker.recoveryCompleted(
                journeyId = NavigationJourney.GOAL_CREATE_EDIT,
                recoveryPath = "save_goal",
                success = true
            )
            navController.popBackStack()
        }
    }

    // Show error in snackbar
    LaunchedEffect(uiState.error) {
        uiState.error?.let { error ->
            snackbarHostState.showSnackbar(error)
            runtimeViewModel.telemetryTracker.recoveryCompleted(
                journeyId = NavigationJourney.GOAL_CREATE_EDIT,
                recoveryPath = "save_error",
                success = false
            )
            viewModel.clearError()
        }
    }

    LaunchedEffect(uiState.nameError, uiState.targetAmountError, uiState.deadlineError) {
        if (uiState.nameError != null || uiState.targetAmountError != null || uiState.deadlineError != null) {
            runtimeViewModel.telemetryTracker.recoveryCompleted(
                journeyId = NavigationJourney.GOAL_CREATE_EDIT,
                recoveryPath = "validation_error",
                success = false
            )
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (uiState.isEditMode) "Edit Goal" else "Add Goal") },
                navigationIcon = {
                    IconButton(onClick = {
                        runtimeViewModel.telemetryTracker.cancelled(
                            journeyId = NavigationJourney.GOAL_CREATE_EDIT,
                            isDirty = true,
                            cancelStage = "back_navigation"
                        )
                        navController.popBackStack()
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { paddingValues ->
        if (uiState.isLoading && uiState.isEditMode && uiState.name.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues)
                    .padding(16.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Name field
                OutlinedTextField(
                    value = uiState.name,
                    onValueChange = viewModel::updateName,
                    label = { Text("Goal Name") },
                    placeholder = { Text("e.g., Emergency Fund") },
                    modifier = Modifier.fillMaxWidth(),
                    isError = uiState.nameError != null,
                    supportingText = uiState.nameError?.let { { Text(it) } },
                    singleLine = true
                )

                // Target Amount with Currency
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    // Currency dropdown
                    CurrencyDropdown(
                        selectedCurrency = uiState.currency,
                        onCurrencySelected = viewModel::updateCurrency,
                        modifier = Modifier.weight(0.35f)
                    )

                    // Target amount
                    OutlinedTextField(
                        value = uiState.targetAmount,
                        onValueChange = viewModel::updateTargetAmount,
                        label = { Text("Target Amount") },
                        placeholder = { Text("10000") },
                        modifier = Modifier.weight(0.65f),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        isError = uiState.targetAmountError != null,
                        supportingText = uiState.targetAmountError?.let { { Text(it) } },
                        singleLine = true
                    )
                }

                // Start Date
                DatePickerField(
                    label = "Start Date",
                    selectedDate = uiState.startDate,
                    onDateSelected = viewModel::updateStartDate
                )

                // Deadline
                DatePickerField(
                    label = "Deadline",
                    selectedDate = uiState.deadline,
                    onDateSelected = viewModel::updateDeadline,
                    error = uiState.deadlineError
                )

                // Emoji field
                OutlinedTextField(
                    value = uiState.emoji ?: "",
                    onValueChange = { viewModel.updateEmoji(it.takeIf { it.isNotEmpty() }) },
                    label = { Text("Emoji (optional)") },
                    placeholder = { Text("e.g., 🎯 or 🏠") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )

                // Link field
                OutlinedTextField(
                    value = uiState.link,
                    onValueChange = viewModel::updateLink,
                    label = { Text("Link (optional)") },
                    placeholder = { Text("e.g., https://example.com") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri)
                )

                // Reminders section
                GoalReminderPermissionToggle(
                    checked = uiState.reminderEnabled,
                    permissionState = reminderPermissionState,
                    permissionDenied = reminderPermissionDenied,
                    onRequestPermission = {
                        notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    },
                    onReminderEnabledChange = { enabled ->
                        reminderPermissionDenied = false
                        viewModel.updateReminderEnabled(enabled)
                    },
                    onPermissionMismatch = {
                        reminderPermissionDenied = true
                    }
                )

                if (uiState.reminderEnabled) {
                    ReminderFrequencyDropdown(
                        selectedFrequency = uiState.reminderFrequency,
                        onFrequencySelected = viewModel::updateReminderFrequency
                    )
                }

                // Description
                OutlinedTextField(
                    value = uiState.description,
                    onValueChange = viewModel::updateDescription,
                    label = { Text("Description (optional)") },
                    placeholder = { Text("Add any notes about this goal...") },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(120.dp),
                    maxLines = 5
                )

                Spacer(modifier = Modifier.height(8.dp))

                // Save button
                Button(
                    onClick = {
                        val reconciliation = goalReminderSaveResult(
                            reminderEnabled = uiState.reminderEnabled,
                            readPermissionState = {
                                currentGoalReminderPermissionState(context).also { refreshedState ->
                                    reminderPermissionState = refreshedState
                                }
                            }
                        )
                        if (reconciliation.showDenial) {
                            reminderPermissionDenied = true
                            viewModel.updateReminderEnabled(false)
                        } else {
                            viewModel.saveGoal()
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !uiState.isLoading
                ) {
                    if (uiState.isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.padding(end = 8.dp),
                            color = MaterialTheme.colorScheme.onPrimary
                        )
                    }
                    Text(if (uiState.isEditMode) "Save Changes" else "Create Goal")
                }
            }
        }
    }
}

@Composable
internal fun GoalReminderPermissionToggle(
    checked: Boolean,
    permissionState: GoalReminderPermissionState,
    permissionDenied: Boolean,
    onRequestPermission: () -> Unit,
    onReminderEnabledChange: (Boolean) -> Unit,
    onPermissionMismatch: () -> Unit
) {
    val reconciliation = reconcileEnabledReminderWithPermission(
        reminderEnabled = checked,
        permissionState = permissionState
    )
    LaunchedEffect(reconciliation) {
        if (reconciliation.showDenial) {
            onReminderEnabledChange(false)
            onPermissionMismatch()
        }
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
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
                checked = checked,
                onCheckedChange = { enable ->
                    when {
                        !enable -> onReminderEnabledChange(false)
                        goalReminderEnableEffect(permissionState) == GoalReminderEnableEffect.ENABLE ->
                            onReminderEnabledChange(true)
                        else -> onRequestPermission()
                    }
                },
                modifier = Modifier.testTag(GOAL_REMINDER_SWITCH_TAG)
            )
        }

        if (permissionDenied) {
            Text(
                text = "Notification permission was denied. Reminders remain disabled.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.testTag(GOAL_REMINDER_PERMISSION_DENIED_TAG)
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CurrencyDropdown(
    selectedCurrency: String,
    onCurrencySelected: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    var expanded by remember { mutableStateOf(false) }

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = modifier
    ) {
        OutlinedTextField(
            value = selectedCurrency,
            onValueChange = {},
            readOnly = true,
            label = { Text("Currency") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier.menuAnchor(MenuAnchorType.PrimaryNotEditable)
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            availableCurrencies.forEach { currency ->
                DropdownMenuItem(
                    text = { Text(currency) },
                    onClick = {
                        onCurrencySelected(currency)
                        expanded = false
                    }
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DatePickerField(
    label: String,
    selectedDate: LocalDate,
    onDateSelected: (LocalDate) -> Unit,
    error: String? = null
) {
    var showDatePicker by remember { mutableStateOf(false) }
    val dateFormatter = remember { DateTimeFormatter.ofPattern("MMM d, yyyy") }

    OutlinedTextField(
        value = selectedDate.format(dateFormatter),
        onValueChange = {},
        readOnly = true,
        label = { Text(label) },
        trailingIcon = {
            IconButton(onClick = { showDatePicker = true }) {
                Icon(Icons.Default.DateRange, contentDescription = "Select date")
            }
        },
        modifier = Modifier.fillMaxWidth(),
        isError = error != null,
        supportingText = error?.let { { Text(it) } }
    )

    if (showDatePicker) {
        val datePickerState = rememberDatePickerState(
            initialSelectedDateMillis = selectedDate
                .atStartOfDay(ZoneId.systemDefault())
                .toInstant()
                .toEpochMilli()
        )

        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        datePickerState.selectedDateMillis?.let { millis ->
                            val date = Instant.ofEpochMilli(millis)
                                .atZone(ZoneId.systemDefault())
                                .toLocalDate()
                            onDateSelected(date)
                        }
                        showDatePicker = false
                    }
                ) {
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReminderFrequencyDropdown(
    selectedFrequency: ReminderFrequency?,
    onFrequencySelected: (ReminderFrequency) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it }
    ) {
        OutlinedTextField(
            value = selectedFrequency?.displayName() ?: "Select frequency",
            onValueChange = {},
            readOnly = true,
            label = { Text("Reminder Frequency") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(MenuAnchorType.PrimaryNotEditable)
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            ReminderFrequency.entries.forEach { frequency ->
                DropdownMenuItem(
                    text = { Text(frequency.displayName()) },
                    onClick = {
                        onFrequencySelected(frequency)
                        expanded = false
                    }
                )
            }
        }
    }
}
