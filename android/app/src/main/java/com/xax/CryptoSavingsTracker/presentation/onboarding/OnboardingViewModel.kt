package com.xax.CryptoSavingsTracker.presentation.onboarding

import android.content.Context
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.R
import com.xax.CryptoSavingsTracker.domain.model.ChainIds
import com.xax.CryptoSavingsTracker.domain.model.OnChainAssetRouteCatalog
import com.xax.CryptoSavingsTracker.domain.usecase.asset.AddAssetUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetsUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.AddGoalUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.ExistingGoalRetryPolicy
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject

/**
 * Experience level for user profile - matches iOS
 */
enum class ExperienceLevel(
    val titleResId: Int,
    val descriptionResId: Int,
    val icon: ImageVector
) {
    BEGINNER(
        R.string.experience_beginner_title,
        R.string.experience_beginner_desc,
        Icons.Default.School
    ),
    INTERMEDIATE(
        R.string.experience_intermediate_title,
        R.string.experience_intermediate_desc,
        Icons.Default.Person
    ),
    EXPERT(
        R.string.experience_expert_title,
        R.string.experience_expert_desc,
        Icons.Default.WorkspacePremium
    )
}

/**
 * Goal templates for quick setup - matches iOS
 */
enum class GoalTemplate(
    val titleResId: Int,
    val descriptionResId: Int,
    val emoji: String,
    val suggestedAmount: Double,
    val currency: String,
    val durationMonths: Int,
    val recommendedAssets: List<String>
) {
    EMERGENCY_FUND(
        R.string.goal_emergency_fund_title,
        R.string.goal_emergency_fund_desc,
        "\uD83D\uDEE1\uFE0F",
        10000.0,
        "USD",
        12,
        listOf("USDT", "USDC")
    ),
    VACATION(
        R.string.goal_vacation_title,
        R.string.goal_vacation_desc,
        "\u2708\uFE0F",
        5000.0,
        "USD",
        6,
        listOf("BTC", "ETH")
    ),
    NEW_CAR(
        R.string.goal_new_car_title,
        R.string.goal_new_car_desc,
        "\uD83D\uDE97",
        30000.0,
        "USD",
        24,
        listOf("BTC", "ETH", "SOL")
    ),
    HOME_DOWN_PAYMENT(
        R.string.goal_home_title,
        R.string.goal_home_desc,
        "\uD83C\uDFE0",
        50000.0,
        "USD",
        36,
        listOf("BTC", "ETH")
    ),
    RETIREMENT(
        R.string.goal_retirement_title,
        R.string.goal_retirement_desc,
        "\uD83C\uDFD6\uFE0F",
        100000.0,
        "USD",
        120,
        listOf("BTC", "ETH")
    ),
    CUSTOM(
        R.string.goal_custom_title,
        R.string.goal_custom_desc,
        "\uD83C\uDFAF",
        1000.0,
        "USD",
        12,
        listOf("BTC")
    )
}

/**
 * Asset data class for onboarding
 */
data class OnboardingAsset(
    val symbol: String,
    val name: String
)

/**
 * UI State for onboarding
 */
data class OnboardingUiState(
    val currentStep: Int = 0,
    val experienceLevel: ExperienceLevel = ExperienceLevel.BEGINNER,
    val selectedTemplate: GoalTemplate? = null,
    val selectedAssets: Set<String> = emptySet(),
    val isComplete: Boolean = false,
    val isLoading: Boolean = false,
    val availableAssets: List<OnboardingAsset> = emptyList(),
    val error: String? = null
) {
    val canProceed: Boolean
        get() = !isLoading && when (currentStep) {
            0 -> true // Welcome
            1 -> true // Profile (has defaults)
            2 -> selectedTemplate != null // Goal template
            3 -> true // Assets (optional)
            4 -> true // Complete
            else -> false
        }
}

/**
 * One-time events for Onboarding
 */
sealed class OnboardingEvent {
    object NavigateToDashboard : OnboardingEvent()
}

internal const val ONBOARDING_PREFS_NAME = "onboarding_prefs"
internal const val ONBOARDING_COMPLETED_KEY = "onboarding_completed"

@HiltViewModel
class OnboardingViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val addGoalUseCase: AddGoalUseCase,
    private val addAssetUseCase: AddAssetUseCase,
    private val getAssetsUseCase: GetAssetsUseCase
) : ViewModel() {

    private val _uiState = MutableStateFlow(OnboardingUiState())
    val uiState: StateFlow<OnboardingUiState> = _uiState.asStateFlow()

    private val _events = Channel<OnboardingEvent>(Channel.BUFFERED)
    val events = _events.receiveAsFlow()

    private val prefs = context.getSharedPreferences(ONBOARDING_PREFS_NAME, Context.MODE_PRIVATE)
    private val completionInFlight = AtomicBoolean(false)

    init {
        // Load available assets
        val assets = listOf(
            OnboardingAsset("BTC", "Bitcoin"),
            OnboardingAsset("ETH", "Ethereum"),
            OnboardingAsset("USDT", "Tether"),
            OnboardingAsset("USDC", "USD Coin"),
            OnboardingAsset("SOL", "Solana"),
            OnboardingAsset("POL", "Polygon")
        )
        _uiState.update { it.copy(availableAssets = assets) }

        // Check if onboarding was already completed
        if (prefs.getBoolean(ONBOARDING_COMPLETED_KEY, false)) {
            _uiState.update { it.copy(isComplete = true) }
        }
    }

    fun nextStep() {
        val current = _uiState.value.currentStep
        if (current == 4) {
            completeOnboarding()
        } else {
            _uiState.update { it.copy(currentStep = current + 1) }

            // Auto-select recommended assets when entering asset selection
            if (current == 2 && _uiState.value.selectedTemplate != null) {
                val template = _uiState.value.selectedTemplate!!
                _uiState.update {
                    it.copy(selectedAssets = template.recommendedAssets.toSet())
                }
            }
        }
    }

    fun previousStep() {
        val current = _uiState.value.currentStep
        if (current > 0) {
            _uiState.update { it.copy(currentStep = current - 1) }
        }
    }

    fun skip() {
        completeOnboarding(createGoal = false)
    }

    fun setExperienceLevel(level: ExperienceLevel) {
        _uiState.update { it.copy(experienceLevel = level) }
    }

    fun selectTemplate(template: GoalTemplate) {
        _uiState.update { it.copy(selectedTemplate = template) }
    }

    fun toggleAsset(symbol: String) {
        _uiState.update { state ->
            val newAssets = if (state.selectedAssets.contains(symbol)) {
                state.selectedAssets - symbol
            } else {
                state.selectedAssets + symbol
            }
            state.copy(selectedAssets = newAssets)
        }
    }

    private fun completeOnboarding(createGoal: Boolean = true) {
        if (_uiState.value.isComplete || !completionInFlight.compareAndSet(false, true)) {
            return
        }
        _uiState.update { it.copy(isLoading = true, error = null) }

        viewModelScope.launch {
            try {
                runCatching {
                    if (createGoal) {
                        val existingCurrencies = getAssetsUseCase()
                            .first()
                            .mapTo(mutableSetOf()) { it.currency.uppercase() }

                        _uiState.value.selectedAssets.sorted().forEach { symbol ->
                            val normalizedSymbol = symbol.uppercase()
                            val chainId = ChainIds.predictChain(normalizedSymbol)
                            val canonicalCurrency =
                                OnChainAssetRouteCatalog.canonicalPersistenceCurrency(
                                    chainId = chainId,
                                    currencyOrContract = normalizedSymbol
                                )
                            if (canonicalCurrency !in existingCurrencies) {
                                val addedAsset = addAssetUseCase(
                                    currency = normalizedSymbol,
                                    chainId = chainId
                                ).getOrThrow()
                                existingCurrencies += addedAsset.currency.uppercase()
                            }
                        }
                    }

                    val template = _uiState.value.selectedTemplate.takeIf { createGoal }
                    if (template != null) {
                        val deadline = LocalDate.now().plusMonths(template.durationMonths.toLong())

                        // We still need the strings here to save the goal.
                        // In a perfect world, we'd have a StringProvider, but for now we use context.
                        addGoalUseCase(
                            name = context.getString(template.titleResId),
                            currency = template.currency,
                            targetAmount = template.suggestedAmount,
                            deadline = deadline,
                            startDate = LocalDate.now(),
                            emoji = template.emoji,
                            description = context.getString(template.descriptionResId),
                            goalId = onboardingGoalId(),
                            existingGoalRetryPolicy = ExistingGoalRetryPolicy.KEEP_PERSISTED
                        ).getOrThrow()
                    }
                }.onSuccess {
                    markOnboardingComplete()
                    _uiState.update { it.copy(isLoading = false, isComplete = true, error = null) }
                    _events.send(OnboardingEvent.NavigateToDashboard)
                }.onFailure { error ->
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            isComplete = false,
                            error = error.message ?: "Failed to complete onboarding"
                        )
                    }
                }
            } finally {
                completionInFlight.set(false)
            }
        }
    }

    private fun markOnboardingComplete() {
        prefs.edit().putBoolean(ONBOARDING_COMPLETED_KEY, true).apply()
    }
}

internal fun onboardingGoalId(): String {
    val stableKey = "onboarding-setup-goal"
    return UUID.nameUUIDFromBytes(stableKey.toByteArray(StandardCharsets.UTF_8)).toString()
}
