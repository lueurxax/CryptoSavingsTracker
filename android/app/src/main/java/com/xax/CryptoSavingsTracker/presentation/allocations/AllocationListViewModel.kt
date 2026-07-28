package com.xax.CryptoSavingsTracker.presentation.allocations

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.xax.CryptoSavingsTracker.domain.model.Allocation
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.Transaction
import com.xax.CryptoSavingsTracker.domain.model.TransactionSource
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.ExchangeRateRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.repository.AllocationRepository
import com.xax.CryptoSavingsTracker.domain.repository.OnChainBalanceRepository
import com.xax.CryptoSavingsTracker.domain.repository.TransactionRepository
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.DeleteAllocationUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.allocation.GetAllocationsForGoalUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.balance.AssetBalanceCompletenessResolver
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject
import kotlin.math.abs

/**
 * Data class for displaying an allocation with its asset details.
 */
data class AllocationWithDetails(
    val allocation: Allocation,
    val asset: Asset?,
    val assetBalance: Double?,
    val assetTotalAllocated: Double,   // Total allocated from this asset across all goals
    val assetDisplayName: String,
    val isAssetOverAllocated: Boolean?,
    val balanceIssue: String?
) {
    val fundedAmount: Double?
        get() {
            val total = assetTotalAllocated
            val balance = assetBalance ?: return null
            if (total <= 0.0 || balance <= 0.0) return 0.0
            val ratio = if (balance >= total) 1.0 else balance / total
            return allocation.amount.coerceAtLeast(0.0) * ratio
        }

    val isUnderfunded: Boolean?
        get() = fundedAmount?.let { it + 0.0000001 < allocation.amount }
}

/**
 * UI State for Allocation List screen
 */
data class AllocationListUiState(
    val goal: Goal? = null,
    val allocations: List<AllocationWithDetails> = emptyList(),
    val totalAllocated: Double? = null,
    val totalFunded: Double? = null,
    val hasOverAllocatedAssets: Boolean = false,
    val hasMissingExchangeRates: Boolean = false,
    val hasUnavailableBalances: Boolean = false,
    val financialDataIssue: String? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val showDeleteConfirmation: Allocation? = null
)

/**
 * ViewModel for managing allocations for a specific goal.
 */
@HiltViewModel
class AllocationListViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val getAllocationsForGoalUseCase: GetAllocationsForGoalUseCase,
    private val deleteAllocationUseCase: DeleteAllocationUseCase,
    private val goalRepository: GoalRepository,
    private val assetRepository: AssetRepository,
    private val allocationRepository: AllocationRepository,
    private val transactionRepository: TransactionRepository,
    private val onChainBalanceRepository: OnChainBalanceRepository,
    private val exchangeRateRepository: ExchangeRateRepository
) : ViewModel() {

    private val goalId: String = checkNotNull(savedStateHandle["goalId"])

    private val _error = MutableStateFlow<String?>(null)
    private val _showDeleteConfirmation = MutableStateFlow<Allocation?>(null)
    private val _financialSnapshot = MutableStateFlow(AllocationFinancialSnapshot())
    private var calculationJob: Job? = null
    private var calculationGeneration: Long = 0L

    init {
        observeFinancialInputs()
    }

    val uiState: StateFlow<AllocationListUiState> = combine(
        _financialSnapshot,
        _error,
        _showDeleteConfirmation
    ) { snapshot, error, deleteConfirmation ->
        AllocationListUiState(
            goal = snapshot.goal,
            allocations = snapshot.allocations,
            totalAllocated = snapshot.totals.totalAllocatedInGoalCurrency,
            totalFunded = snapshot.totals.totalFundedInGoalCurrency,
            hasOverAllocatedAssets = snapshot.allocations.any { it.isAssetOverAllocated == true },
            isLoading = snapshot.isLoading,
            hasMissingExchangeRates = snapshot.totals.hasMissingExchangeRates,
            hasUnavailableBalances = snapshot.allocations.any { it.assetBalance == null },
            financialDataIssue = snapshot.totals.financialDataIssue,
            error = error ?: snapshot.error,
            showDeleteConfirmation = deleteConfirmation
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = AllocationListUiState()
    )

    private fun observeFinancialInputs() {
        viewModelScope.launch {
            observeInputs().collect { inputs ->
                startCalculation(inputs)
            }
        }
    }

    private fun observeInputs(): Flow<AllocationInputs> {
        val invalidations = combine(
            onChainBalanceRepository.observeBalanceInvalidations(),
            exchangeRateRepository.observeRateInvalidations()
        ) { balanceVersion, rateVersion ->
            balanceVersion to rateVersion
        }
        val sourceSnapshots = combine(
            goalRepository.getGoalByIdFlow(goalId),
            assetRepository.getAllAssets(),
            allocationRepository.getAllAllocationsFlow(),
            transactionRepository.getAllTransactions()
        ) { goal, assets, allocations, transactions ->
            AllocationInputs(
                goal = goal,
                assets = assets,
                allocations = allocations,
                transactions = transactions
            )
        }
        return combine(sourceSnapshots, invalidations) { inputs, _ -> inputs }
    }

    private fun startCalculation(inputs: AllocationInputs) {
        val generation = ++calculationGeneration
        calculationJob?.cancel()
        _financialSnapshot.update { it.copy(isLoading = true, error = null) }
        calculationJob = viewModelScope.launch {
            val snapshot = try {
                buildFinancialSnapshot(inputs)
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (error: Throwable) {
                AllocationFinancialSnapshot(
                    goal = inputs.goal,
                    isLoading = false,
                    error = error.message ?: "Failed to load allocations"
                )
            }
            if (generation == calculationGeneration) {
                _financialSnapshot.value = snapshot
            }
        }
    }

    private suspend fun buildFinancialSnapshot(
        inputs: AllocationInputs
    ): AllocationFinancialSnapshot = coroutineScope {
        val assetsById = inputs.assets.associateBy { it.id }
        val manualBalanceByAssetId = inputs.transactions
            .filter { it.source == TransactionSource.MANUAL }
            .groupBy { it.assetId }
            .mapValues { (_, transactions) -> transactions.sumOf { it.amount } }
        val totalAllocatedByAssetId = inputs.allocations
            .groupBy { it.assetId }
            .mapValues { (_, allocations) -> allocations.sumOf { it.amount } }
        val goalAllocations = inputs.allocations.filter { it.goalId == goalId }
        val balanceByAssetId = goalAllocations
            .map { it.assetId }
            .distinct()
            .map { assetId ->
                async {
                    val asset = assetsById[assetId]
                    val balanceResolution = asset?.let {
                        AssetBalanceCompletenessResolver.resolve(
                            asset = it,
                            manualBalance = manualBalanceByAssetId[assetId] ?: 0.0,
                            repository = onChainBalanceRepository,
                            forceRefresh = false
                        )
                    }
                    assetId to balanceResolution
                }
            }
            .awaitAll()
            .toMap()
        val withDetails = goalAllocations.map { allocation ->
            val asset = assetsById[allocation.assetId]
            val balanceResolution = balanceByAssetId[allocation.assetId]
            val balance = balanceResolution?.totalBalanceOrNull
            val balanceIssue = balanceResolution?.issueOrNull
                ?: if (asset == null) {
                    "Asset is unavailable. Restore the asset and retry."
                } else {
                    null
                }
            val totalAllocatedFromAsset = totalAllocatedByAssetId[allocation.assetId] ?: 0.0
            AllocationWithDetails(
                allocation = allocation,
                asset = asset,
                assetBalance = balance,
                assetTotalAllocated = totalAllocatedFromAsset,
                assetDisplayName = asset?.displayName() ?: "Unknown Asset",
                isAssetOverAllocated = balance?.let {
                    totalAllocatedFromAsset > it + 0.0000001
                },
                balanceIssue = balanceIssue
            )
        }
        AllocationFinancialSnapshot(
            goal = inputs.goal,
            allocations = withDetails,
            totals = calculateTotals(inputs.goal, withDetails),
            isLoading = false
        )
    }

    fun requestDeleteAllocation(allocation: Allocation) {
        _showDeleteConfirmation.value = allocation
    }

    fun dismissDeleteConfirmation() {
        _showDeleteConfirmation.value = null
    }

    fun confirmDeleteAllocation() {
        val allocation = _showDeleteConfirmation.value ?: return
        viewModelScope.launch {
            deleteAllocationUseCase(
                allocationId = allocation.id,
                assetId = allocation.assetId,
                goalId = allocation.goalId
            ).fold(
                onSuccess = {
                    _showDeleteConfirmation.value = null
                },
                onFailure = { e ->
                    _error.value = e.message ?: "Failed to delete allocation"
                    _showDeleteConfirmation.value = null
                }
            )
        }
    }

    fun clearError() {
        _error.value = null
    }

    private suspend fun calculateTotals(
        goal: Goal?,
        allocations: List<AllocationWithDetails>
    ): AllocationTotals {
        val goalCurrency = goal?.currency ?: return AllocationTotals()
        var allocated = 0.0
        var funded = 0.0
        var missingRates = false
        var allocatedComplete = true
        var fundedComplete = true
        val issues = linkedSetOf<String>()

        for (item in allocations) {
            val assetCurrency = item.asset?.currency
            if (assetCurrency == null) {
                allocatedComplete = false
                fundedComplete = false
                issues += item.balanceIssue ?: "Allocation asset is unavailable."
                continue
            }
            val allocationAmount = item.allocation.amount
            val fundedAmount = item.fundedAmount

            val allocatedValue = convertOrNull(allocationAmount, assetCurrency, goalCurrency)
            if (allocatedValue == null) {
                missingRates = true
                allocatedComplete = false
                fundedComplete = false
                issues += "Exchange rate $assetCurrency → $goalCurrency is unavailable."
                continue
            }
            allocated += allocatedValue

            if (fundedAmount == null) {
                fundedComplete = false
                issues += item.balanceIssue ?: "Asset balance is unavailable."
                continue
            }
            val fundedValue = convertOrNull(fundedAmount, assetCurrency, goalCurrency)
            if (fundedValue == null) {
                missingRates = true
                fundedComplete = false
                issues += "Exchange rate $assetCurrency → $goalCurrency is unavailable."
                continue
            }
            funded += fundedValue
        }

        return AllocationTotals(
            totalAllocatedInGoalCurrency = allocated.takeIf { allocatedComplete },
            totalFundedInGoalCurrency = funded.takeIf { fundedComplete },
            hasMissingExchangeRates = missingRates,
            financialDataIssue = issues.takeIf { it.isNotEmpty() }?.joinToString(" ")
        )
    }

    private suspend fun convertOrNull(amount: Double, from: String, to: String): Double? {
        if (from.equals(to, ignoreCase = true)) return amount
        val rate = runCatching { exchangeRateRepository.fetchRate(from, to) }.getOrNull()
        return rate
            ?.takeIf { it.isFinite() && it > 0.0 }
            ?.let { amount * it }
            ?.takeIf(Double::isFinite)
    }
}

private data class AllocationTotals(
    val totalAllocatedInGoalCurrency: Double? = null,
    val totalFundedInGoalCurrency: Double? = null,
    val hasMissingExchangeRates: Boolean = false,
    val financialDataIssue: String? = null
)

private data class AllocationInputs(
    val goal: Goal?,
    val assets: List<Asset>,
    val allocations: List<Allocation>,
    val transactions: List<Transaction>
)

private data class AllocationFinancialSnapshot(
    val goal: Goal? = null,
    val allocations: List<AllocationWithDetails> = emptyList(),
    val totals: AllocationTotals = AllocationTotals(),
    val isLoading: Boolean = true,
    val error: String? = null
)
