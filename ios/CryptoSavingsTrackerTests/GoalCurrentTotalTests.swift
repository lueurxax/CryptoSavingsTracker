//
//  GoalCurrentTotalTests.swift
//  CryptoSavingsTrackerTests
//
//  Minimal placeholder to satisfy legacy references.
//

import Testing
import Foundation
@testable import CryptoSavingsTracker

@MainActor
struct GoalCurrentTotalTests {
    private struct NoOpTatumService: TatumServiceProtocol {
        var supportedChains: [TatumChain] { [] }

        func predictChain(for symbol: String) -> TatumChain? {
            nil
        }

        func fetchBalance(
            chainId: String,
            address: String,
            symbol: String,
            forceRefresh: Bool
        ) async throws -> Double {
            0
        }

        func fetchTransactionHistory(
            chainId: String,
            address: String,
            currency: String?,
            limit: Int,
            forceRefresh: Bool
        ) async throws -> [TatumTransaction] {
            []
        }

        func hasValidConfiguration() -> Bool {
            true
        }

        func setOfflineMode(_ offline: Bool) {}
    }

    @Test("Current total placeholder")
    func testCurrentTotalPlaceholder() async throws {
        // Basic sanity: a goal with no allocations has zero current total.
        let goal = Goal(
            name: "Placeholder",
            currency: "USD",
            targetAmount: 1000,
            deadline: Date().addingTimeInterval(86400)
        )
        #expect(goal.currentTotal == 0)
    }

    @Test("Refreshing a goal without reminders preserves its day-based suggested deposit")
    func refreshPreservesDayBasedSuggestedDepositWithoutReminders() async {
        let deadline = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        let goal = Goal(
            name: "Emergency fund",
            currency: "USD",
            targetAmount: 1_000,
            deadline: deadline
        )
        let expectedSuggestion = goal.suggestedDailyDeposit
        let viewModel = GoalViewModel(
            goal: goal,
            tatumService: NoOpTatumService(),
            exchangeRateService: MockExchangeRateService()
        )

        #expect(expectedSuggestion > 0)

        await viewModel.refreshValues()

        #expect(abs(viewModel.suggestedDeposit - expectedSuggestion) < 0.000_001)
    }

    @Test("Goal detail view model switches its represented goal")
    func goalDetailViewModelSwitchesRepresentedGoal() async {
        let firstGoal = Goal(
            name: "First",
            currency: "USD",
            targetAmount: 100,
            deadline: Date().addingTimeInterval(86_400)
        )
        let secondGoal = Goal(
            name: "Second",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )
        let asset = Asset(currency: "USD")
        let transaction = Transaction(amount: 250, asset: asset)
        let allocation = AssetAllocation(asset: asset, goal: secondGoal, amount: 250)
        asset.transactions = [transaction]
        asset.allocations = [allocation]
        secondGoal.allocations = [allocation]
        let viewModel = GoalViewModel(
            goal: firstGoal,
            tatumService: NoOpTatumService(),
            exchangeRateService: MockExchangeRateService()
        )

        viewModel.updateGoal(secondGoal)
        await viewModel.refreshValues()

        #expect(viewModel.currentTotal == 250)
        #expect(viewModel.progress == 0.25)
    }

    @Test("Latest refresh owns same-goal values and loading state")
    func latestRefreshOwnsSameGoalValuesAndLoadingState() async {
        let goal = Goal(
            name: "Concurrent refresh",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )
        let asset = Asset(currency: "USD", address: "0x123", chainId: "ethereum")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 1_000)
        asset.allocations = [allocation]
        goal.allocations = [allocation]
        let balances = SequencedBalanceService()
        let viewModel = GoalViewModel(
            goal: goal,
            tatumService: balances,
            exchangeRateService: MockExchangeRateService()
        )

        let firstRefresh = Task { await viewModel.refreshValues() }
        await balances.waitForRequestCount(1)
        let secondRefresh = Task { await viewModel.refreshValues() }
        await balances.waitForRequestCount(2)

        balances.resumeRequest(at: 0, with: 100)
        _ = await firstRefresh.value

        #expect(viewModel.isLoading)
        #expect(viewModel.currentTotal == 0)

        balances.resumeRequest(at: 1, with: 200)
        _ = await secondRefresh.value

        #expect(viewModel.isLoading == false)
        #expect(viewModel.currentTotal == 200)
        #expect(viewModel.progress == 0.2)
    }

    @Test("Goal calculation preserves degraded status when one asset conversion fails")
    func goalCalculationPreservesPartialConversionFailure() async {
        let goal = Goal(
            name: "Mixed currency goal",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )
        let usdAsset = Asset(currency: "USD")
        let eurAsset = Asset(currency: "EUR")
        let usdTransaction = Transaction(amount: 100, asset: usdAsset)
        let eurTransaction = Transaction(amount: 50, asset: eurAsset)
        usdAsset.transactions = [usdTransaction]
        eurAsset.transactions = [eurTransaction]

        let usdAllocation = AssetAllocation(asset: usdAsset, goal: goal, amount: 100)
        let eurAllocation = AssetAllocation(asset: eurAsset, goal: goal, amount: 50)
        goal.allocations = [usdAllocation, eurAllocation]
        usdAsset.allocations = [usdAllocation]
        eurAsset.allocations = [eurAllocation]

        let rates = MockExchangeRateService()
        rates.shouldFail = true
        let service = GoalCalculationService(
            exchangeRateService: rates,
            tatumService: NoOpTatumService()
        )

        let result = await service.getCurrentTotalResult(for: goal)

        #expect(result.total == 100)
        #expect(result.isComplete == false)
        #expect(result.error != nil)
    }

    @Test("Production goal row exposes unavailable financial totals without recording success")
    func goalRowExposesUnavailableFinancialTotal() async {
        let goal = Goal(
            name: "Unavailable balance",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )
        var loadCount = 0
        let viewModel = GoalRowViewModel(
            goal: goal,
            currentTotalLoader: { _ in
                loadCount += 1
                return GoalCurrentTotalResult(
                    total: 0,
                    error: UserFacingError(
                        title: "Balances Not Refreshed",
                        message: "One provider is unavailable."
                    )
                )
            }
        )

        await viewModel.loadAsyncProgress()

        #expect(loadCount == 1)
        #expect(viewModel.lastSuccessfulLoad == nil)
        #expect(viewModel.hasError)
        #expect(viewModel.hasLoadedInitialData)
        #expect(viewModel.amountText.contains("unavailable"))
        #expect(viewModel.progressPercentageText == "Progress unavailable")
        guard case .degraded = viewModel.viewState else {
            Issue.record("A partial goal total must remain visibly degraded.")
            return
        }
    }

    @Test("Production goal row labels a nonzero partial total and only records a later complete load")
    func goalRowLabelsPartialThenRecordsCompleteLoad() async {
        let goal = Goal(
            name: "Partial balance",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )
        var shouldSucceed = false
        let viewModel = GoalRowViewModel(
            goal: goal,
            currentTotalLoader: { _ in
                if shouldSucceed {
                    return GoalCurrentTotalResult(total: 250, error: nil)
                }
                return GoalCurrentTotalResult(
                    total: 100,
                    error: UserFacingError(
                        title: "Balances Not Refreshed",
                        message: "One conversion failed."
                    )
                )
            }
        )

        await viewModel.loadAsyncProgress()
        #expect(viewModel.amountText.contains("Partial"))
        #expect(viewModel.lastSuccessfulLoad == nil)

        shouldSucceed = true
        await viewModel.retry()

        #expect(viewModel.amountText.contains("Partial") == false)
        #expect(viewModel.lastSuccessfulLoad != nil)
        #expect(viewModel.viewState == .loaded)
    }

    @Test("Goal row remains degraded while a retry is suspended")
    func goalRowPreservesDegradedStateDuringSuspendedRetry() async {
        let goal = Goal(
            name: "Suspended retry",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )
        let gate = GoalTotalLoadGate()
        var isInitialLoad = true
        let viewModel = GoalRowViewModel(
            goal: goal,
            currentTotalLoader: { _ in
                if isInitialLoad {
                    isInitialLoad = false
                    return GoalCurrentTotalResult(
                        total: 100,
                        error: UserFacingError(
                            title: "Balances Not Refreshed",
                            message: "One provider is unavailable."
                        )
                    )
                }
                return await gate.wait()
            }
        )

        await viewModel.loadAsyncProgress()
        #expect(viewModel.hasError)
        guard case .degraded = viewModel.viewState else {
            Issue.record("The initial partial load must be degraded.")
            return
        }

        let retry = Task { await viewModel.retry() }
        while !gate.isWaiting {
            await Task.yield()
        }

        #expect(viewModel.hasError)
        #expect(viewModel.amountText.contains("Partial"))
        #expect(viewModel.progressPercentageText == "Progress unavailable")
        guard case .degraded = viewModel.viewState else {
            Issue.record("A suspended retry must not promote stale partial data to loading success.")
            gate.resume(with: GoalCurrentTotalResult(total: 250, error: nil))
            await retry.value
            return
        }

        gate.resume(with: GoalCurrentTotalResult(total: 250, error: nil))
        await retry.value

        #expect(viewModel.hasError == false)
        #expect(viewModel.viewState == .loaded)
        #expect(viewModel.amountText.contains("Partial") == false)
    }

    @Test("Dashboard snapshot withholds a degraded goal total")
    func dashboardSnapshotWithholdsDegradedGoalTotal() {
        let result = GoalCurrentTotalResult(
            total: 100,
            error: UserFacingError(
                title: "Balances Not Refreshed",
                message: "One conversion failed."
            )
        )

        let snapshot = DashboardGoalSnapshot(
            calculationResult: result,
            targetAmount: 1_000
        )

        #expect(snapshot.currentTotal == nil)
        #expect(snapshot.progress == nil)
    }

    @Test("Dashboard portfolio rejects a degraded goal total")
    func dashboardPortfolioRejectsDegradedGoalTotal() async {
        let result = GoalCurrentTotalResult(
            total: 100,
            error: UserFacingError(
                title: "Balances Not Refreshed",
                message: "One conversion failed."
            )
        )

        await #expect(throws: DashboardPortfolioTotalError.self) {
            try await DashboardPortfolioTotalCalculator.total(
                entries: [
                    DashboardPortfolioEntry(
                        calculationResult: result,
                        currency: "USD"
                    )
                ],
                displayCurrency: "USD",
                exchangeRateService: MockExchangeRateService()
            )
        }
    }

    @Test("Dashboard trend reports unavailable when currency conversion fails")
    func dashboardTrendReportsConversionFailure() async {
        let rates = MockExchangeRateService()
        rates.shouldFail = true
        let endDate = Date(timeIntervalSince1970: 1_752_019_200)

        let state = await DashboardActivityTrendLoader.load(
            entries: [
                DashboardActivityEntry(
                    amount: 10,
                    currency: "EUR",
                    date: endDate
                )
            ],
            displayCurrency: "USD",
            endDate: endDate,
            exchangeRateService: rates
        )

        guard case .unavailable = state else {
            Issue.record("A conversion failure must not be presented as an empty activity trend.")
            return
        }
    }

    @Test("Dashboard refresh fingerprint changes when an active goal retires")
    func dashboardFingerprintTracksLifecycleChanges() {
        let goal = Goal(
            name: "Active goal",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )
        let before = DashboardPortfolioRefreshFingerprint(
            displayCurrency: "USD",
            goals: [goal]
        )

        goal.markCancelled(at: Date(timeIntervalSince1970: 10_000))

        let after = DashboardPortfolioRefreshFingerprint(
            displayCurrency: "USD",
            goals: [goal]
        )

        #expect(before != after)
        #expect(before.goals.count == 1)
        #expect(after.goals.isEmpty)
    }

    @Test("Dashboard refresh fingerprint changes with allocation inputs")
    func dashboardFingerprintTracksFinancialInputs() {
        let goal = Goal(
            name: "Allocation goal",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )
        let asset = Asset(currency: "BTC")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 0.1)
        goal.allocations = [allocation]
        asset.allocations = [allocation]

        let before = DashboardPortfolioRefreshFingerprint(
            displayCurrency: "USD",
            goals: [goal]
        )

        allocation.updateAmount(0.2)

        let after = DashboardPortfolioRefreshFingerprint(
            displayCurrency: "USD",
            goals: [goal]
        )

        #expect(before != after)
    }

    @Test("Dashboard refresh rejects a late result from a superseded generation")
    func dashboardRefreshRejectsSupersededGeneration() {
        let generationGuard = DashboardRefreshGenerationGuard()
        let staleGeneration = generationGuard.begin()
        let currentGeneration = generationGuard.begin()
        var committedValue = "initial"

        let acceptedStaleResult = generationGuard.commitIfCurrent(staleGeneration) {
            committedValue = "stale"
        }

        #expect(acceptedStaleResult == false)
        #expect(committedValue == "initial")

        let acceptedCurrentResult = generationGuard.commitIfCurrent(currentGeneration) {
            committedValue = "current"
        }

        #expect(acceptedCurrentResult)
        #expect(committedValue == "current")
    }

    @Test("Dashboard refresh identity changes after exchange rates refresh")
    func dashboardRefreshIdentityTracksRateRefreshes() {
        let goal = Goal(
            name: "Mixed currency goal",
            currency: "EUR",
            targetAmount: 1_000,
            deadline: Date().addingTimeInterval(86_400)
        )
        let portfolioFingerprint = DashboardPortfolioRefreshFingerprint(
            displayCurrency: "USD",
            goals: [goal]
        )

        let before = DashboardRefreshRequestID(
            portfolioFingerprint: portfolioFingerprint,
            exchangeRateGeneration: 0,
            calendarDayStart: Date(timeIntervalSince1970: 1_752_019_200)
        )
        let after = DashboardRefreshRequestID(
            portfolioFingerprint: portfolioFingerprint,
            exchangeRateGeneration: 1,
            calendarDayStart: Date(timeIntervalSince1970: 1_752_019_200)
        )

        #expect(before != after)
    }

    @Test("Dashboard refresh identity changes at the next calendar day")
    func dashboardRefreshIdentityTracksCalendarDay() {
        let portfolioFingerprint = DashboardPortfolioRefreshFingerprint(
            displayCurrency: "USD",
            goals: []
        )
        let dayStart = Date(timeIntervalSince1970: 1_752_019_200)

        let before = DashboardRefreshRequestID(
            portfolioFingerprint: portfolioFingerprint,
            exchangeRateGeneration: 0,
            calendarDayStart: dayStart
        )
        let after = DashboardRefreshRequestID(
            portfolioFingerprint: portfolioFingerprint,
            exchangeRateGeneration: 0,
            calendarDayStart: dayStart.addingTimeInterval(86_400)
        )

        #expect(before != after)
    }

    @Test("Dashboard activity trend converts signed transactions into display currency")
    func dashboardActivityTrendConvertsSignedTransactions() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let endDate = Date(timeIntervalSince1970: 1_752_019_200) // 2025-07-09 00:00:00 UTC
        let rates = MockExchangeRateService()
        rates.setRate(from: "EUR", to: "USD", rate: 2)

        let points = try await DashboardActivityTrendCalculator.points(
            entries: [
                DashboardActivityEntry(
                    amount: 10,
                    currency: "EUR",
                    date: calendar.date(byAdding: .day, value: -1, to: endDate)!
                ),
                DashboardActivityEntry(
                    amount: -1,
                    currency: "EUR",
                    date: endDate
                ),
                DashboardActivityEntry(
                    amount: 999,
                    currency: "EUR",
                    date: calendar.date(byAdding: .day, value: -8, to: endDate)!
                )
            ],
            displayCurrency: "USD",
            endDate: endDate,
            calendar: calendar,
            exchangeRateService: rates
        )

        #expect(points.count == 7)
        #expect(points.allSatisfy { $0.currency == "USD" })
        #expect(points[5].balance == 20)
        #expect(points[6].balance == 18)
    }
}

@MainActor
private final class GoalTotalLoadGate {
    private var continuation: CheckedContinuation<GoalCurrentTotalResult, Never>?

    var isWaiting: Bool {
        continuation != nil
    }

    func wait() async -> GoalCurrentTotalResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with result: GoalCurrentTotalResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
private final class SequencedBalanceService: TatumServiceProtocol {
    private var continuations: [CheckedContinuation<Double, Error>?] = []

    var supportedChains: [TatumChain] { [] }

    func predictChain(for symbol: String) -> TatumChain? {
        nil
    }

    func fetchBalance(
        chainId: String,
        address: String,
        symbol: String,
        forceRefresh: Bool
    ) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func fetchTransactionHistory(
        chainId: String,
        address: String,
        currency: String?,
        limit: Int,
        forceRefresh: Bool
    ) async throws -> [TatumTransaction] {
        []
    }

    func hasValidConfiguration() -> Bool {
        true
    }

    func setOfflineMode(_ offline: Bool) {
    }

    func waitForRequestCount(_ expectedCount: Int) async {
        while continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func resumeRequest(at index: Int, with balance: Double) {
        let continuation = continuations[index]
        continuations[index] = nil
        continuation?.resume(returning: balance)
    }
}
