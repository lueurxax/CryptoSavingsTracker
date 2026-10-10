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

    /// Cumulative valid rates for the currently tracked goal set.
    private var cumulativeRates: [String: Decimal] = [:]
    private var rateTimestamps: [String: Date] = [:]
    private var calculationRatePairs: Set<String> = []
    private var requiredRatePairs: Set<String> = []

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
        initialRateSnapshot: RateSnapshot? = nil,
        handler: @escaping (FamilyShareProjectionDirtyReason) -> Void
    ) {
        guard rollout.isFreshnessPipelineEnabled() else { return }

        listenerTask?.cancel()
        cumulativeRates = [:]
        rateTimestamps = [:]
        configureTrackedGoals(
            goalInputs,
            lastPublished: lastPublished,
            rateSnapshot: initialRateSnapshot
        )
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
    func updateTrackedGoals(
        _ inputs: [GoalProgressInput],
        lastPublished: [UUID: Decimal],
        rateSnapshot: RateSnapshot? = nil
    ) {
        configureTrackedGoals(
            inputs,
            lastPublished: lastPublished,
            rateSnapshot: rateSnapshot
        )
    }

    /// Teardown for rollback.
    func teardown() {
        listenerTask?.cancel()
        listenerTask = nil
        onDirtyEvent = nil
        trackedGoalInputs = []
        lastPublishedAmounts = [:]
        cumulativeRates = [:]
        rateTimestamps = [:]
        calculationRatePairs = []
        requiredRatePairs = []
    }

    // MARK: - Private

    private func evaluateDrift(rateEvent: RateRefreshEvent) {
        guard rollout.isFreshnessPipelineEnabled() else { return }
        let refreshedRates = rateEvent.rates.filter {
            rateEvent.refreshedPairs.contains($0.key)
        }
        guard mergeRates(
            refreshedRates,
            timestamp: rateEvent.rateSnapshotTimestamp
        ) else {
            return
        }

        let rateSnapshot = RateSnapshot(
            rates: cumulativeRates,
            timestamp: calculationRatePairs
                .compactMap { rateTimestamps[$0] }
                .min() ?? rateEvent.rateSnapshotTimestamp
        )

        var materialGoalIDs: Set<UUID> = []

        for input in trackedGoalInputs {
            let result = calculator.calculateProgress(for: input, rates: rateSnapshot)
            guard result.isComplete else {
                continue
            }
            let lastAmount = lastPublishedAmounts[input.goalID] ?? 0

            // Get USD-to-goal-currency rate for materiality check
            let usdToGoalRate: Decimal?
            if input.currency.caseInsensitiveCompare("USD") == .orderedSame {
                usdToGoalRate = 1
            } else {
                usdToGoalRate = cumulativeRates[
                    CurrencyPair.canonicalKey(from: "USD", to: input.currency)
                ]
            }

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

    private func configureTrackedGoals(
        _ inputs: [GoalProgressInput],
        lastPublished: [UUID: Decimal],
        rateSnapshot: RateSnapshot?
    ) {
        trackedGoalInputs = inputs
        lastPublishedAmounts = lastPublished

        let requirements = FamilyShareRateRequirements(goalInputs: inputs)
        calculationRatePairs = requirements.calculationPairs
        requiredRatePairs = requirements.allPairs
        cumulativeRates = cumulativeRates.filter {
            requiredRatePairs.contains($0.key)
        }
        rateTimestamps = rateTimestamps.filter {
            requiredRatePairs.contains($0.key)
        }

        if let rateSnapshot {
            _ = mergeRates(
                rateSnapshot.rates,
                timestamp: rateSnapshot.timestamp
            )
        }
    }

    @discardableResult
    private func mergeRates(
        _ rates: [String: Decimal],
        timestamp: Date
    ) -> Bool {
        var mergedRequiredRate = false
        for pair in requiredRatePairs {
            guard let rate = rates[pair], rate > 0 else { continue }
            cumulativeRates[pair] = rate
            rateTimestamps[pair] = timestamp
            mergedRequiredRate = true
        }
        return mergedRequiredRate
    }
}
