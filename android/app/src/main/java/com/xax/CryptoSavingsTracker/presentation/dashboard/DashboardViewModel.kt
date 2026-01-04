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
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GetGoalProgressUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.GoalWithProgress
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import javax.inject.Inject

data class DashboardAssetSummary(
    val asset: Asset,
    val currentBalance: Double,
    val usdValue: Double?
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
    val activeGoals: List<GoalWithProgress> = emptyList(),
    val assets: List<DashboardAssetSummary> = emptyList(),
    val error: String? = null
)

@HiltViewModel
class DashboardViewModel @Inject constructor(
    private val getAssetsUseCase: GetAssetsUseCase,
    private val transactionRepository: TransactionRepository,
    private val exchangeRateRepository: ExchangeRateRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository,
    private val getGoalProgressUseCase: GetGoalProgressUseCase
) : ViewModel() {

    private val refreshSignal = MutableStateFlow(0)

    private val _uiState = MutableStateFlow(DashboardUiState())
    val uiState: StateFlow<DashboardUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            combine(
                getAssetsUseCase().catch { emit(emptyList()) },
                transactionRepository.getAllTransactions().catch { emit(emptyList()) },
                getGoalProgressUseCase().catch { emit(emptyList()) },
                refreshSignal
            ) { assets, transactions, goalsWithProgress, _ ->
                Triple(assets, transactions, goalsWithProgress)
            }
                .collectLatest { (assets, transactions, goalsWithProgress) ->
                    loadDashboard(assets, transactions, goalsWithProgress)
                }
        }
    }

    fun refresh() {
        refreshSignal.value = refreshSignal.value + 1
    }

    private suspend fun loadDashboard(
        assets: List<Asset>,
        transactions: List<com.xax.CryptoSavingsTracker.domain.model.Transaction>,
        goalsWithProgress: List<GoalWithProgress>
    ) {
        _uiState.update { it.copy(isLoading = true, error = null) }
        runCatching {
            val summariesAndMeta = buildSummaries(assets, transactions)
            val summaries = summariesAndMeta.summaries
            val partialTotal = summaries.mapNotNull { it.usdValue }.sum()
            val total = if (summariesAndMeta.hasMissingUsdRates && partialTotal == 0.0) null else partialTotal
            val activeGoals = goalsWithProgress
                .filter { it.goal.lifecycleStatus == GoalLifecycleStatus.ACTIVE }
                .sortedBy { it.goal.deadline }
                .take(3)
            DashboardUiState(
                isLoading = false,
                totalUsd = total,
                portfolioLast30Days = summariesAndMeta.last30Days,
                hasMissingUsdRates = summariesAndMeta.hasMissingUsdRates,
                activeGoals = activeGoals,
                assets = summaries.sortedByDescending { it.usdValue ?: Double.NEGATIVE_INFINITY },
                error = null
            )
        }.onSuccess { state ->
            _uiState.value = state
        }.onFailure { e ->
            _uiState.value = DashboardUiState(
                isLoading = false,
                totalUsd = null,
                assets = emptyList(),
                error = e.message ?: "Failed to load dashboard"
            )
        }
    }

    private data class SummariesResult(
        val summaries: List<DashboardAssetSummary>,
        val last30Days: List<PortfolioChartPoint>,
        val hasMissingUsdRates: Boolean
    )

    private suspend fun buildSummaries(
        assets: List<Asset>,
        transactions: List<com.xax.CryptoSavingsTracker.domain.model.Transaction>
    ): SummariesResult = coroutineScope {
        val manualTransactions = transactions.filter { it.source == TransactionSource.MANUAL }
        val manualBalanceByAssetId = manualTransactions
            .groupBy { it.assetId }
            .mapValues { (_, txs) -> txs.sumOf { it.amount } }

        val onChainByAssetId = assets
            .map { asset ->
                async {
                    val hasOnChain = !asset.address.isNullOrBlank() && !asset.chainId.isNullOrBlank()
                    val balance = if (!hasOnChain) {
                        0.0
                    } else {
                        runCatching { onChainBalanceRepository.getBalance(asset, forceRefresh = false).getOrNull()?.balance ?: 0.0 }
                            .getOrElse { 0.0 }
                    }
                    asset.id to balance
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
                val manualBalance = manualBalanceByAssetId[asset.id] ?: 0.0
                val onChainBalance = onChainByAssetId[asset.id] ?: 0.0
                val currentBalance = manualBalance + onChainBalance
                val rate = ratesByCurrency[asset.currency.uppercase()]
                val usdValue = rate?.let { currentBalance * it }
                DashboardAssetSummary(asset = asset, currentBalance = currentBalance, usdValue = usdValue)
            }
        }.awaitAll()

        val hasMissingUsdRates = summaries.any { it.currentBalance != 0.0 && it.usdValue == null }
        val last30Days = buildLast30DaysChart(
            assets = assets,
            manualTransactions = manualTransactions,
            ratesByCurrency = ratesByCurrency,
            onChainByAssetId = onChainByAssetId
        )

        SummariesResult(summaries = summaries, last30Days = last30Days, hasMissingUsdRates = hasMissingUsdRates)
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
            var index = 0
            var balance = onChainByAssetId[asset.id] ?: 0.0

            days.forEachIndexed { dayIndex, day ->
                while (index < txs.size && !txs[index].first.isAfter(day)) {
                    balance += txs[index].second
                    index++
                }
                totals[dayIndex] += balance * rate
            }
        }

        return days.mapIndexed { index, day ->
            PortfolioChartPoint(label = dayFormatter.format(day), usdTotal = totals[index])
        }
    }
}
