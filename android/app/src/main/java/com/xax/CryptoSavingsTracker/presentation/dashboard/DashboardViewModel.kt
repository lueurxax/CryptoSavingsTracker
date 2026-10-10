package com.xax.CryptoSavingsTracker.presentation.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetsUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceCompleteness
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceCompletenessResolver
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalProgressUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GoalWithProgress
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import javax.inject.Inject

data class DashboardAssetSummary(
    val asset: Asset,
    val currentBalance: Double?,
    val usdValue: Double?,
    val balanceIssue: String? = null
)

data class PortfolioChartPoint(
    val label: String,
    val usdTotal: Double
)

data class DashboardUiState(
    val isLoading: Boolean = true,
    val totalUsd: Double? = null,
    val portfolioLast30Days: List<PortfolioChartPoint> = emptyList(),
    val hasMissingUsdRates: Boolean = false,
    val hasUnavailableBalances: Boolean = false,
    val financialDataIssue: String? = null,
    val activeGoals: List<GoalWithProgress> = emptyList(),
    val assets: List<DashboardAssetSummary> = emptyList(),
    val error: String? = null
)

@HiltViewModel
@OptIn(ExperimentalCoroutinesApi::class)
class DashboardViewModel @Inject constructor(
    private val getAssetsUseCase: GetAssetsUseCase,
    private val transactionRepository: TransactionRepository,
    private val exchangeRateRepository: ExchangeRateRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository,
    private val getGoalProgressUseCase: GetGoalProgressUseCase
) : ViewModel() {

    private data class DashboardInputs(
        val assets: List<Asset>,
        val transactions: List<com.xax.CryptoSavingsTracker.domain.model.Transaction>,
        val goalsWithProgress: List<GoalWithProgress>
    )

    private data class SourceRead<T>(
        val value: T? = null,
        val failure: String? = null
    )

    private data class DashboardSourceUpdate(
        val inputs: DashboardInputs? = null,
        val failure: String? = null
    )

    private val _uiState = MutableStateFlow(DashboardUiState())
    val uiState: StateFlow<DashboardUiState> = _uiState.asStateFlow()

    private val sourceRetryGeneration = MutableStateFlow(0L)
    private var latestInputs: DashboardInputs? = null
    private var loadJob: Job? = null
    private var loadGeneration: Long = 0L
    private var explicitRefreshInProgress: Boolean = false
    private var pendingReactiveReload: Boolean = false
    private var sourceFailureActive: Boolean = false

    init {
        viewModelScope.launch {
            sourceRetryGeneration
                .flatMapLatest { observeDashboardSources() }
                .collect { update ->
                    val sourceFailure = update.failure
                    if (sourceFailure != null) {
                        sourceFailureActive = true
                        latestInputs = null
                        loadGeneration += 1
                        loadJob?.cancel()
                        explicitRefreshInProgress = false
                        pendingReactiveReload = false
                        _uiState.value = DashboardUiState(
                            isLoading = false,
                            totalUsd = null,
                            portfolioLast30Days = emptyList(),
                            financialDataIssue = sourceFailure,
                            assets = emptyList(),
                            error = sourceFailure
                        )
                        return@collect
                    }

                    val inputs = checkNotNull(update.inputs)
                    sourceFailureActive = false
                    latestInputs = inputs
                    if (explicitRefreshInProgress) {
                        pendingReactiveReload = true
                    } else {
                        startLoad(inputs = inputs, forceRefresh = false)
                    }
                }
        }
    }

    fun refresh() {
        if (sourceFailureActive) {
            _uiState.value = DashboardUiState(isLoading = true)
            sourceRetryGeneration.update { it + 1L }
            return
        }
        val inputs = latestInputs ?: return
        startLoad(inputs = inputs, forceRefresh = true)
    }

    private fun observeDashboardSources(): Flow<DashboardSourceUpdate> = combine(
        getAssetsUseCase().asSourceRead("Asset"),
        transactionRepository.getAllTransactions().asSourceRead("Transaction"),
        getGoalProgressUseCase().asSourceRead("Goal")
    ) { assets, transactions, goals ->
        val failure = listOfNotNull(assets.failure, transactions.failure, goals.failure)
            .joinToString(" ")
            .takeIf { it.isNotEmpty() }
        if (failure != null) {
            DashboardSourceUpdate(failure = failure)
        } else {
            DashboardSourceUpdate(
                inputs = DashboardInputs(
                    assets = checkNotNull(assets.value),
                    transactions = checkNotNull(transactions.value),
                    goalsWithProgress = checkNotNull(goals.value)
                )
            )
        }
    }

    private fun <T> Flow<T>.asSourceRead(label: String): Flow<SourceRead<T>> =
        map<T, SourceRead<T>> { value -> SourceRead(value = value) }
            .catch { error ->
                emit(
                    SourceRead(
                        failure = "$label data source unavailable: " +
                            (error.message ?: error::class.simpleName.orEmpty())
                    )
                )
            }

    private fun startLoad(
        inputs: DashboardInputs,
        forceRefresh: Boolean
    ) {
        val generation = ++loadGeneration
        if (forceRefresh) {
            explicitRefreshInProgress = true
            pendingReactiveReload = false
        }
        loadJob?.cancel()
        _uiState.update { it.copy(isLoading = true, error = null) }

        loadJob = viewModelScope.launch {
            try {
                val state = runCatching {
                    buildDashboardState(
                        inputs = inputs,
                        forceRefresh = forceRefresh
                    )
                }.getOrElse { error ->
                    DashboardUiState(
                        isLoading = false,
                        totalUsd = null,
                        assets = emptyList(),
                        error = error.message ?: "Failed to load dashboard"
                    )
                }
                if (generation == loadGeneration) {
                    _uiState.value = state
                }
            } finally {
                if (forceRefresh && generation == loadGeneration) {
                    explicitRefreshInProgress = false
                    if (pendingReactiveReload) {
                        pendingReactiveReload = false
                        latestInputs?.let { latest ->
                            startLoad(inputs = latest, forceRefresh = false)
                        }
                    }
                }
            }
        }
    }

    private suspend fun buildDashboardState(
        inputs: DashboardInputs,
        forceRefresh: Boolean
    ): DashboardUiState {
        if (forceRefresh) {
            exchangeRateRepository.clearCache()
        }
        val summariesAndMeta = buildSummaries(
            assets = inputs.assets,
            transactions = inputs.transactions,
            forceRefresh = forceRefresh
        )
        val summaries = summariesAndMeta.summaries
        val total = if (
            summariesAndMeta.hasMissingUsdRates ||
            summariesAndMeta.hasUnavailableBalances
        ) {
            null
        } else {
            summaries.sumOf { it.usdValue ?: 0.0 }
        }
        val activeGoals = inputs.goalsWithProgress
            .filter { it.goal.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
            .sortedBy { it.goal.deadline }
            .take(3)
        return DashboardUiState(
            isLoading = false,
            totalUsd = total,
            portfolioLast30Days = summariesAndMeta.last30Days,
            hasMissingUsdRates = summariesAndMeta.hasMissingUsdRates,
            hasUnavailableBalances = summariesAndMeta.hasUnavailableBalances,
            financialDataIssue = summariesAndMeta.financialDataIssue,
            activeGoals = activeGoals,
            assets = summaries.sortedByDescending { it.usdValue ?: Double.NEGATIVE_INFINITY },
            error = null
        )
    }

    private data class SummariesResult(
        val summaries: List<DashboardAssetSummary>,
        val last30Days: List<PortfolioChartPoint>,
        val hasMissingUsdRates: Boolean,
        val hasUnavailableBalances: Boolean,
        val financialDataIssue: String?
    )

    private suspend fun buildSummaries(
        assets: List<Asset>,
        transactions: List<com.xax.CryptoSavingsTracker.domain.model.Transaction>,
        forceRefresh: Boolean
    ): SummariesResult = coroutineScope {
        val manualTransactions = transactions.filter { it.source == TransactionSource.MANUAL }
        val manualBalanceByAssetId = manualTransactions
            .groupBy { it.assetId }
            .mapValues { (_, txs) -> txs.sumOf { it.amount } }

        val balanceByAssetId = assets
            .map { asset ->
                async {
                    val manualBalance = manualBalanceByAssetId[asset.id] ?: 0.0
                    asset.id to AssetBalanceCompletenessResolver.resolve(
                        asset = asset,
                        manualBalance = manualBalance,
                        repository = onChainBalanceRepository,
                        forceRefresh = forceRefresh
                    )
                }
            }
            .awaitAll()
            .toMap()

        val currencies = assets.map { it.currency.uppercase() }.distinct()
        val ratesByCurrency = currencies
            .map { currency ->
                async {
                    val rate = runCatching { exchangeRateRepository.fetchRate(currency, "USD") }.getOrNull()
                    currency to rate
                }
            }
            .awaitAll()
            .toMap()

        val summaries = assets.map { asset ->
            async {
                val balance = checkNotNull(balanceByAssetId[asset.id])
                val currentBalance = balance.totalBalanceOrNull
                val rate = ratesByCurrency[asset.currency.uppercase()]
                val usdValue = currentBalance?.let { total ->
                    rate
                        ?.takeIf { it.isFinite() && it > 0.0 }
                        ?.let { total * it }
                        ?.takeIf(Double::isFinite)
                }
                DashboardAssetSummary(
                    asset = asset,
                    currentBalance = currentBalance,
                    usdValue = usdValue,
                    balanceIssue = balance.issueOrNull
                )
            }
        }.awaitAll()

        val hasUnavailableBalances = summaries.any { it.currentBalance == null }
        val manualAssetIdsWithActivity = manualTransactions.mapTo(mutableSetOf()) { it.assetId }
        val hasMissingUsdRates = summaries.any { summary ->
            val needsRate =
                summary.currentBalance?.let { it != 0.0 } == true ||
                    summary.asset.id in manualAssetIdsWithActivity
            needsRate && summary.usdValue == null
        }
        val last30Days = if (hasUnavailableBalances || hasMissingUsdRates) {
            emptyList()
        } else {
            buildLast30DaysChart(
                assets = assets,
                manualTransactions = manualTransactions,
                ratesByCurrency = ratesByCurrency,
                onChainByAssetId = balanceByAssetId.mapValues { (_, completeness) ->
                    (completeness as AssetBalanceCompleteness.Complete).onChainBalance ?: 0.0
                }
            )
        }
        val financialDataIssue = buildList {
            summaries.mapNotNullTo(this) { it.balanceIssue }
            if (hasMissingUsdRates) {
                add("One or more USD exchange rates are unavailable. Refresh rates and retry.")
            }
        }.distinct().takeIf { it.isNotEmpty() }?.joinToString(" ")

        SummariesResult(
            summaries = summaries,
            last30Days = last30Days,
            hasMissingUsdRates = hasMissingUsdRates,
            hasUnavailableBalances = hasUnavailableBalances,
            financialDataIssue = financialDataIssue
        )
    }

    private fun buildLast30DaysChart(
        assets: List<Asset>,
        manualTransactions: List<com.xax.CryptoSavingsTracker.domain.model.Transaction>,
        ratesByCurrency: Map<String, Double?>,
        onChainByAssetId: Map<String, Double>
    ): List<PortfolioChartPoint> {
        if (assets.isEmpty()) return emptyList()

        val zone = ZoneId.systemDefault()
        val endDate = LocalDate.now(zone)
        val startDate = endDate.minusDays(29)
        val dayFormatter = DateTimeFormatter.ofPattern("MM/dd")

        val days = (0..29).map { offset -> startDate.plusDays(offset.toLong()) }
        val totals = DoubleArray(days.size) { 0.0 }

        val manualTxsByAssetId = manualTransactions
            .groupBy { it.assetId }
            .mapValues { (_, txs) ->
                txs.map { tx ->
                    val date = Instant.ofEpochMilli(tx.dateMillis).atZone(zone).toLocalDate()
                    date to tx.amount
                }.sortedBy { it.first }
            }

        assets.forEach { asset ->
            val rate = ratesByCurrency[asset.currency.uppercase()] ?: return@forEach
            val txs = manualTxsByAssetId[asset.id].orEmpty()

            // Start with the current total balance (on-chain + all manual transactions)
            var currentAssetBalance = (onChainByAssetId[asset.id] ?: 0.0) + txs.sumOf { it.second }

            // Reconstruct history by moving backward from today and subtracting transactions
            var txIndex = txs.size - 1
            for (dayIndex in 29 downTo 0) {
                val day = days[dayIndex]
                // While transactions happened after the current day being processed, subtract them
                while (txIndex >= 0 && txs[txIndex].first.isAfter(day)) {
                    currentAssetBalance -= txs[txIndex].second
                    txIndex--
                }
                totals[dayIndex] += currentAssetBalance * rate
            }
        }

        return days.mapIndexed { index, day ->
            PortfolioChartPoint(label = dayFormatter.format(day), usdTotal = totals[index])
        }
    }
}
