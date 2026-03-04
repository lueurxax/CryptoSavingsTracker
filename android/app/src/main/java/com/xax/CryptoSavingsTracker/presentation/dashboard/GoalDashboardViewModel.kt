package com.xax.CryptoSavingsTracker.presentation.dashboard

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.navigation.NavigationTelemetryTracker
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationValidationService
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalProgressUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GoalWithProgress
import dagger.hilt.android.lifecycle.HiltViewModel
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import javax.inject.Inject
import kotlin.math.max
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class GoalDashboardUiState(
    val isLoading: Boolean = true,
    val errorMessage: String? = null,
    val sceneModel: GoalDashboardSceneModel? = null
)

@HiltViewModel
class GoalDashboardViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val getGoalProgressUseCase: GetGoalProgressUseCase,
    private val allocationRepository: AllocationRepository,
    private val assetRepository: AssetRepository,
    private val transactionRepository: TransactionRepository,
    private val exchangeRateRepository: ExchangeRateRepository,
    private val allocationValidationService: AllocationValidationService,
    private val sceneAssembler: GoalDashboardSceneAssembler,
    private val telemetryTracker: NavigationTelemetryTracker
) : ViewModel() {
    private val goalId: String = checkNotNull(savedStateHandle["goalId"])
    private val refreshSignal = MutableStateFlow(0)
    private var lastSuccessfulRefreshAt: Instant? = null

    private val _uiState = MutableStateFlow(GoalDashboardUiState())
    val uiState: StateFlow<GoalDashboardUiState> = _uiState.asStateFlow()

    init {
        observeDashboard()
    }

    fun refresh() {
        refreshSignal.update { it + 1 }
    }

    fun trackDashboardOpened() {
        telemetryTracker.goalDashboardOpened(goalId = goalId, entryPoint = "goal_detail")
    }

    fun trackPrimaryCtaShown(nextAction: NextActionSlice) {
        telemetryTracker.goalDashboardPrimaryCtaShown(
            goalId = goalId,
            resolverState = nextAction.resolverState.wireId,
            ctaId = nextAction.primaryCta.id
        )
    }

    fun trackPrimaryCtaTapped(nextAction: NextActionSlice) {
        telemetryTracker.goalDashboardPrimaryCtaTapped(
            goalId = goalId,
            resolverState = nextAction.resolverState.wireId,
            ctaId = nextAction.primaryCta.id
        )
    }

    private fun observeDashboard() {
        viewModelScope.launch {
            combine(
                getGoalProgressUseCase.getProgressFlow(goalId),
                allocationRepository.getAllocationsForGoalListFlow(goalId),
                transactionRepository.getAllTransactions().catch { emit(emptyList()) },
                refreshSignal
            ) { goalProgress, allocations, transactions, _ ->
                Triple(goalProgress, allocations.map { it.assetId }, transactions)
            }.collectLatest { (goalProgress, allocationAssetIds, transactions) ->
                _uiState.update { it.copy(isLoading = true, errorMessage = null) }
                val scene = buildSceneOrHardError(
                    goalProgress = goalProgress,
                    allocationAssetIds = allocationAssetIds,
                    transactions = transactions
                )
                if (scene != null && scene.freshness != DataFreshnessState.HARD_ERROR) {
                    lastSuccessfulRefreshAt = scene.generatedAt
                }
                _uiState.value = GoalDashboardUiState(
                    isLoading = false,
                    errorMessage = if (goalProgress == null) "Goal not found" else null,
                    sceneModel = scene
                )
            }
        }
    }

    private suspend fun buildSceneOrHardError(
        goalProgress: GoalWithProgress?,
        allocationAssetIds: List<String>,
        transactions: List<Transaction>
    ): GoalDashboardSceneModel? {
        if (goalProgress == null) return null
        return try {
            buildScene(
                goalProgress = goalProgress,
                allocationAssetIds = allocationAssetIds,
                transactions = transactions
            )
        } catch (error: Exception) {
            buildHardErrorScene(goalProgress.goal, sanitizeReason(error.message))
        }
    }

    private suspend fun buildScene(
        goalProgress: GoalWithProgress,
        allocationAssetIds: List<String>,
        transactions: List<Transaction>
    ): GoalDashboardSceneModel {
        val goal = goalProgress.goal
        val now = Instant.now()
        val zoneId = ZoneId.systemDefault()
        val nowDate = LocalDate.now(zoneId)
        val monthStartMillis = nowDate.withDayOfMonth(1)
            .atStartOfDay(zoneId)
            .toInstant()
            .toEpochMilli()

        val rateCache = mutableMapOf<Pair<String, String>, Double?>()
        var missingRateCount = 0

        val assetIds = allocationAssetIds.toSet()
        val assetMap = assetIds.associateWith { assetId ->
            runCatching { assetRepository.getAssetById(assetId) }.getOrNull()
        }

        val goalTransactions = transactions
            .asSequence()
            .filter { it.assetId in assetIds }
            .filter { it.amount > 0 }
            .sortedByDescending { it.dateMillis }
            .toList()

        suspend fun convertToGoalCurrency(amount: Double, fromCurrency: String): Double? {
            if (fromCurrency.equals(goal.currency, ignoreCase = true)) {
                return amount
            }
            val key = fromCurrency.uppercase() to goal.currency.uppercase()
            val rate = if (rateCache.containsKey(key)) {
                rateCache[key]
            } else {
                val fetched = runCatching {
                    exchangeRateRepository.fetchRate(fromCurrency, goal.currency)
                }.getOrNull()
                rateCache[key] = fetched
                fetched
            }
            return rate?.let { amount * it }
        }

        val monthContributionSum = goalTransactions
            .filter { it.dateMillis >= monthStartMillis }
            .sumOf { tx ->
                val currency = assetMap[tx.assetId]?.currency ?: goal.currency
                val converted = convertToGoalCurrency(tx.amount, currency)
                if (converted == null) {
                    missingRateCount += 1
                    0.0
                } else {
                    converted
                }
            }

        val recentRows = goalTransactions
            .take(5)
            .map { tx ->
                val currency = assetMap[tx.assetId]?.currency ?: goal.currency
                val converted = convertToGoalCurrency(tx.amount, currency)
                if (converted == null) {
                    missingRateCount += 1
                }
                ActivityRow(
                    id = tx.id,
                    assetCurrency = currency,
                    amount = decimalOf(converted ?: 0.0),
                    date = Instant.ofEpochMilli(tx.dateMillis),
                    note = tx.comment
                )
            }

        val allocationPairs = allocationRepository.getAllocationsForGoal(goal.id).map { allocation ->
            allocation.assetId to max(0.0, allocation.amount)
        }

        val convertedAllocations = allocationPairs.mapNotNull { (assetId, amount) ->
            val currency = assetMap[assetId]?.currency ?: goal.currency
            val converted = convertToGoalCurrency(amount, currency)
            if (converted == null) {
                missingRateCount += 1
                null
            } else {
                Triple(assetId, currency, converted)
            }
        }

        val totalAllocated = convertedAllocations.sumOf { it.third }
        val topAssets = convertedAllocations
            .sortedByDescending { it.third }
            .take(3)
            .map { (assetId, currency, amount) ->
                val ratio = if (totalAllocated > 0) amount / totalAllocated else 0.0
                AssetWeight(
                    assetId = assetId,
                    assetCurrency = currency,
                    amount = decimalOf(amount),
                    weightRatio = ratio
                )
            }

        val concentrationRatio = topAssets.maxOfOrNull { it.weightRatio }
        val overAllocatedAssetIds = runCatching {
            allocationValidationService.getOverAllocatedAssets().map { it.asset.id }.toSet()
        }.getOrElse { emptySet() }
        val overAllocated = allocationAssetIds.any { it in overAllocatedAssetIds }

        val assumptionWindowDays = 90
        val windowStartMillis = nowDate.minusDays(assumptionWindowDays.toLong())
            .atStartOfDay(zoneId)
            .toInstant()
            .toEpochMilli()
        val windowContributions = goalTransactions.filter { it.dateMillis >= windowStartMillis }
        val windowContributionSum = windowContributions.sumOf { tx ->
            val currency = assetMap[tx.assetId]?.currency ?: goal.currency
            val converted = convertToGoalCurrency(tx.amount, currency)
            if (converted == null) {
                missingRateCount += 1
                0.0
            } else {
                converted
            }
        }

        val monthsInWindow = assumptionWindowDays / 30.0
        val monthlyPace = if (monthsInWindow > 0) windowContributionSum / monthsInWindow else 0.0
        val daysRemaining = max(0L, ChronoUnit.DAYS.between(nowDate, goal.deadline))
        val projectedAmount = goalProgress.fundedAmount + (monthlyPace * (daysRemaining / 30.0))

        val forecastStatus = when {
            projectedAmount >= goal.targetAmount -> GoalDashboardRiskStatus.ON_TRACK
            projectedAmount >= goal.targetAmount * 0.85 -> GoalDashboardRiskStatus.AT_RISK
            else -> GoalDashboardRiskStatus.OFF_TRACK
        }
        val confidence = when {
            windowContributions.size >= 6 -> GoalDashboardForecastConfidence.HIGH
            windowContributions.size >= 2 -> GoalDashboardForecastConfidence.MEDIUM
            else -> GoalDashboardForecastConfidence.LOW
        }

        val freshness = if (missingRateCount > 0) DataFreshnessState.STALE else DataFreshnessState.FRESH
        val freshnessReason = if (missingRateCount > 0) "missing_exchange_rate" else null

        return sceneAssembler.assemble(
            GoalDashboardSceneInput(
                goal = goal,
                generatedAt = now,
                currentAmount = decimalOf(goalProgress.fundedAmount),
                targetAmount = decimalOf(goal.targetAmount),
                remainingAmount = decimalOf(max(0.0, goal.targetAmount - goalProgress.fundedAmount)),
                progressRatio = goalProgress.progress,
                daysRemaining = daysRemaining.toInt(),
                freshness = freshness,
                freshnessUpdatedAt = now,
                freshnessReason = freshnessReason,
                reasonCode = freshnessReason,
                assumptionWindowDays = assumptionWindowDays,
                forecastConfidence = confidence,
                forecastStatus = forecastStatus,
                forecastUpdatedAt = now,
                projectedAmount = decimalOf(projectedAmount),
                forecastWhyCopyKey = "dashboard.forecast.why.${forecastStatus.wireId}",
                forecastErrorReasonCode = null,
                monthContributionSum = decimalOf(monthContributionSum),
                recentRows = recentRows,
                lastContributionAt = recentRows.firstOrNull()?.date,
                overAllocated = overAllocated,
                concentrationRatio = concentrationRatio,
                topAssets = topAssets,
                allocationWarningCopyKey = if (overAllocated) "dashboard.allocation.overAllocated" else null,
                hasAssets = allocationAssetIds.isNotEmpty(),
                hasContributionsThisMonth = monthContributionSum > 0.000001,
                lastSuccessfulRefreshAt = lastSuccessfulRefreshAt,
                legacyWidgetPrefsApplied = false
            )
        )
    }

    private fun buildHardErrorScene(goal: Goal, reasonCode: String?): GoalDashboardSceneModel {
        val now = Instant.now()
        return sceneAssembler.assemble(
            GoalDashboardSceneInput(
                goal = goal,
                generatedAt = now,
                currentAmount = decimalOf(0.0),
                targetAmount = decimalOf(goal.targetAmount),
                remainingAmount = decimalOf(goal.targetAmount),
                progressRatio = 0.0,
                daysRemaining = if (goal.lifecycleStatus == GoalLifecycleStatus.FINISHED || goal.lifecycleStatus == GoalLifecycleStatus.DELETED) {
                    null
                } else {
                    max(0L, ChronoUnit.DAYS.between(LocalDate.now(), goal.deadline)).toInt()
                },
                freshness = DataFreshnessState.HARD_ERROR,
                freshnessUpdatedAt = now,
                freshnessReason = reasonCode ?: "dashboard_build_failed",
                reasonCode = reasonCode ?: "dashboard_build_failed",
                assumptionWindowDays = null,
                forecastConfidence = null,
                forecastStatus = null,
                forecastUpdatedAt = now,
                projectedAmount = null,
                forecastWhyCopyKey = null,
                forecastErrorReasonCode = reasonCode ?: "dashboard_build_failed",
                monthContributionSum = decimalOf(0.0),
                recentRows = emptyList(),
                lastContributionAt = null,
                overAllocated = false,
                concentrationRatio = null,
                topAssets = emptyList(),
                allocationWarningCopyKey = null,
                hasAssets = false,
                hasContributionsThisMonth = false,
                lastSuccessfulRefreshAt = lastSuccessfulRefreshAt,
                legacyWidgetPrefsApplied = false
            )
        )
    }

    private fun decimalOf(value: Double): BigDecimal = BigDecimal.valueOf(value)

    private fun sanitizeReason(message: String?): String {
        return message
            ?.lowercase()
            ?.replace(" ", "_")
            ?.replace(":", "_")
            ?.replace(".", "_")
            ?.ifBlank { null }
            ?: "unknown_hard_error"
    }
}
