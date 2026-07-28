package com.xax.CryptoSavingsTracker.presentation.onboarding

import android.content.Context
import android.content.SharedPreferences
import com.google.common.truth.Truth.assertThat
import com.xax.CryptoSavingsTracker.domain.model.Asset
import com.xax.CryptoSavingsTracker.domain.model.Goal
import com.xax.CryptoSavingsTracker.domain.model.GoalLifecycleStatus
import com.xax.CryptoSavingsTracker.domain.reminders.GoalReminderScheduler
import com.xax.CryptoSavingsTracker.domain.repository.AssetRepository
import com.xax.CryptoSavingsTracker.domain.repository.GoalRepository
import com.xax.CryptoSavingsTracker.domain.usecase.asset.AddAssetUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.asset.GetAssetsUseCase
import com.xax.CryptoSavingsTracker.domain.usecase.goal.AddGoalUseCase
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class OnboardingViewModelTest {
    @Test
    fun `completion persists every selected asset before reporting complete`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val assetRepository = RecordingAssetRepository()
            val viewModel = viewModel(assetRepository)
            viewModel.toggleAsset("BTC")
            viewModel.toggleAsset("ETH")

            completeCurrentOnboarding(viewModel)
            advanceUntilIdle()

            assertThat(assetRepository.insertedAssets.map { it.currency })
                .containsExactly("BTC", "ETH")
            assertThat(viewModel.uiState.value.isComplete).isTrue()
            assertThat(viewModel.uiState.value.error).isNull()
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `asset persistence failure leaves onboarding incomplete and exposes error`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val assetRepository = RecordingAssetRepository(failingCurrency = "ETH")
            val viewModel = viewModel(assetRepository)
            viewModel.toggleAsset("BTC")
            viewModel.toggleAsset("ETH")

            completeCurrentOnboarding(viewModel)
            advanceUntilIdle()

            assertThat(viewModel.uiState.value.isComplete).isFalse()
            assertThat(viewModel.uiState.value.isLoading).isFalse()
            assertThat(viewModel.uiState.value.error).contains("ETH")
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `skip bypasses setup persistence and emits navigation exactly once`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val assetRepository = RecordingAssetRepository(failingCurrency = "BTC")
            val goalRepository = RecordingGoalRepository()
            val viewModel = viewModel(assetRepository, goalRepository)
            val events = mutableListOf<OnboardingEvent>()
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
                viewModel.events.collect(events::add)
            }

            viewModel.toggleAsset("BTC")
            viewModel.selectTemplate(GoalTemplate.VACATION)

            viewModel.skip()
            viewModel.skip()
            advanceUntilIdle()

            assertThat(assetRepository.getAllAssetsCallCount).isEqualTo(0)
            assertThat(assetRepository.attemptedInsertCurrencies).isEmpty()
            assertThat(goalRepository.insertedGoals).isEmpty()
            assertThat(viewModel.uiState.value.isComplete).isTrue()
            assertThat(viewModel.uiState.value.isLoading).isFalse()
            assertThat(viewModel.uiState.value.error).isNull()
            assertThat(events).containsExactly(OnboardingEvent.NavigateToDashboard)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `retry after partial failure persists each selected asset exactly once`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val assetRepository = RecordingAssetRepository(failingCurrency = "ETH")
            val viewModel = viewModel(assetRepository)
            viewModel.toggleAsset("BTC")
            viewModel.toggleAsset("ETH")

            completeCurrentOnboarding(viewModel)
            advanceUntilIdle()

            assertThat(assetRepository.insertedAssets.map { it.currency })
                .containsExactly("BTC")
            assertThat(viewModel.uiState.value.isComplete).isFalse()

            assetRepository.failingCurrency = null
            viewModel.nextStep()
            advanceUntilIdle()

            assertThat(assetRepository.insertedAssets.map { it.currency })
                .containsExactly("BTC", "ETH")
            assertThat(viewModel.uiState.value.isComplete).isTrue()
            assertThat(viewModel.uiState.value.error).isNull()
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `retry compares canonical MATIC identity and does not insert a second manual POL asset`() =
        runTest {
            val dispatcher = StandardTestDispatcher(testScheduler)
            Dispatchers.setMain(dispatcher)

            try {
                val assetRepository = RecordingAssetRepository(failingCurrency = "ZZZ")
                val viewModel = viewModel(assetRepository)
                viewModel.toggleAsset("MATIC")
                viewModel.toggleAsset("ZZZ")

                completeCurrentOnboarding(viewModel)
                advanceUntilIdle()

                assertThat(assetRepository.insertedAssets.map { it.currency })
                    .containsExactly("POL")
                assertThat(viewModel.uiState.value.isComplete).isFalse()

                assetRepository.failingCurrency = null
                viewModel.nextStep()
                advanceUntilIdle()

                assertThat(assetRepository.insertedAssets.map { it.currency })
                    .containsExactly("POL", "ZZZ")
                assertThat(viewModel.uiState.value.isComplete).isTrue()
            } finally {
                Dispatchers.resetMain()
            }
        }

    @Test
    fun `two immediate completion requests persist setup and emit navigation once`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val assetRepository = RecordingAssetRepository()
            val goalRepository = RecordingGoalRepository()
            val viewModel = viewModel(assetRepository, goalRepository)
            val events = mutableListOf<OnboardingEvent>()
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
                viewModel.events.collect(events::add)
            }

            viewModel.nextStep()
            viewModel.nextStep()
            viewModel.selectTemplate(GoalTemplate.VACATION)
            viewModel.nextStep()
            viewModel.nextStep()

            viewModel.nextStep()
            viewModel.nextStep()
            advanceUntilIdle()

            assertThat(assetRepository.insertedAssets.map { it.currency })
                .containsExactly("BTC", "ETH")
            assertThat(goalRepository.insertedGoals).hasSize(1)
            assertThat(events).containsExactly(OnboardingEvent.NavigateToDashboard)
            assertThat(viewModel.uiState.value.isComplete).isTrue()
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `process restart with a different template does not create a second setup goal`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)

        try {
            val assetRepository = RecordingAssetRepository()
            val goalRepository = RecordingGoalRepository()

            completeWithTemplate(viewModel(assetRepository, goalRepository), GoalTemplate.VACATION)
            advanceUntilIdle()

            // Simulate a process restart before the asynchronous completion preference was durable.
            completeWithTemplate(viewModel(assetRepository, goalRepository), GoalTemplate.NEW_CAR)
            advanceUntilIdle()

            assertThat(goalRepository.insertedGoals).hasSize(1)
            assertThat(goalRepository.insertedGoals.single().name)
                .isEqualTo("String ${GoalTemplate.VACATION.titleResId}")
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `primary action is disabled while completion is loading`() {
        val state = OnboardingUiState(currentStep = 4, isLoading = true)

        assertThat(state.canProceed).isFalse()
    }

    private fun viewModel(
        assetRepository: AssetRepository,
        goalRepository: GoalRepository = RecordingGoalRepository()
    ): OnboardingViewModel {
        val context = mockk<Context>()
        val prefs = mockk<SharedPreferences>()
        val editor = mockk<SharedPreferences.Editor>(relaxed = true)

        every { context.getSharedPreferences(ONBOARDING_PREFS_NAME, Context.MODE_PRIVATE) } returns prefs
        every { context.getString(any()) } answers { "String ${firstArg<Int>()}" }
        every { prefs.getBoolean(ONBOARDING_COMPLETED_KEY, false) } returns false
        every { prefs.edit() } returns editor
        every { editor.putBoolean(any(), any()) } returns editor

        return OnboardingViewModel(
            context = context,
            addGoalUseCase = AddGoalUseCase(goalRepository, NoOpGoalReminderScheduler),
            addAssetUseCase = AddAssetUseCase(assetRepository),
            getAssetsUseCase = GetAssetsUseCase(assetRepository)
        )
    }

    private fun completeCurrentOnboarding(viewModel: OnboardingViewModel) {
        repeat(5) {
            viewModel.nextStep()
        }
    }

    private fun completeWithTemplate(
        viewModel: OnboardingViewModel,
        template: GoalTemplate
    ) {
        viewModel.nextStep()
        viewModel.nextStep()
        viewModel.selectTemplate(template)
        viewModel.nextStep()
        viewModel.nextStep()
        viewModel.nextStep()
    }
}

private class RecordingAssetRepository(
    var failingCurrency: String? = null
) : AssetRepository {
    val insertedAssets = mutableListOf<Asset>()
    val attemptedInsertCurrencies = mutableListOf<String>()
    var getAllAssetsCallCount = 0

    override fun getAllAssets(): Flow<List<Asset>> {
        getAllAssetsCallCount += 1
        return flowOf(insertedAssets)
    }

    override fun getAssetsByCurrency(currency: String): Flow<List<Asset>> =
        flowOf(insertedAssets.filter { it.currency == currency })

    override suspend fun getAssetById(id: String): Asset? =
        insertedAssets.firstOrNull { it.id == id }

    override fun getAssetByIdFlow(id: String): Flow<Asset?> =
        flowOf(insertedAssets.firstOrNull { it.id == id })

    override suspend fun getAssetByAddress(address: String): Asset? =
        insertedAssets.firstOrNull { it.address == address }

    override suspend fun insertAsset(asset: Asset) {
        attemptedInsertCurrencies += asset.currency
        if (asset.currency == failingCurrency) {
            throw IllegalStateException("Failed to persist ${asset.currency}")
        }
        insertedAssets += asset
    }

    override suspend fun updateAsset(asset: Asset) = Unit

    override suspend fun deleteAsset(id: String) = Unit

    override suspend fun deleteAsset(asset: Asset) = Unit

    override suspend fun getAssetCount(): Int = insertedAssets.size
}

private class RecordingGoalRepository : GoalRepository {
    val insertedGoals = mutableListOf<Goal>()
    private val goals = MutableStateFlow<Map<String, Goal>>(emptyMap())

    override fun getAllGoals(): Flow<List<Goal>> = goals.map { it.values.toList() }

    override fun getGoalsByStatus(status: GoalLifecycleStatus): Flow<List<Goal>> =
        goals.map { values -> values.values.filter { it.lifecycleStatus == status } }

    override fun getActiveGoals(): Flow<List<Goal>> =
        getGoalsByStatus(GoalLifecycleStatus.ACTIVE)

    override suspend fun getGoalById(id: String): Goal? = goals.value[id]

    override fun getGoalByIdFlow(id: String): Flow<Goal?> = goals.map { it[id] }

    override suspend fun insertGoal(goal: Goal) {
        insertedGoals += goal
        goals.value += goal.id to goal
    }

    override suspend fun updateGoal(goal: Goal) {
        goals.value += goal.id to goal
    }

    override suspend fun deleteGoal(id: String) {
        goals.value -= id
    }

    override suspend fun deleteGoal(goal: Goal) {
        deleteGoal(goal.id)
    }

    override suspend fun updateGoalStatus(id: String, status: GoalLifecycleStatus) {
        val goal = goals.value[id] ?: return
        goals.value += id to goal.copy(lifecycleStatus = status)
    }

    override fun getActiveGoalCount(): Flow<Int> =
        goals.map { values -> values.values.count { it.lifecycleStatus == GoalLifecycleStatus.ACTIVE } }
}

private object NoOpGoalReminderScheduler : GoalReminderScheduler {
    override fun schedule(goal: Goal) = Unit

    override fun cancel(goalId: String) = Unit
}
