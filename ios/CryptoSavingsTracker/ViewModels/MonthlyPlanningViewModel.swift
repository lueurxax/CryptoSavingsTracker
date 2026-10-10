//
//  MonthlyPlanningViewModel.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 09/08/2025.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

/// ViewModel for managing monthly planning calculations and UI state
@MainActor
final class MonthlyPlanningViewModel: ObservableObject {
    private struct PlanningLoadIdentity: Equatable {
        let requestID: UUID
        let monthLabel: String
        let displayCurrency: String
    }

    private struct BudgetApplyIdentity {
        let requestID: UUID
        let monthLabel: String
        let amount: MoneyAmount
        let currency: String
        let plan: BudgetCalculatorPlan
        let monthlyPlanIDs: Set<UUID>
        let paymentDay: Int
    }
    
    // MARK: - Published Properties
    
    /// All monthly requirements for active goals
    @Published var monthlyRequirements: [MonthlyRequirement] = []
    
    /// All active goals
    @Published var goals: [Goal] = []
    
    /// Total required amount in display currency
    @Published var totalRequired: Double = 0
    
    /// True when `totalRequired` could not include every goal due to a currency conversion
    /// failure (e.g. exchange rate fetch error). The UI should surface this so users don't
    /// mistake an incomplete total for the real, full requirement.
    @Published var totalRequiredIsPartial: Bool = false

    /// Settings for monthly planning configuration
    private let settings: MonthlyPlanningSettings
    
    /// Display currency for total calculations (derived from settings)
    @Published var displayCurrency: String = "USD"

    /// Month label the planning UI is currently targeting
    @Published var planningMonthLabel: String = ""
    
    /// Access to settings for UI components
    var planningSettings: MonthlyPlanningSettings {
        settings
    }
    
    /// Flex adjustment percentage (0.0 to 1.5, where 1.0 = 100%)
    @Published var flexAdjustment: Double = 1.0
    
    /// Loading state
    @Published var isLoading = false
    
    /// Error state
    @Published var error: Error?
    
    /// Whether flex controls are visible
    @Published var showFlexControls = false
    
    /// Protected goal IDs (won't be reduced in flex adjustments)
    @Published var protectedGoalIds: Set<UUID> = []
    
    /// Skipped goal IDs (temporarily excluded from payments)
    @Published var skippedGoalIds: Set<UUID> = []

    // MARK: - Budget Calculator State

    /// Latest budget calculator preview plan (ephemeral).
    @Published var budgetPreviewPlan: BudgetCalculatorPlan?

    /// Feasibility status for the current budget input.
    @Published var budgetFeasibility: FeasibilityResult = .empty

    /// Timeline blocks for the preview schedule.
    @Published var budgetPreviewTimeline: [ScheduledGoalBlock] = []

    /// Loading state for budget preview.
    @Published var isBudgetPreviewLoading = false

    /// Budget preview error message.
    @Published var budgetPreviewError: String?

    /// Atomic snapshot for the latest budget preview computation.
    @Published var budgetComputationResult: BudgetComputationResult?

    /// User-visible reason when Save is disabled in budget sheet.
    @Published var budgetSaveDisabledReason: String?

    /// One-time migration notice flag (view-level).
    @Published var showBudgetMigrationNotice = false

    /// Prompt for recalculation when goals or month change.
    @Published var showBudgetRecalculationPrompt = false

    /// Whether FX data for budget evaluation is stale or unavailable.
    @Published var budgetHasStaleRates = false

    /// Last successful budget FX refresh time.
    @Published var budgetRateLastUpdated: Date?

    /// Currencies that currently fail conversion into budget currency.
    @Published var budgetRateAffectedCurrencies: [String] = []
    
    // MARK: - Computed Properties
    
    /// Whether there are any flexible goals that can be adjusted
    var hasFlexibleGoals: Bool {
        monthlyRequirements.contains { requirement in
            !protectedGoalIds.contains(requirement.goalId) && 
            !skippedGoalIds.contains(requirement.goalId)
        }
    }
    
    /// Effective plan total in display currency, including persisted flex adjustments.
    var adjustedTotal: Double {
        totalRequired
    }

    /// Number of goals affected by flex adjustment (flexible, non-skipped goals)
    var affectedGoalsCount: Int {
        monthlyRequirements.filter { requirement in
            !protectedGoalIds.contains(requirement.goalId) &&
            !skippedGoalIds.contains(requirement.goalId)
        }.count
    }
    
    /// Summary statistics
    var statistics: PlanningStatistics {
        PlanningStatistics(
            totalGoals: monthlyRequirements.count,
            onTrackCount: monthlyRequirements.filter { $0.status == .onTrack }.count,
            attentionCount: monthlyRequirements.filter { $0.status == .attention }.count,
            criticalCount: monthlyRequirements.filter { $0.status == .critical }.count,
            completedCount: monthlyRequirements.filter { $0.status == .completed }.count,
            averageMonthlyRequired: monthlyRequirements.isEmpty ? 0 : 
                monthlyRequirements.map { $0.requiredMonthly }.reduce(0, +) / Double(monthlyRequirements.count),
            shortestDeadline: monthlyRequirements.map { $0.deadline }.min()
        )
    }

    /// Whether a monthly budget is configured.
    var hasBudget: Bool {
        (settings.monthlyBudget ?? 0) > 0
    }

    /// Current budget amount (0 when not set).
    var budgetAmount: Double {
        settings.monthlyBudget ?? 0
    }

    /// Budget currency (defaults to settings).
    var budgetCurrency: String {
        settings.budgetCurrency
    }

    /// Whether the budget has been applied to the current planning month.
    var isBudgetAppliedForCurrentMonth: Bool {
        settings.budgetAppliedMonthLabel == planningMonthLabel && hasBudget
    }

    /// Current focus goal for budget summary (earliest deadline with remaining amount).
    private var budgetFocusGoal: Goal? {
        guard hasBudget else { return nil }
        let candidates = currentPlans
            .filter { !$0.isSkipped && ($0.customAmount ?? 0) > 0.01 }
            .compactMap { plan in
                goals.first { $0.id == plan.goalId }
            }
        return candidates.min(by: { $0.deadline < $1.deadline })
    }

    /// Current focus goal name for budget summary.
    var budgetFocusGoalName: String? {
        budgetFocusGoal?.name
    }

    /// Current focus goal deadline for budget summary.
    var budgetFocusGoalDeadline: Date? {
        budgetFocusGoal?.deadline
    }

    /// Unified budget state used by Budget Health card.
    var budgetHealthState: BudgetHealthState {
        guard hasBudget else { return .noBudget }

        if budgetHasStaleRates {
            return .staleFX(
                lastUpdated: budgetRateLastUpdated,
                affectedCurrencies: budgetRateAffectedCurrencies
            )
        }

        if budgetComputationResult?.state == .readyFeasible,
           !isBudgetSnapshotFresh {
            return .staleFX(
                lastUpdated: budgetComputationResult?.rateSnapshotTimestamp,
                affectedCurrencies: budgetComputationResult?.affectedCurrencies ?? []
            )
        }

        guard budgetFeasibility.isAvailable else {
            return .needsRecalculation
        }

        let shortfall = max(0, budgetFeasibility.minimumRequired - budgetAmount)
        if shortfall > 0.01 {
            let riskCount = budgetFeasibility.infeasibleGoals.count
            let shortfallRatio = budgetFeasibility.minimumRequired > 0
                ? shortfall / budgetFeasibility.minimumRequired
                : 0
            let goalsRatio = monthlyRequirements.isEmpty
                ? 0
                : Double(riskCount) / Double(max(1, monthlyRequirements.count))
            if shortfallRatio > 0.25 || goalsRatio >= 0.40 {
                return .severeRisk(shortfall: shortfall, goalsAtRisk: riskCount)
            }
            return .atRisk(shortfall: shortfall, goalsAtRisk: riskCount)
        }

        if !isBudgetAppliedForCurrentMonth {
            return .notApplied
        }

        if showBudgetRecalculationPrompt {
            return .needsRecalculation
        }

        return .healthy
    }

    /// Text hint for mixed fiat/crypto conversion basis.
    var budgetConversionContext: String? {
        guard hasBudget else { return nil }
        let sourceCurrencies = Set(monthlyRequirements.map(\.currency).filter { $0 != budgetCurrency })
        guard !sourceCurrencies.isEmpty else { return nil }
        let list = sourceCurrencies.sorted().joined(separator: "/")
        return "Converted from \(list) holdings at current rates."
    }
    
    // MARK: - Dependencies
    
    private let planService: MonthlyPlanService
    private let exchangeRateService: ExchangeRateServiceProtocol
    private let budgetCalculatorService: BudgetCalculatorService
    private let planningMutationService: PlanningMutationServiceProtocol
    private let modelContext: ModelContext
    private var flexService: FlexAdjustmentService?
    private var cancellables = Set<AnyCancellable>()
    private var currentPlans: [MonthlyPlan] = []
    private var isApplyingBudgetMigration = false
    private var latestBudgetPublicationRequestId: UUID?
    private var latestFlexRequestId: UUID?
    private var budgetPreviewTask: Task<Void, Never>?
    private var latestPreviewGoalsSignature: String?
    private var latestPreviewCurrency: String?
    private var latestPreviewRateSnapshotId: String?
    private var latestPreviewPlanningMonthLabel: String?
    private var latestPlanningLoadIdentity: PlanningLoadIdentity?
    private var persistedFlexAdjustment: Double = 1.0
    
    // MARK: - Initialization
    
    convenience init(modelContext: ModelContext, exchangeRateService: ExchangeRateServiceProtocol? = nil) {
        self.init(
            modelContext: modelContext,
            exchangeRateService: exchangeRateService,
            configureObservers: true
        )
    }

    init(
        modelContext: ModelContext,
        planService: MonthlyPlanService? = nil,
        exchangeRateService: ExchangeRateServiceProtocol? = nil,
        budgetCalculatorService: BudgetCalculatorService? = nil,
        planningMutationService: PlanningMutationServiceProtocol? = nil,
        flexService: FlexAdjustmentService? = nil,
        settings: MonthlyPlanningSettings? = nil,
        configureObservers: Bool
    ) {
        let resolvedSettings = settings ?? MonthlyPlanningSettings.shared
        self.modelContext = modelContext
        self.settings = resolvedSettings
        self.planService = planService ?? DIContainer.shared.makeMonthlyPlanService(modelContext: modelContext)
        self.exchangeRateService = exchangeRateService ?? DIContainer.shared.exchangeRateService
        self.budgetCalculatorService = budgetCalculatorService
            ?? BudgetCalculatorService(exchangeRateService: self.exchangeRateService)
        self.planningMutationService = planningMutationService
            ?? DIContainer.shared.makePlanningMutationService(modelContext: modelContext)
        self.flexService = flexService ?? DIContainer.shared.makeFlexAdjustmentService(modelContext: modelContext)
        self.planningMonthLabel = self.planService.currentMonthLabel()
        
        // Initialize display currency from settings
        self.displayCurrency = resolvedSettings.displayCurrency
        
        if configureObservers {
            setupObservers()
            loadUserPreferences()
            setupSettingsObservation()
        }
    }
    
    // MARK: - Public Methods
    
    /// Load monthly requirements for all active goals in the selected planning month
    func loadMonthlyRequirements(for monthLabel: String? = nil) async {
        latestFlexRequestId = nil
        let targetMonthLabel = resolvePlanningMonthLabel(preferred: monthLabel)
        let loadIdentity = PlanningLoadIdentity(
            requestID: UUID(),
            monthLabel: targetMonthLabel,
            displayCurrency: displayCurrency
        )
        latestPlanningLoadIdentity = loadIdentity
        invalidateBudgetPreviewForInputChange()
        planningMonthLabel = targetMonthLabel
        isLoading = true
        error = nil
        
        do {
            // Fetch all active goals
            let descriptor = FetchDescriptor<Goal>(
                predicate: #Predicate { goal in
                    goal.lifecycleStatusRawValue == "active"
                },
                sortBy: [SortDescriptor(\.deadline, order: .forward)]
            )
            
            let goals = try modelContext.fetch(descriptor)
            let activeGoalIDs = Set(goals.map(\.id))
            for _ in goals {
            }

            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            let hasActiveExecution = (try? executionService.getActiveRecord()) != nil
            #if DEBUG
            let shouldSkipDraftRollForward = UITestFlags.shouldSeedStaleDrafts
            #else
            let shouldSkipDraftRollForward = false
            #endif
            if !hasActiveExecution && !shouldSkipDraftRollForward {
                _ = try await planService.rollForwardDraftPlans(to: targetMonthLabel)
            }

            // Get or create persisted plans for the selected month
            let candidatePlans = try await planService.getOrCreatePlans(
                for: targetMonthLabel,
                goals: goals
            )
            let plans = candidatePlans.filter { activeGoalIDs.contains($0.goalId) }

            // Map plans to MonthlyRequirement adapters for UI compatibility
            let requirements = goals.compactMap { goal -> MonthlyRequirement? in
                guard let plan = plans.first(where: { $0.goalId == goal.id }) else { return nil }
                return requirement(from: plan, goal: goal)
            }

            let total = try await calculateTotalRequired(
                from: plans,
                displayCurrency: loadIdentity.displayCurrency
            )
            let latestActiveGoalIDs = Set(try modelContext.fetch(descriptor).map(\.id))
            guard latestActiveGoalIDs == activeGoalIDs else {
                throw PlanError.sourceDataChanged(
                    "Active goals changed while the planning summary was being calculated. Retry with current goals."
                )
            }
            guard isCurrentPlanningLoad(loadIdentity) else { return }

            // Publish atomically on this @MainActor after the final membership check.
            self.currentPlans = plans
            self.goals = goals
            self.monthlyRequirements = requirements
            self.totalRequired = total
            self.totalRequiredIsPartial = false
            self.isLoading = false
            // Refresh flex state sets from plan data
            self.protectedGoalIds = Set(
                plans
                    .filter { $0.flexState == .protected || $0.isProtected }
                    .map(\.goalId)
            )
            self.skippedGoalIds = Set(
                plans
                    .filter { $0.flexState == .skipped || $0.isSkipped }
                    .map(\.goalId)
            )

            await refreshBudgetStatus(expectedLoad: loadIdentity)
            guard isCurrentPlanningLoad(loadIdentity) else { return }
            await handleBudgetMigrationIfNeeded(
                goals: goals,
                expectedLoad: loadIdentity
            )
            
        } catch {
            guard isCurrentPlanningLoad(loadIdentity) else { return }
            self.invalidateFinancialStateAfterLoadFailure(error)
            AppLog.error(
                "Failed to load monthly requirements: \(error.localizedDescription)",
                category: .monthlyPlanning
            )
        }
    }
    
    /// Refresh calculations (force cache clear)
    func refreshCalculations() async {
        await loadMonthlyRequirements()
    }

    /// Whether the current preview belongs to the supplied canonical budget input.
    func isBudgetSnapshotCurrent(for amount: MoneyAmount) -> Bool {
        guard let snapshot = budgetComputationResult else { return false }
        guard latestPreviewPlanningMonthLabel == planningMonthLabel else {
            return false
        }
        guard !currentPlans.isEmpty,
              currentPlans.allSatisfy({
                  $0.monthLabel == planningMonthLabel
              })
        else {
            return false
        }
        guard amount.currency == snapshot.enteredBudgetCanonical.currency else { return false }
        return MoneyQuantizer.compare(amount, snapshot.enteredBudgetCanonical) == .orderedSame
    }

    /// Invalidates financial preview state before an input dimension changes.
    func invalidateBudgetPreviewForInputChange() {
        budgetPreviewTask?.cancel()
        latestBudgetPublicationRequestId = nil
        budgetComputationResult = nil
        budgetPreviewPlan = nil
        budgetPreviewTimeline = []
        budgetFeasibility = .empty
        budgetSaveDisabledReason = "Calculating latest amount..."
        budgetPreviewError = nil
        isBudgetPreviewLoading = false
        latestPreviewRateSnapshotId = nil
        latestPreviewGoalsSignature = nil
        latestPreviewCurrency = nil
        latestPreviewPlanningMonthLabel = nil
    }

    var isBudgetSnapshotFresh: Bool {
        guard let snapshot = budgetComputationResult,
              snapshot.state == .readyFeasible else {
            return false
        }
        return budgetCalculatorService.isRateSnapshotFresh(
            timestamp: snapshot.rateSnapshotTimestamp
        )
    }

    // MARK: - Budget Calculator

    /// Prepare preview data for the budget calculator sheet.
    func previewBudget(amount: Double, currency: String, forceRateRefresh: Bool = false) async {
        let canonical = MoneyQuantizer.normalize(Decimal(max(0, amount)), currency: currency, mode: .halfUp)
        await previewBudget(
            amount: canonical,
            currency: currency,
            forceRateRefresh: forceRateRefresh
        )
    }

    /// Prepare preview data for the budget calculator sheet with canonical money type.
    func previewBudget(amount: MoneyAmount, currency: String, forceRateRefresh: Bool = false) async {
        let eligibleGoals = budgetEligibleGoals()

        if forceRateRefresh {
            budgetCalculatorService.invalidateRateSnapshots()
            latestPreviewRateSnapshotId = nil
        }

        guard amount.minorUnitValue > 0, !eligibleGoals.isEmpty else {
            invalidateBudgetPreviewForInputChange()
            budgetSaveDisabledReason = "Enter a valid amount."
            return
        }

        let goalsSignature = budgetSignature(for: eligibleGoals)
        if latestPreviewGoalsSignature != goalsSignature || latestPreviewCurrency != amount.currency {
            latestPreviewRateSnapshotId = nil
        }
        latestPreviewGoalsSignature = goalsSignature
        latestPreviewCurrency = amount.currency

        let requestId = UUID()
        let requestedPlanningMonthLabel = planningMonthLabel
        latestBudgetPublicationRequestId = requestId
        budgetPreviewTask?.cancel()
        isBudgetPreviewLoading = true
        budgetPreviewError = nil
        budgetSaveDisabledReason = "Calculating latest amount..."

        let rateSnapshotId = latestPreviewRateSnapshotId
        budgetPreviewTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let result = await self.budgetCalculatorService.computeBudgetSnapshot(
                requestId: requestId,
                goals: eligibleGoals,
                enteredBudget: amount,
                goalsSignature: goalsSignature,
                rateSnapshotId: rateSnapshotId,
                planningMonthLabel: requestedPlanningMonthLabel
            )

            await MainActor.run {
                guard self.latestBudgetPublicationRequestId
                        == result.requestId,
                      self.planningMonthLabel
                        == requestedPlanningMonthLabel
                else {
                    BudgetPlanAnalytics.log(.snapshotStaleResultDropped)
                    return
                }

                self.applyBudgetSnapshot(
                    result,
                    planningMonthLabel: requestedPlanningMonthLabel
                )
            }
        }
    }

    private func applyBudgetSnapshot(
        _ result: BudgetComputationResult,
        planningMonthLabel: String
    ) {
        budgetComputationResult = result
        latestPreviewPlanningMonthLabel = planningMonthLabel
        latestPreviewRateSnapshotId = result.rateSnapshotId
        budgetPreviewPlan = result.plan
        budgetPreviewTimeline = result.timeline
        budgetFeasibility = FeasibilityResult(
            isFeasible: result.isFeasible,
            minimumRequired: result.minimumRequiredCanonical.doubleValue,
            currency: result.minimumRequiredCanonical.currency,
            infeasibleGoals: result.infeasibleGoals,
            suggestions: result.suggestions,
            isAvailable: result.state != .blockedRates && result.state != .blockedBalances
        )
        budgetRateLastUpdated = result.rateSnapshotTimestamp
        budgetRateAffectedCurrencies = result.affectedCurrencies
        budgetHasStaleRates = result.state == .blockedRates
            || (
                result.state == .readyFeasible
                    && !budgetCalculatorService.isRateSnapshotFresh(timestamp: result.rateSnapshotTimestamp)
            )
        isBudgetPreviewLoading = false

        switch result.state {
        case .readyFeasible:
            budgetSaveDisabledReason = nil
        case .blockedInfeasible:
            if MoneyQuantizer.compare(result.enteredBudgetCanonical, result.minimumRequiredCanonical) == .orderedSame {
                BudgetPlanAnalytics.log(.displayValidationMismatchDetected, properties: [
                    "currency": result.enteredBudgetCanonical.currency
                ])
            }
            let shortfallText = CurrencyFormatter.format(amount: result.shortfallCanonical)
            budgetSaveDisabledReason = "Short by \(shortfallText). Tap Use Minimum or increase budget."
            BudgetPlanAnalytics.log(.saveBlockedReasonShown, properties: ["reason": "blocked_infeasible"])
        case .blockedRates:
            budgetSaveDisabledReason = "Rates unavailable for conversion. Refresh rates to validate this budget."
            BudgetPlanAnalytics.log(.saveBlockedReasonShown, properties: ["reason": "blocked_rates"])
        case .blockedBalances:
            budgetSaveDisabledReason = "Balances unavailable. Refresh balances to validate this budget."
            BudgetPlanAnalytics.log(.saveBlockedReasonShown, properties: ["reason": "blocked_balances"])
        }
    }

    /// Apply a feasibility suggestion that modifies goals and refreshes the preview.
    func applyFeasibilitySuggestion(
        _ suggestion: FeasibilitySuggestion,
        currentBudget: Double,
        currency: String
    ) async -> Bool {
        switch suggestion {
        case .increaseBudget:
            return false
        case .editGoal:
            return false
        case .extendDeadline, .reduceTarget:
            break
        }

        do {
            let didApply = try planningMutationService.applyFeasibilitySuggestion(suggestion, goals: goals)
            guard didApply else { return false }
        } catch {
            self.error = error
            return false
        }

        await loadMonthlyRequirements(for: planningMonthLabel)
        if currentBudget > 0 {
            await previewBudget(amount: currentBudget, currency: currency)
        }
        return true
    }

    func hasCustomAmount(for goalId: UUID) -> Bool {
        currentPlans.first(where: { $0.goalId == goalId })?.customAmount != nil
    }

    /// Apply the budget calculator results to the current month's plans.
    func applyBudgetPlan(
        plan: BudgetCalculatorPlan,
        amount: Double,
        currency: String
    ) async -> Bool {
        let appliedMonthLabel = planningMonthLabel
        let plansToApply = currentPlans
        guard !plansToApply.isEmpty else { return false }
        guard plansToApply.allSatisfy({
            $0.monthLabel == appliedMonthLabel
        }) else {
            budgetSaveDisabledReason = "Planning month changed. Refresh the preview and retry."
            return false
        }
        let canonicalAmount = MoneyQuantizer.normalize(
            Decimal(max(0, amount)),
            currency: currency,
            mode: .halfUp
        )
        guard let snapshot = budgetComputationResult,
              snapshot.state == .readyFeasible,
              snapshot.plan == plan,
              plan.currency.uppercased() == currency.uppercased(),
              isBudgetSnapshotCurrent(for: canonicalAmount),
              isBudgetSnapshotFresh else {
            budgetSaveDisabledReason = "Preview expired or no longer matches this budget. Refresh and retry."
            return false
        }
        let appliedPaymentDay = settings.paymentDay
        let applyIdentity = BudgetApplyIdentity(
            requestID: snapshot.requestId,
            monthLabel: appliedMonthLabel,
            amount: canonicalAmount,
            currency: currency.uppercased(),
            plan: plan,
            monthlyPlanIDs: Set(plansToApply.map(\.id)),
            paymentDay: appliedPaymentDay
        )
        guard isBudgetApplyIdentityCurrent(applyIdentity) else {
            budgetSaveDisabledReason = "Budget inputs changed. Refresh the preview and retry."
            return false
        }

        do {
            try await planningMutationService.applyBudgetPlan(
                plan,
                currentPlans: plansToApply,
                budgetCurrency: applyIdentity.currency,
                validateBeforeCommit: { [weak self] in
                    self?.isBudgetApplyIdentityCurrent(applyIdentity) == true
                }
            )
        } catch {
            budgetPreviewError = error.localizedDescription
            return false
        }

        guard isBudgetApplyIdentityCurrent(applyIdentity) else {
            budgetSaveDisabledReason = "Budget inputs changed. Refresh the preview and retry."
            return false
        }
        let appliedSignature = appliedBudgetSignature(
            amount: canonicalAmount,
            plan: plan,
            monthlyPlans: plansToApply,
            paymentDay: appliedPaymentDay
        )
        settings.monthlyBudget = canonicalAmount.doubleValue
        settings.budgetCurrency = applyIdentity.currency
        settings.budgetAppliedMonthLabel = appliedMonthLabel
        settings.budgetAppliedSignature = appliedSignature

        flexAdjustment = 1.0
        persistedFlexAdjustment = 1.0
        saveUserPreferences()

        await loadMonthlyRequirements()
        return true
    }

    private func isBudgetApplyIdentityCurrent(
        _ identity: BudgetApplyIdentity
    ) -> Bool {
        guard latestBudgetPublicationRequestId == identity.requestID,
              latestPreviewPlanningMonthLabel == identity.monthLabel,
              planningMonthLabel == identity.monthLabel,
              latestPreviewCurrency?.uppercased() == identity.currency,
              settings.paymentDay == identity.paymentDay,
              let snapshot = budgetComputationResult,
              snapshot.requestId == identity.requestID,
              snapshot.state == .readyFeasible,
              snapshot.plan == identity.plan,
              snapshot.enteredBudgetCanonical == identity.amount,
              budgetPreviewPlan == identity.plan,
              Set(currentPlans.map(\.id)) == identity.monthlyPlanIDs,
              currentPlans.allSatisfy({
                  $0.monthLabel == identity.monthLabel
              }),
              isBudgetSnapshotCurrent(for: identity.amount),
              isBudgetSnapshotFresh else {
            return false
        }
        return true
    }

    /// Dismiss the one-time migration notice.
    func dismissBudgetMigrationNotice() {
        settings.hasSeenBudgetMigrationNotice = true
        showBudgetMigrationNotice = false
    }

    /// Mark the recalculation prompt as acknowledged for the current inputs.
    func acknowledgeBudgetRecalculationPrompt() {
        let canonicalAmount = MoneyQuantizer.normalize(
            Decimal(max(0, settings.monthlyBudget ?? 0)),
            currency: settings.budgetCurrency,
            mode: .halfUp
        )
        guard let result = budgetComputationResult,
              let signature = appliedBudgetSignature(
                amount: canonicalAmount,
                plan: result.plan
              ) else {
            showBudgetRecalculationPrompt = true
            return
        }
        settings.budgetAppliedMonthLabel = planningMonthLabel
        settings.budgetAppliedSignature = signature
        showBudgetRecalculationPrompt = false
    }

    /// Apply flex adjustment to persisted plans and refresh UI
    func applyFlexAdjustment(_ percentage: Double) async {
        let clamped = max(0.0, min(1.5, percentage))
        _ = await persistFlexConfiguration(
            adjustment: clamped,
            protectedGoalIds: protectedGoalIds,
            skippedGoalIds: skippedGoalIds
        )
    }
    
    /// Toggle protection status for a goal
    func toggleProtection(for goalId: UUID) async {
        var nextProtectedGoalIds = protectedGoalIds
        var nextSkippedGoalIds = skippedGoalIds
        if nextProtectedGoalIds.contains(goalId) {
            nextProtectedGoalIds.remove(goalId)
        } else {
            nextProtectedGoalIds.insert(goalId)
            nextSkippedGoalIds.remove(goalId) // Can't be both protected and skipped
        }
        _ = await persistFlexConfiguration(
            adjustment: flexAdjustment,
            protectedGoalIds: nextProtectedGoalIds,
            skippedGoalIds: nextSkippedGoalIds
        )
    }
    
    /// Toggle skip status for a goal
    func toggleSkip(for goalId: UUID) async {
        var nextProtectedGoalIds = protectedGoalIds
        var nextSkippedGoalIds = skippedGoalIds
        if nextSkippedGoalIds.contains(goalId) {
            nextSkippedGoalIds.remove(goalId)
        } else {
            nextSkippedGoalIds.insert(goalId)
            nextProtectedGoalIds.remove(goalId) // Can't be both skipped and protected
        }
        _ = await persistFlexConfiguration(
            adjustment: flexAdjustment,
            protectedGoalIds: nextProtectedGoalIds,
            skippedGoalIds: nextSkippedGoalIds
        )
    }

    /// Set a custom amount for a specific goal
    /// - Parameters:
    ///   - goalId: The goal to set custom amount for
    ///   - amount: The custom amount (nil to clear)
    func setCustomAmount(for goalId: UUID, amount: Double?) {
        guard let plan = currentPlans.first(where: { $0.goalId == goalId }) else {
            AppLog.warning("No plan found for goal \(goalId)", category: .monthlyPlanning)
            return
        }

        // Set the custom amount directly on the plan
        do {
            try planService.setCustomAmount(amount, for: plan)

            // If setting a custom amount, auto-protect this goal
            if amount != nil {
                protectedGoalIds.insert(goalId)
                skippedGoalIds.remove(goalId)
            } else {
                protectedGoalIds.remove(goalId)
            }

            saveUserPreferences()

            // Refresh the adjusted amounts display
            Task {
                await loadMonthlyRequirements(for: planningMonthLabel)
                await refreshBudgetStatus()
            }

            AppLog.info("Set custom amount \(amount ?? 0) for goal \(goalId)", category: .monthlyPlanning)
        } catch {
            AppLog.error(
                "Failed to set custom amount: \(error.localizedDescription)",
                category: .monthlyPlanning
            )
        }
    }

    /// Get the current effective amount for a goal (custom amount or calculated)
    func getEffectiveAmount(for goalId: UUID) -> Double? {
        guard let plan = currentPlans.first(where: { $0.goalId == goalId }) else { return nil }
        return plan.effectiveAmount
    }

    /// Get the required monthly amount for a goal (before any adjustments)
    func getRequiredAmount(for goalId: UUID) -> Double? {
        return monthlyRequirements.first(where: { $0.goalId == goalId })?.requiredMonthly
    }

    /// Apply quick action
    func applyQuickAction(_ action: QuickAction) async {
        var nextProtectedGoalIds = protectedGoalIds
        var nextSkippedGoalIds = skippedGoalIds
        var nextAdjustment = flexAdjustment
        var clearFlexibleOverrides = false

        switch action {
        case .skipMonth:
            // Skip all flexible goals this month
            for requirement in monthlyRequirements {
                if !nextProtectedGoalIds.contains(requirement.goalId) {
                    nextSkippedGoalIds.insert(requirement.goalId)
                }
            }
            
        case .payHalf:
            // Pay 50% of required amounts
            nextSkippedGoalIds.removeAll()
            nextAdjustment = 0.5
            
        case .payExact:
            // Pay exact calculated amounts
            nextSkippedGoalIds.removeAll()
            nextAdjustment = 1.0

        case .reset:
            // Reset all adjustments
            nextProtectedGoalIds.removeAll()
            nextSkippedGoalIds.removeAll()
            nextAdjustment = 1.0
            clearFlexibleOverrides = true
        }

        _ = await persistFlexConfiguration(
            adjustment: nextAdjustment,
            protectedGoalIds: nextProtectedGoalIds,
            skippedGoalIds: nextSkippedGoalIds,
            clearFlexibleOverrides: clearFlexibleOverrides
        )
    }

    /// Persists one canonical flex state before publishing it to the view model
    /// or UserDefaults. A failed save therefore leaves all three layers aligned.
    @discardableResult
    private func persistFlexConfiguration(
        adjustment: Double,
        protectedGoalIds nextProtectedGoalIds: Set<UUID>,
        skippedGoalIds nextSkippedGoalIds: Set<UUID>,
        clearFlexibleOverrides: Bool = false
    ) async -> Bool {
        if currentPlans.isEmpty {
            await loadMonthlyRequirements(for: planningMonthLabel)
        }
        guard !currentPlans.isEmpty else { return false }
        let requestId = UUID()
        latestFlexRequestId = requestId
        let requestCurrency = displayCurrency
        let requestMonth = planningMonthLabel
        let plans = currentPlans

        do {
            try await planService.applyBulkFlexAdjustment(
                plans: plans,
                adjustment: adjustment,
                protectedGoalIds: nextProtectedGoalIds,
                skippedGoalIds: nextSkippedGoalIds,
                clearFlexibleOverrides: clearFlexibleOverrides
            )
        } catch {
            guard latestFlexRequestId == requestId else { return false }
            self.error = error
            flexAdjustment = persistedFlexAdjustment
            AppLog.error(
                "Failed to persist flex adjustment: \(error.localizedDescription)",
                category: .monthlyPlanning
            )
            return false
        }
        guard latestFlexRequestId == requestId else { return true }

        protectedGoalIds = nextProtectedGoalIds
        skippedGoalIds = nextSkippedGoalIds
        flexAdjustment = adjustment
        persistedFlexAdjustment = adjustment
        saveUserPreferences()
        error = nil

        let requirements = goals.compactMap { goal -> MonthlyRequirement? in
            guard let plan = plans.first(where: { $0.goalId == goal.id }) else { return nil }
            return requirement(from: plan, goal: goal)
        }

        do {
            let total = try await calculateTotalRequired(
                from: plans,
                displayCurrency: requestCurrency
            )
            guard latestFlexRequestId == requestId,
                  displayCurrency == requestCurrency,
                  planningMonthLabel == requestMonth else { return true }
            monthlyRequirements = requirements
            totalRequired = total
            totalRequiredIsPartial = false
        } catch {
            guard latestFlexRequestId == requestId,
                  displayCurrency == requestCurrency,
                  planningMonthLabel == requestMonth else { return true }
            totalRequired = 0
            totalRequiredIsPartial = true
            self.error = error
            AppLog.error(
                "Flex state was saved, but its converted total is unavailable: \(error.localizedDescription)",
                category: .monthlyPlanning
            )
        }

        await refreshBudgetStatus()
        return true
    }
    
    /// Get flex state for a specific goal
    func getFlexState(for goalId: UUID) -> MonthlyPlan.FlexState {
        if skippedGoalIds.contains(goalId) {
            return .skipped
        } else if protectedGoalIds.contains(goalId) {
            return .protected
        } else {
            return .flexible
        }
    }
    
    /// Update display currency
    func updateDisplayCurrency(_ currency: String) async {
        settings.displayCurrency = currency
        displayCurrency = currency
        await loadMonthlyRequirements()
    }
    
    // MARK: - Private Methods
    
    /// Setup Combine observers for reactive updates
    private func setupObservers() {
        // Observe goal changes
        NotificationCenter.default.publisher(for: .monthlyPlanningGoalUpdated)
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadMonthlyRequirements()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .monthlyPlanningGoalDeleted)
            .sink { [weak self] notification in
                guard let goal = notification.object as? Goal else { return }
                self?.protectedGoalIds.remove(goal.id)
                self?.skippedGoalIds.remove(goal.id)
                self?.saveUserPreferences()
                
                Task { [weak self] in
                    await self?.loadMonthlyRequirements()
                }
            }
            .store(in: &cancellables)
        
        // Observe asset changes
        NotificationCenter.default.publisher(for: .monthlyPlanningAssetUpdated)
            .debounce(for: .seconds(1.0), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.handlePlanningAssetUpdate()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .monthlyExecutionCompleted)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadMonthlyRequirements()
                }
            }
            .store(in: &cancellables)
    }

    func handlePlanningAssetUpdate() async {
        await loadMonthlyRequirements(for: planningMonthLabel)
    }
    
    /// Setup observation of settings changes
    private func setupSettingsObservation() {
        // Observe currency changes
        settings.$displayCurrency
            .receive(on: RunLoop.main)
            .sink { [weak self] newCurrency in
                self?.displayCurrency = newCurrency
                Task { [weak self] in
                    await self?.loadMonthlyRequirements()
                }
            }
            .store(in: &cancellables)
        
        // Observe payment day changes
        settings.$paymentDay
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.loadMonthlyRequirements()
                }
            }
            .store(in: &cancellables)

        // Observe budget changes
        settings.$monthlyBudget
            .dropFirst()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.refreshBudgetStatus()
                }
            }
            .store(in: &cancellables)

        settings.$budgetCurrency
            .dropFirst()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.refreshBudgetStatus()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshBudgetStatus(
        expectedLoad: PlanningLoadIdentity? = nil
    ) async {
        if let expectedLoad,
           !isCurrentPlanningLoad(expectedLoad) {
            return
        }
        guard hasBudget else {
            budgetPreviewTask?.cancel()
            budgetFeasibility = .empty
            budgetComputationResult = nil
            budgetPreviewPlan = nil
            budgetPreviewTimeline = []
            budgetSaveDisabledReason = nil
            latestPreviewRateSnapshotId = nil
            latestPreviewGoalsSignature = nil
            latestPreviewCurrency = nil
            latestPreviewPlanningMonthLabel = nil
            latestBudgetPublicationRequestId = nil
            showBudgetRecalculationPrompt = false
            budgetHasStaleRates = false
            budgetRateLastUpdated = nil
            budgetRateAffectedCurrencies = []
            return
        }

        let eligibleGoals = budgetEligibleGoals()
        guard !eligibleGoals.isEmpty else {
            budgetPreviewTask?.cancel()
            budgetFeasibility = .empty
            budgetComputationResult = nil
            budgetPreviewPlan = nil
            budgetPreviewTimeline = []
            budgetSaveDisabledReason = nil
            latestPreviewRateSnapshotId = nil
            latestPreviewGoalsSignature = nil
            latestPreviewCurrency = nil
            latestPreviewPlanningMonthLabel = nil
            latestBudgetPublicationRequestId = nil
            budgetHasStaleRates = false
            budgetRateLastUpdated = nil
            budgetRateAffectedCurrencies = []
            return
        }

        let budget = settings.monthlyBudget ?? 0
        let currency = settings.budgetCurrency
        let canonicalBudget = MoneyQuantizer.normalize(
            Decimal(max(0, budget)),
            currency: currency,
            mode: .halfUp
        )
        let goalsSignature = budgetSignature(for: eligibleGoals)
        let requestId = UUID()
        let requestedPlanningMonthLabel = planningMonthLabel
        latestBudgetPublicationRequestId = requestId
        budgetPreviewTask?.cancel()
        let result = await budgetCalculatorService.computeBudgetSnapshot(
            requestId: requestId,
            goals: eligibleGoals,
            enteredBudget: canonicalBudget,
            goalsSignature: goalsSignature,
            rateSnapshotId: nil,
            planningMonthLabel: requestedPlanningMonthLabel
        )
        guard latestBudgetPublicationRequestId == requestId,
              planningMonthLabel == requestedPlanningMonthLabel
        else {
            return
        }
        if let expectedLoad,
           !isCurrentPlanningLoad(expectedLoad) {
            return
        }

        applyBudgetSnapshot(
            result,
            planningMonthLabel: requestedPlanningMonthLabel
        )
        budgetPreviewError = budgetCalculatorService.lastError?.localizedDescription

        guard settings.budgetAppliedMonthLabel != nil else {
            showBudgetRecalculationPrompt = false
            return
        }

        if settings.budgetAppliedMonthLabel != planningMonthLabel {
            showBudgetRecalculationPrompt = true
        } else {
            let currentAppliedSignature = appliedBudgetSignature(
                amount: canonicalBudget,
                plan: result.plan
            )
            showBudgetRecalculationPrompt =
                currentAppliedSignature == nil
                || settings.budgetAppliedSignature != currentAppliedSignature
        }
    }

    private func handleBudgetMigrationIfNeeded(
        goals: [Goal],
        expectedLoad: PlanningLoadIdentity
    ) async {
        guard isCurrentPlanningLoad(expectedLoad) else { return }
        guard hasBudget, settings.budgetAppliedMonthLabel == nil else { return }
        guard !isApplyingBudgetMigration else { return }
        let eligibleGoals = budgetEligibleGoals(from: goals)
        guard !eligibleGoals.isEmpty else { return }

        isApplyingBudgetMigration = true
        defer { isApplyingBudgetMigration = false }

        let budget = settings.monthlyBudget ?? 0
        let currency = settings.budgetCurrency
        let canonicalBudget = MoneyQuantizer.normalize(
            Decimal(max(0, budget)),
            currency: currency,
            mode: .halfUp
        )
        if !isBudgetSnapshotCurrent(for: canonicalBudget) || !isBudgetSnapshotFresh {
            await refreshBudgetStatus(expectedLoad: expectedLoad)
        }
        guard isCurrentPlanningLoad(expectedLoad) else { return }
        guard let result = budgetComputationResult,
              result.state == .readyFeasible,
              let plan = result.plan,
              isBudgetSnapshotCurrent(for: canonicalBudget),
              isBudgetSnapshotFresh else {
            budgetPreviewError = budgetCalculatorService.lastError?.localizedDescription
            return
        }

        let applied = await applyBudgetPlan(plan: plan, amount: budget, currency: currency)
        if applied, !settings.hasSeenBudgetMigrationNotice {
            showBudgetMigrationNotice = true
        }
    }

    private func budgetEligibleGoals(from goals: [Goal]? = nil) -> [Goal] {
        let source = goals ?? self.goals
        let skipped = skippedGoalIds
        return source.filter { goal in
            goal.lifecycleStatus == .active && !skipped.contains(goal.id)
        }
    }

    private func budgetSignature(for goals: [Goal]) -> String {
        BudgetSnapshotIdentity.goalsSignature(goals: goals, skippedGoalIds: skippedGoalIds)
    }

    private func appliedBudgetSignature(
        amount: MoneyAmount,
        plan: BudgetCalculatorPlan?,
        monthlyPlans: [MonthlyPlan]? = nil,
        paymentDay: Int? = nil
    ) -> String? {
        guard let plan,
              let sourceStateSignature = plan.sourceStateSignature,
              !sourceStateSignature.isEmpty else {
            return nil
        }
        return BudgetSnapshotIdentity.appliedBudgetSignature(
            amount: amount,
            sourceStateSignature: sourceStateSignature,
            monthlyPlans: monthlyPlans ?? currentPlans,
            paymentDay: paymentDay ?? settings.paymentDay,
            budgetPlan: plan
        )
    }

    /// Load saved flex states from SwiftData
    private func loadFlexStates() async {
        do {
            let descriptor = FetchDescriptor<MonthlyPlan>()
            let plans = try modelContext.fetch(descriptor)
            
            for plan in plans {
                switch plan.flexState {
                case .protected:
                    protectedGoalIds.insert(plan.goalId)
                case .skipped:
                    skippedGoalIds.insert(plan.goalId)
                case .flexible:
                    break
                }
            }
        } catch {
            AppLog.warning(
                "Failed to load flex states: \(error.localizedDescription)",
                category: .monthlyPlanning
            )
        }
    }

    /// Save user preferences to UserDefaults
    private func saveUserPreferences() {
        // Display currency is now managed by settings
        UserDefaults.standard.set(
            protectedGoalIds.map(\.uuidString).sorted(),
            forKey: "MonthlyPlanning.ProtectedGoals"
        )
        UserDefaults.standard.set(
            skippedGoalIds.map(\.uuidString).sorted(),
            forKey: "MonthlyPlanning.SkippedGoals"
        )
        UserDefaults.standard.set(flexAdjustment, forKey: "MonthlyPlanning.FlexAdjustment")
    }
    
    /// Load user preferences from UserDefaults
    private func loadUserPreferences() {
        // Display currency is now managed by settings
        
        if let protectedStrings = UserDefaults.standard.stringArray(forKey: "MonthlyPlanning.ProtectedGoals") {
            protectedGoalIds = Set(protectedStrings.compactMap { UUID(uuidString: $0) })
        }
        
        if let skippedStrings = UserDefaults.standard.stringArray(forKey: "MonthlyPlanning.SkippedGoals") {
            skippedGoalIds = Set(skippedStrings.compactMap { UUID(uuidString: $0) })
        }
        
        let savedAdjustment = UserDefaults.standard.double(forKey: "MonthlyPlanning.FlexAdjustment")
        if savedAdjustment > 0 {
            flexAdjustment = savedAdjustment
            persistedFlexAdjustment = savedAdjustment
        } else {
            flexAdjustment = 1.0
            persistedFlexAdjustment = 1.0
        }
    }

    /// Adapter: convert a persisted MonthlyPlan into a MonthlyRequirement for UI reuse
    private func requirement(from plan: MonthlyPlan, goal: Goal) -> MonthlyRequirement {
        let required = plan.requiredMonthly
        let remaining = plan.remainingAmount
        let currentTotal = max(goal.targetAmount - remaining, 0)
        let progress = goal.targetAmount > 0 ? min(currentTotal / goal.targetAmount, 1.0) : 0.0

        return MonthlyRequirement(
            goalId: plan.goalId,
            goalName: goal.name,
            currency: plan.currency,
            targetAmount: goal.targetAmount,
            currentTotal: currentTotal,
            remainingAmount: remaining,
            monthsRemaining: plan.monthsRemaining,
            requiredMonthly: required,
            progress: progress,
            deadline: goal.deadline,
            status: plan.status
        )
    }

    private func resolvePlanningMonthLabel(preferred: String?) -> String {
        if let preferred, !preferred.isEmpty {
            return preferred
        }

        let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
        if let record = try? executionService.getCurrentMonthRecord(), record.status == .closed {
            if let nextMonth = nextMonthLabel(from: record.monthLabel) {
                return nextMonth
            }
        }

        let currentMonth = planService.currentMonthLabel()
        if planningMonthLabel.isEmpty {
            return currentMonth
        }
        if planningMonthLabel < currentMonth {
            return currentMonth
        }
        return planningMonthLabel
    }

    private func nextMonthLabel(from monthLabel: String) -> String? {
        try? PlanningMonthContract.nextLabel(after: monthLabel)
    }

    /// Calculate total required using plan effective amounts with currency conversion
    private func calculateTotalRequired(
        from plans: [MonthlyPlan],
        displayCurrency: String
    ) async throws -> Double {
        let targetCurrency = displayCurrency.uppercased()
        let sourceCurrencies = Set(
            plans
                .map { $0.currency.uppercased() }
                .filter { $0 != targetCurrency }
        )
        var ratesBySource: [String: Double] = [:]

        for sourceCurrency in sourceCurrencies.sorted() {
            do {
                ratesBySource[sourceCurrency] = try await exchangeRateService.fetchRate(
                    from: sourceCurrency,
                    to: targetCurrency
                )
            } catch {
                if error is CancellationError {
                    throw error
                }
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    throw error
                }
                AppLog.warning(
                    "Failed to convert \(sourceCurrency) to \(targetCurrency): \(error.localizedDescription)",
                    category: .monthlyPlanning
                )
                throw MonthlyPlanningError.currencyConversionFailed(
                    "\(sourceCurrency) to \(targetCurrency)"
                )
            }
        }

        return plans.reduce(into: 0.0) { total, plan in
            let sourceCurrency = plan.currency.uppercased()
            if sourceCurrency == targetCurrency {
                total += plan.effectiveAmount
            } else if let rate = ratesBySource[sourceCurrency] {
                total += plan.effectiveAmount * rate
            }
        }
    }

    private func invalidateFinancialStateAfterLoadFailure(_ loadError: Error) {
        budgetPreviewTask?.cancel()
        latestBudgetPublicationRequestId = nil
        currentPlans = []
        monthlyRequirements = []
        totalRequired = 0
        totalRequiredIsPartial = true
        budgetFeasibility = .unavailable(currency: budgetCurrency)
        budgetComputationResult = nil
        budgetPreviewPlan = nil
        budgetPreviewTimeline = []
        budgetSaveDisabledReason = "Planning data is unavailable. Refresh and retry."
        budgetPreviewError = loadError.localizedDescription
        budgetRateLastUpdated = nil
        budgetRateAffectedCurrencies = []
        budgetHasStaleRates = false
        showBudgetRecalculationPrompt = hasBudget
        latestPreviewRateSnapshotId = nil
        latestPreviewGoalsSignature = nil
        latestPreviewCurrency = nil
        latestPreviewPlanningMonthLabel = nil
        error = loadError
        isLoading = false
    }

    private func isCurrentPlanningLoad(
        _ identity: PlanningLoadIdentity
    ) -> Bool {
        latestPlanningLoadIdentity == identity
            && planningMonthLabel == identity.monthLabel
            && displayCurrency == identity.displayCurrency
    }
}

// MARK: - Supporting Types

// QuickAction is now defined in Models/QuickAction.swift

/// Planning statistics
struct PlanningStatistics {
    let totalGoals: Int
    let onTrackCount: Int
    let attentionCount: Int
    let criticalCount: Int
    let completedCount: Int
    let averageMonthlyRequired: Double
    let shortestDeadline: Date?
    
    var statusSummary: String {
        if criticalCount > 0 {
            return "\(criticalCount) critical goal\(criticalCount == 1 ? "" : "s") need immediate attention"
        } else if attentionCount > 0 {
            return "\(attentionCount) goal\(attentionCount == 1 ? "" : "s") need attention"
        } else if onTrackCount == totalGoals {
            return "All goals on track"
        } else {
            return "\(onTrackCount) of \(totalGoals) goals on track"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let monthlyPlanningGoalUpdated = Notification.Name("monthlyPlanningGoalUpdated")
    static let monthlyPlanningGoalDeleted = Notification.Name("monthlyPlanningGoalDeleted")
    static let monthlyPlanningAssetUpdated = Notification.Name("monthlyPlanningAssetUpdated")
}
