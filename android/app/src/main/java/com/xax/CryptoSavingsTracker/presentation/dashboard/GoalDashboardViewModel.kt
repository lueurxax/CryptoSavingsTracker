package com.xax.CryptoSavingsTracker.presentation.dashboard

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.AllocationHistory
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.navigation.NavigationTelemetryTracker
import com.xax.CryptoSavingsTracker.domain.repository.AllocationHistoryRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.AllocationValidationService
import com.xax.CryptoSavingsTracker.domain.usecase.execution.FundedDeltaAttribution
import com.xax.CryptoSavingsTracker.domain.usecase.execution.ExecutionAttributionScopeValidator
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalProgressUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GoalContributionAttributionCalculator
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GoalWithProgress
import dagger.hilt.android.lifecycle.HiltViewModel
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import javax.inject.Inject
import kotlin.math.max
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class GoalDashboardUiState(
    val isLoading: Boolean = true,
    val errorMessage: String? = null,
    val sceneModel: GoalDashboardSceneModel? = null
)

private data class GoalDashboardInputs(
    val goalProgress: GoalWithProgress?,
    val allocations: List<Allocation>,
    val transactions: List<Transaction>,
    val allocationHistory: List<AllocationHistory>,
    val sourceFailureReason: String?
)

private data class GoalDashboardSource<T>(
    val value: T,
    val failureReason: String? = null
)

private data class ConvertedGoalContribution(
    val attribution: FundedDeltaAttribution,
    val assetCurrency: String,
    val amountInGoalCurrency: Double?
)

@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class GoalDashboardViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val getGoalProgressUseCase: GetGoalProgressUseCase,
    private val allocationRepository: AllocationRepository,
    private val allocationHistoryRepository: AllocationHistoryRepository,
    private val assetRepository: AssetRepository,
    private val transactionRepository: TransactionRepository,
    private val exchangeRateRepository: ExchangeRateRepository,
    private val allocationValidationService: AllocationValidationService,
    private val contributionAttributionCalculator: GoalContributionAttributionCalculator,
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
            refreshSignal
                .flatMapLatest { dashboardInputs() }
                .collectLatest { inputs ->
                    _uiState.update { it.copy(isLoading = true, errorMessage = null) }
                    val scene = buildSceneOrHardError(
                        goalProgress = inputs.goalProgress,
                        allocations = inputs.allocations,
                        transactions = inputs.transactions,
                        allocationHistory = inputs.allocationHistory,
                        sourceFailureReason = inputs.sourceFailureReason
                    )
                    if (scene != null && scene.freshness != DataFreshnessState.HARD_ERROR) {
                        lastSuccessfulRefreshAt = scene.generatedAt
                    }
                    _uiState.value = GoalDashboardUiState(
                        isLoading = false,
                        errorMessage = if (inputs.goalProgress == null) "Goal not found" else null,
                        sceneModel = scene
                    )
                }
        }
    }

    private fun dashboardInputs(): Flow<GoalDashboardInputs> {
        return combine(
            getGoalProgressUseCase.getProgressFlow(goalId).withDashboardFailure(
                fallback = null,
                reason = "goal_progress_source_unavailable"
            ),
            allocationRepository.getAllAllocationsFlow().withDashboardFailure(
                fallback = emptyList(),
                reason = "allocations_source_unavailable"
            ),
            transactionRepository.getAllTransactions().withDashboardFailure(
                fallback = emptyList(),
                reason = "transactions_source_unavailable"
            ),
            allocationHistoryRepository.getAll().withDashboardFailure(
                fallback = emptyList(),
                reason = "allocation_history_source_unavailable"
            )
        ) { goalProgress, allocations, transactions, allocationHistory ->
            GoalDashboardInputs(
                goalProgress = goalProgress.value,
                allocations = allocations.value,
                transactions = transactions.value,
                allocationHistory = allocationHistory.value,
                sourceFailureReason = goalProgress.failureReason
                    ?: allocations.failureReason
                    ?: transactions.failureReason
                    ?: allocationHistory.failureReason
            )
        }
    }

    private fun <T> Flow<T>.withDashboardFailure(
        fallback: T,
        reason: String
    ): Flow<GoalDashboardSource<T>> {
        return map { GoalDashboardSource(value = it) }
            .catch { error ->
                if (error is CancellationException) throw error
                emit(
                    GoalDashboardSource(
                        value = fallback,
                        failureReason = reason
                    )
                )
            }
    }

    private suspend fun buildSceneOrHardError(
        goalProgress: GoalWithProgress?,
        allocations: List<Allocation>,
        transactions: List<Transaction>,
        allocationHistory: List<AllocationHistory>,
        sourceFailureReason: String?
    ): GoalDashboardSceneModel? {
        if (goalProgress == null) return null
        if (sourceFailureReason != null) {
            return buildHardErrorScene(goalProgress.goal, sourceFailureReason)
        }
        if (
            goalProgress.financialDataIssue != null ||
            goalProgress.fundedAmount == null ||
            goalProgress.progress == null
        ) {
            return buildHardErrorScene(
                goalProgress.goal,
                sanitizeReason(goalProgress.financialDataIssue ?: "goal_financial_data_unavailable")
            )
        }
        return try {
            buildScene(
                goalProgress = goalProgress,
                allocations = allocations,
                transactions = transactions,
                allocationHistory = allocationHistory
            )
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            buildHardErrorScene(goalProgress.goal, sanitizeReason(error.message))
        }
    }

    private suspend fun buildScene(
        goalProgress: GoalWithProgress,
        allocations: List<Allocation>,
        transactions: List<Transaction>,
        allocationHistory: List<AllocationHistory>
    ): GoalDashboardSceneModel {
        val goal = goalProgress.goal
        val fundedAmount = checkNotNull(goalProgress.fundedAmount)
        val progress = checkNotNull(goalProgress.progress)
        val now = Instant.now()
        val zoneId = ZoneId.systemDefault()
        val nowDate = LocalDate.now(zoneId)
        val monthStartMillis = nowDate.withDayOfMonth(1)
            .atStartOfDay(zoneId)
            .toInstant()
            .toEpochMilli()

        val rateCache = mutableMapOf<Pair<String, String>, Double?>()
        var missingRateCount = 0

        val goalAllocations = allocations.filter { it.goalId == goal.id }
        val allocationAssetIds = goalAllocations.map { it.assetId }
        val goalRelatedAssetIds = buildSet {
            goalAllocations.mapTo(this) { it.assetId }
            allocationHistory
                .filterTo(mutableListOf()) { it.goalId == goal.id }
                .mapTo(this) { it.assetId }
        }
        val assetMap = mutableMapOf<String, Asset>()
        for (assetId in goalRelatedAssetIds) {
            assetMap[assetId] = sourceValueOrNull {
                assetRepository.getAssetById(assetId)
            }
                ?: throw IllegalStateException(
                    "Goal contribution attribution asset is unavailable: $assetId"
                )
        }
        ExecutionAttributionScopeValidator.requireProvableTransactionLedger(
            requiredAssetIds = goalRelatedAssetIds,
            knownAssetIds = assetMap.keys,
            addressedAssetIds = assetMap.values
                .asSequence()
                .filter { !it.address.isNullOrBlank() }
                .mapTo(hashSetOf()) { it.id },
            onChainTransactionAssetIds = transactions
                .asSequence()
                .filter { it.source == TransactionSource.ON_CHAIN }
                .mapTo(hashSetOf()) { it.assetId }
        )
        val attributedContributions = contributionAttributionCalculator.calculate(
            goalId = goal.id,
            currentAllocations = allocations,
            transactions = transactions,
            allocationHistory = allocationHistory,
            nowMillis = now.toEpochMilli()
        )

        suspend fun convertToGoalCurrency(amount: Double, fromCurrency: String): Double? {
            if (fromCurrency.equals(goal.currency, ignoreCase = true)) {
                return amount
            }
            val key = fromCurrency.uppercase() to goal.currency.uppercase()
            val rate = if (rateCache.containsKey(key)) {
                rateCache[key]
            } else {
                val fetched = sourceValueOrNull {
                    exchangeRateRepository.fetchRate(fromCurrency, goal.currency)
                }
                rateCache[key] = fetched
                fetched
            }
            return rate?.let { amount * it }
        }

        val convertedContributions = attributedContributions.map { attribution ->
            val currency = checkNotNull(assetMap[attribution.assetId]).currency
            val converted = convertToGoalCurrency(attribution.amount, currency)
            if (converted == null) {
                missingRateCount += 1
            }
            ConvertedGoalContribution(
                attribution = attribution,
                assetCurrency = currency,
                amountInGoalCurrency = converted
            )
        }
        val monthContributionSum = convertedContributions
            .filter { it.attribution.timestampMillis >= monthStartMillis }
            .sumOf { it.amountInGoalCurrency ?: 0.0 }

        val recentRows = convertedContributions
            .sortedByDescending { it.attribution.timestampMillis }
            .take(5)
            .map { contribution ->
                ActivityRow(
                    id = "${contribution.attribution.source.name.lowercase()}:" +
                        contribution.attribution.sourceId,
                    assetCurrency = contribution.assetCurrency,
                    amount = decimalOf(contribution.amountInGoalCurrency ?: 0.0),
                    date = Instant.ofEpochMilli(contribution.attribution.timestampMillis),
                    note = contribution.attribution.comment
                )
            }

        val allocationPairs = goalAllocations.map { allocation ->
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
        val overAllocatedAssetIds = allocationValidationService
            .getOverAllocatedAssets()
            .map { it.asset.id }
            .toSet()
        val overAllocated = allocationAssetIds.any { it in overAllocatedAssetIds }

        val assumptionWindowDays = 90
        val windowStartMillis = nowDate.minusDays(assumptionWindowDays.toLong())
            .atStartOfDay(zoneId)
            .toInstant()
            .toEpochMilli()
        val windowContributions = convertedContributions.filter {
            it.attribution.timestampMillis >= windowStartMillis
        }
        val hasIncompleteForecastInputs = windowContributions.any {
            it.amountInGoalCurrency == null
        }
        val windowContributionSum = windowContributions.sumOf {
            it.amountInGoalCurrency ?: 0.0
        }

        val monthsInWindow = assumptionWindowDays / 30.0
        val monthlyPace = if (monthsInWindow > 0) windowContributionSum / monthsInWindow else 0.0
        val daysRemaining = max(0L, ChronoUnit.DAYS.between(nowDate, goal.deadline))
        val projectedAmount = if (hasIncompleteForecastInputs) {
            null
        } else {
            fundedAmount + (monthlyPace * (daysRemaining / 30.0))
        }

        val forecastStatus = projectedAmount?.let { amount ->
            when {
                amount >= goal.targetAmount -> GoalDashboardRiskStatus.ON_TRACK
                amount >= goal.targetAmount * 0.85 -> GoalDashboardRiskStatus.AT_RISK
                else -> GoalDashboardRiskStatus.OFF_TRACK
            }
        }
        val confidence = if (hasIncompleteForecastInputs) {
            null
        } else {
            when {
                windowContributions.size >= 6 -> GoalDashboardForecastConfidence.HIGH
                windowContributions.size >= 2 -> GoalDashboardForecastConfidence.MEDIUM
                else -> GoalDashboardForecastConfidence.LOW
            }
        }

        val freshness = if (missingRateCount > 0) DataFreshnessState.STALE else DataFreshnessState.FRESH
        val freshnessReason = if (missingRateCount > 0) "missing_exchange_rate" else null

        return sceneAssembler.assemble(
            GoalDashboardSceneInput(
                goal = goal,
                generatedAt = now,
                currentAmount = decimalOf(fundedAmount),
                targetAmount = decimalOf(goal.targetAmount),
                remainingAmount = decimalOf(max(0.0, goal.targetAmount - fundedAmount)),
                progressRatio = progress,
                daysRemaining = daysRemaining.toInt(),
                freshness = freshness,
                freshnessUpdatedAt = now,
                freshnessReason = freshnessReason,
                reasonCode = freshnessReason,
                assumptionWindowDays = assumptionWindowDays,
                forecastConfidence = confidence,
                forecastStatus = forecastStatus,
                forecastUpdatedAt = now,
                projectedAmount = projectedAmount?.let { decimalOf(it) },
                forecastWhyCopyKey = forecastStatus?.let {
                    "dashboard.forecast.why.${it.wireId}"
                },
                forecastErrorReasonCode = if (hasIncompleteForecastInputs) {
                    "missing_exchange_rate"
                } else {
                    null
                },
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

    private suspend fun <T> sourceValueOrNull(block: suspend () -> T): T? {
        return try {
            block()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            null
        }
    }

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
