package com.xax.CryptoSavingsTracker.presentation.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.xax.CryptoSavingsTracker.R
import com.xax.CryptoSavingsTracker.presentation.navigation.Screen

/**
 * Standardized spacing for the onboarding flow.
 */
private object OnboardingSpacing {
    val ScreenPadding = 24.dp
    val ContentPadding = 32.dp
    val ItemSpacing = 16.dp
    val SectionSpacing = 24.dp
}

/**
 * Test tags for onboarding elements.
 */
object OnboardingTestTags {
    const val SCREEN_ROOT = "onboarding_screen"
    const val PROGRESS_BAR = "onboarding_progress"
    const val BACK_BUTTON = "onboarding_back"
    const val NEXT_BUTTON = "onboarding_next"
    const val SKIP_BUTTON = "onboarding_skip"
    const val CONTENT_AREA = "onboarding_content"
}

/**
 * Onboarding flow matching iOS implementation.
 * 5 steps: Welcome, Profile, Goal Template, Asset Selection, Complete
 */
@Composable
fun OnboardingScreen(
    navController: NavController,
    viewModel: OnboardingViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()

    // Handle one-time navigation events
    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is OnboardingEvent.NavigateToDashboard -> {
                    navController.navigate(Screen.Dashboard.route) {
                        launchSingleTop = true
                        popUpTo(Screen.Onboarding.route) { inclusive = true }
                    }
                }
            }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .testTag(OnboardingTestTags.SCREEN_ROOT)
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        MaterialTheme.colorScheme.primary.copy(alpha = 0.1f),
                        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
                    )
                )
            )
    ) {
        Column(
            modifier = Modifier.fillMaxSize()
        ) {
            // Progress indicator
            OnboardingProgressIndicator(
                currentStep = uiState.currentStep,
                totalSteps = 5,
                modifier = Modifier
                    .padding(horizontal = OnboardingSpacing.ScreenPadding, vertical = 16.dp)
                    .testTag(OnboardingTestTags.PROGRESS_BAR)
            )

            // Main content with animation
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) {
                AnimatedContent(
                    targetState = uiState.currentStep,
                    transitionSpec = {
                        if (targetState > initialState) {
                            slideInHorizontally { it } togetherWith slideOutHorizontally { -it }
                        } else {
                            slideInHorizontally { -it } togetherWith slideOutHorizontally { it }
                        }
                    },
                    label = "onboarding_step",
                    modifier = Modifier.testTag(OnboardingTestTags.CONTENT_AREA)
                ) { step ->
                    // Step 3 (Assets) uses LazyColumn for performance, others use verticalScroll
                    if (step == 3) {
                        AssetSelectionStep(
                            assets = uiState.availableAssets,
                            selectedAssets = uiState.selectedAssets,
                            onAssetToggled = viewModel::toggleAsset
                        )
                    } else {
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .verticalScroll(rememberScrollState())
                                .padding(horizontal = OnboardingSpacing.ScreenPadding, vertical = OnboardingSpacing.ContentPadding),
                            verticalArrangement = Arrangement.spacedBy(OnboardingSpacing.ContentPadding)
                        ) {
                            when (step) {
                                0 -> WelcomeStep()
                                1 -> ProfileStep(
                                    experienceLevel = uiState.experienceLevel,
                                    onExperienceLevelChanged = viewModel::setExperienceLevel
                                )
                                2 -> GoalTemplateStep(
                                    selectedTemplate = uiState.selectedTemplate,
                                    onTemplateSelected = viewModel::selectTemplate
                                )
                                4 -> CompletionStep(
                                    selectedTemplate = uiState.selectedTemplate
                                )
                            }
                        }
                    }
                }
            }

            // Navigation buttons
            OnboardingNavigation(
                currentStep = uiState.currentStep,
                canProceed = uiState.canProceed,
                isLastStep = uiState.currentStep == 4,
                onNext = viewModel::nextStep,
                onPrevious = viewModel::previousStep,
                onSkip = viewModel::skip,
                modifier = Modifier.padding(horizontal = OnboardingSpacing.ScreenPadding, vertical = OnboardingSpacing.SectionSpacing)
            )
        }
    }
}

@Composable
private fun OnboardingProgressIndicator(
    currentStep: Int,
    totalSteps: Int,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            repeat(totalSteps) { index ->
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(4.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(
                            if (index <= currentStep)
                                MaterialTheme.colorScheme.primary
                            else
                                MaterialTheme.colorScheme.outlineVariant
                        )
                )
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = stepTitle(currentStep),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = stringResource(R.string.onboarding_step_progress, currentStep + 1, totalSteps),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun stepTitle(step: Int): String = when (step) {
    0 -> stringResource(R.string.onboarding_step_welcome)
    1 -> stringResource(R.string.onboarding_step_profile)
    2 -> stringResource(R.string.onboarding_step_goal)
    3 -> stringResource(R.string.onboarding_step_assets)
    4 -> stringResource(R.string.onboarding_step_ready)
    else -> ""
}

@Composable
private fun WelcomeStep() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(OnboardingSpacing.SectionSpacing)
    ) {
        Icon(
            imageVector = Icons.Default.Savings,
            contentDescription = null,
            modifier = Modifier.size(80.dp),
            tint = MaterialTheme.colorScheme.primary
        )

        Text(
            text = stringResource(R.string.onboarding_welcome_title),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )

        Text(
            text = stringResource(R.string.onboarding_welcome_description),
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(OnboardingSpacing.ItemSpacing))

        FeatureItem(
            icon = Icons.Default.TrackChanges,
            title = stringResource(R.string.onboarding_feature_track_goals_title),
            description = stringResource(R.string.onboarding_feature_track_goals_desc)
        )

        FeatureItem(
            icon = Icons.Default.AccountBalance,
            title = stringResource(R.string.onboarding_feature_multiple_assets_title),
            description = stringResource(R.string.onboarding_feature_multiple_assets_desc)
        )

        FeatureItem(
            icon = Icons.Default.Notifications,
            title = stringResource(R.string.onboarding_feature_smart_reminders_title),
            description = stringResource(R.string.onboarding_feature_smart_reminders_desc)
        )
    }
}

@Composable
private fun FeatureItem(
    icon: ImageVector,
    title: String,
    description: String
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(OnboardingSpacing.ItemSpacing),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primaryContainer),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary
            )
        }
        Column {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun ProfileStep(
    experienceLevel: ExperienceLevel,
    onExperienceLevelChanged: (ExperienceLevel) -> Unit
) {
    Column(
        verticalArrangement = Arrangement.spacedBy(OnboardingSpacing.SectionSpacing)
    ) {
        Text(
            text = stringResource(R.string.onboarding_profile_title),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        Text(
            text = stringResource(R.string.onboarding_profile_subtitle),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = stringResource(R.string.onboarding_profile_experience_label),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Medium
        )

        ExperienceLevel.entries.forEach { level ->
            ExperienceLevelCard(
                level = level,
                isSelected = experienceLevel == level,
                onClick = { onExperienceLevelChanged(level) }
            )
        }
    }
}

@Composable
private fun ExperienceLevelCard(
    level: ExperienceLevel,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected)
                MaterialTheme.colorScheme.primaryContainer
            else
                MaterialTheme.colorScheme.surface
        ),
        border = if (isSelected)
            CardDefaults.outlinedCardBorder().copy(
                brush = Brush.linearGradient(
                    colors = listOf(
                        MaterialTheme.colorScheme.primary,
                        MaterialTheme.colorScheme.primary
                    )
                )
            )
        else null,
        modifier = Modifier
            .fillMaxWidth()
            .semantics {
                role = Role.RadioButton
            }
            .testTag("experience_level_${level.name}")
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(OnboardingSpacing.ItemSpacing),
            horizontalArrangement = Arrangement.spacedBy(OnboardingSpacing.ItemSpacing),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = level.icon,
                contentDescription = null,
                tint = if (isSelected)
                    MaterialTheme.colorScheme.primary
                else
                    MaterialTheme.colorScheme.onSurfaceVariant
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(level.titleResId),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    text = stringResource(level.descriptionResId),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (isSelected) {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = "Selected",
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}

@Composable
private fun GoalTemplateStep(
    selectedTemplate: GoalTemplate?,
    onTemplateSelected: (GoalTemplate) -> Unit
) {
    Column(
        verticalArrangement = Arrangement.spacedBy(OnboardingSpacing.SectionSpacing)
    ) {
        Text(
            text = stringResource(R.string.onboarding_goals_title),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        Text(
            text = stringResource(R.string.onboarding_goals_subtitle),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        GoalTemplate.entries.forEach { template ->
            GoalTemplateCard(
                template = template,
                isSelected = selectedTemplate == template,
                onClick = { onTemplateSelected(template) }
            )
        }
    }
}

@Composable
private fun GoalTemplateCard(
    template: GoalTemplate,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected)
                MaterialTheme.colorScheme.primaryContainer
            else
                MaterialTheme.colorScheme.surface
        ),
        modifier = Modifier
            .fillMaxWidth()
            .semantics { role = Role.RadioButton }
            .testTag("goal_template_${template.name}")
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(OnboardingSpacing.ItemSpacing),
            horizontalArrangement = Arrangement.spacedBy(OnboardingSpacing.ItemSpacing),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = template.emoji,
                style = MaterialTheme.typography.headlineMedium
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(template.titleResId),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    text = stringResource(template.descriptionResId),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = stringResource(R.string.goal_template_target, template.suggestedAmount.toString(), template.currency),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            if (isSelected) {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = "Selected",
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}

@Composable
private fun AssetSelectionStep(
    assets: List<OnboardingAsset>,
    selectedAssets: Set<String>,
    onAssetToggled: (String) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = OnboardingSpacing.ScreenPadding, vertical = OnboardingSpacing.ContentPadding),
        verticalArrangement = Arrangement.spacedBy(OnboardingSpacing.ItemSpacing)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = stringResource(R.string.onboarding_assets_title),
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )

                Text(
                    text = stringResource(R.string.onboarding_assets_subtitle),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(16.dp))
            }
        }

        items(assets, key = { it.symbol }) { asset ->
            AssetSelectionCard(
                symbol = asset.symbol,
                name = asset.name,
                isSelected = selectedAssets.contains(asset.symbol),
                onClick = { onAssetToggled(asset.symbol) }
            )
        }
    }
}

@Composable
private fun AssetSelectionCard(
    symbol: String,
    name: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected)
                MaterialTheme.colorScheme.primaryContainer
            else
                MaterialTheme.colorScheme.surface
        ),
        modifier = Modifier
            .fillMaxWidth()
            .semantics { role = Role.Checkbox }
            .testTag("asset_selection_$symbol")
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(OnboardingSpacing.ItemSpacing),
            horizontalArrangement = Arrangement.spacedBy(OnboardingSpacing.ItemSpacing),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Checkbox(
                checked = isSelected,
                onCheckedChange = { onClick() }
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = symbol,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    text = name,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun CompletionStep(
    selectedTemplate: GoalTemplate?
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(OnboardingSpacing.SectionSpacing)
    ) {
        Icon(
            imageVector = Icons.Default.CheckCircle,
            contentDescription = null,
            modifier = Modifier.size(80.dp),
            tint = MaterialTheme.colorScheme.primary
        )

        Text(
            text = stringResource(R.string.onboarding_complete_title),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )

        Text(
            text = stringResource(R.string.onboarding_complete_description),
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        if (selectedTemplate != null) {
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(OnboardingSpacing.ItemSpacing),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = selectedTemplate.emoji,
                            style = MaterialTheme.typography.titleLarge
                        )
                        Text(
                            text = stringResource(selectedTemplate.titleResId),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Medium
                        )
                    }
                    Text(
                        text = stringResource(R.string.goal_template_target, selectedTemplate.suggestedAmount.toString(), selectedTemplate.currency),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = stringResource(R.string.onboarding_complete_duration_label, stringResource(R.string.goal_template_duration, selectedTemplate.durationMonths)),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun OnboardingNavigation(
    currentStep: Int,
    canProceed: Boolean,
    isLastStep: Boolean,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
    onSkip: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(OnboardingSpacing.ItemSpacing)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            // Back button
            if (currentStep > 0) {
                OutlinedButton(
                    onClick = onPrevious,
                    modifier = Modifier.testTag(OnboardingTestTags.BACK_BUTTON)
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(stringResource(R.string.onboarding_back))
                }
            } else {
                Spacer(modifier = Modifier.width(80.dp))
            }

            // Next/Complete button
            Button(
                onClick = onNext,
                enabled = canProceed,
                modifier = Modifier.testTag(OnboardingTestTags.NEXT_BUTTON)
            ) {
                Text(
                    if (isLastStep) stringResource(R.string.onboarding_start_saving) else stringResource(R.string.onboarding_continue)
                )
                if (!isLastStep) {
                    Spacer(modifier = Modifier.width(8.dp))
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                }
            }
        }

        // Skip option
        if (!isLastStep) {
            TextButton(
                onClick = onSkip,
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .testTag(OnboardingTestTags.SKIP_BUTTON)
            ) {
                Text(
                    text = stringResource(R.string.onboarding_skip),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
