import Foundation

/// Listens to rate-refresh events and evaluates whether exchange rate changes
/// materially alter any shared goal's `currentAmount`.
///
/// If material drift is detected, emits a `.rateDrift` dirty event into the
/// auto-republish coordinator.
actor FamilyShareRateDriftEvaluator {

    private let calculator: GoalProgressCalculator
    private let materialityPolicy: FamilyShareMaterialityPolicy
    private let rateRefreshSource: FamilyShareRateRefreshSource
    private let rollout: FamilyShareRollout

    /// Handler called when material rate drift is detected.
    private var onDirtyEvent: ((FamilyShareProjectionDirtyReason) -> Void)?

    /// Last published amounts per goal for materiality comparison.
    private var lastPublishedAmounts: [UUID: Decimal] = [:]

    /// Goal inputs for rate-drift evaluation.
    private var trackedGoalInputs: [GoalProgressInput] = []

    /// Task running the rate-refresh listener.
    private var listenerTask: Task<Void, Never>?

    init(
        calculator: GoalProgressCalculator = GoalProgressCalculator(),
        materialityPolicy: FamilyShareMaterialityPolicy = FamilyShareMaterialityPolicy(),
        rateRefreshSource: FamilyShareRateRefreshSource = NotificationCenterRateRefreshSource(),
        rollout: FamilyShareRollout = .shared
    ) {
        self.calculator = calculator
        self.materialityPolicy = materialityPolicy
        self.rateRefreshSource = rateRefreshSource
        self.rollout = rollout
    }

    /// Start listening to rate-refresh events.
    func start(
        goalInputs: [GoalProgressInput],
        lastPublished: [UUID: Decimal],
        handler: @escaping (FamilyShareProjectionDirtyReason) -> Void
    ) {
        guard rollout.isFreshnessPipelineEnabled() else { return }

        self.trackedGoalInputs = goalInputs
        self.lastPublishedAmounts = lastPublished
        self.onDirtyEvent = handler

        listenerTask = Task { [weak self] in
            guard let self else { return }
            for await event in rateRefreshSource.ratesDidRefresh {
                guard !Task.isCancelled else { break }
                await self.evaluateDrift(rateEvent: event)
            }
        }
    }

    /// Update tracked goals (called when allocations change).
    func updateTrackedGoals(_ inputs: [GoalProgressInput], lastPublished: [UUID: Decimal]) {
        self.trackedGoalInputs = inputs
        self.lastPublishedAmounts = lastPublished
    }

    /// Teardown for rollback.
    func teardown() {
        listenerTask?.cancel()
        listenerTask = nil
        onDirtyEvent = nil
        trackedGoalInputs = []
        lastPublishedAmounts = [:]
    }

    // MARK: - Private

    private func evaluateDrift(rateEvent: RateRefreshEvent) {
        guard rollout.isFreshnessPipelineEnabled() else { return }

        let rateSnapshot = RateSnapshot(
            rates: rateEvent.rates,
            timestamp: rateEvent.rateSnapshotTimestamp
        )

        var materialGoalIDs: Set<UUID> = []

        for input in trackedGoalInputs {
            let result = calculator.calculateProgress(for: input, rates: rateSnapshot)
            let lastAmount = lastPublishedAmounts[input.goalID] ?? 0

            // Get USD-to-goal-currency rate for materiality check
            let usdPair = CurrencyPair(from: "USD", to: input.currency)
            let usdToGoalRate = rateEvent.rates[usdPair]

            if materialityPolicy.isMaterial(
                newAmount: result.currentAmount,
                lastPublishedAmount: lastAmount,
                targetAmount: input.targetAmount,
                goalCurrency: input.currency,
                usdToGoalCurrencyRate: usdToGoalRate
            ) {
                materialGoalIDs.insert(input.goalID)
            }
        }

        if !materialGoalIDs.isEmpty {
            FamilyShareTelemetryTracker().track(.rateDriftEvaluated, payload: [
                "materialGoalCount": "\(materialGoalIDs.count)"
            ])
            onDirtyEvent?(.rateDrift(goalIDs: materialGoalIDs))
        } else {
            FamilyShareTelemetryTracker().track(.rateDriftBelowThreshold)
        }
    }
}
