//
//  AssetSharingView.swift
//  CryptoSavingsTracker
//

import SwiftUI
import SwiftData

struct AssetSharingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Goal> { goal in
            goal.lifecycleStatusRawValue == "active"
        },
        sort: \Goal.name
    )
    private var goals: [Goal]
    
    let asset: Asset
    let currentGoalId: UUID?
    @State private var allocations: [UUID: Double] = [:]
    @State private var hasLoadedInitial = false
    @State private var fetchedOnChainBalance: Double? = nil
    @State private var isLoadingBalance: Bool = false
    @State private var closeMonthSuggestions: [UUID: Double] = [:]
    @State private var isLoadingCloseMonth = false
    @State private var hasActiveExecution = false
    @State private var pendingPrefillGoalId: UUID?
    @State private var closeMonthClampWarning: String?

    init(asset: Asset, currentGoalId: UUID? = nil, prefillCloseMonthGoalId: UUID? = nil) {
        self.asset = asset
        self.currentGoalId = currentGoalId
        _pendingPrefillGoalId = State(initialValue: prefillCloseMonthGoalId)
    }

    private var hasOnChainAddress: Bool {
        guard
            let chainId = asset.chainId, !chainId.isEmpty,
            let address = asset.address, !address.isEmpty
        else { return false }
        return true
    }

    private var bestKnownBalance: Double {
        // Prefer a fresh fetch when available, otherwise fall back to cached on-chain + manual.
        let cached = asset.currentAmount
        guard let fetchedOnChainBalance else { return cached }
        return max(cached, asset.manualBalance + fetchedOnChainBalance)
    }
    
    var totalAmount: Double {
        allocations.values.reduce(0, +)
    }
    
    var remainingAmount: Double {
        max(0, bestKnownBalance - totalAmount)
    }
    
    var isOverAllocated: Bool {
        totalAmount > bestKnownBalance + 0.000001
    }
    
    var allocationData: [(goal: Goal, amount: Double)] {
        orderedGoals.compactMap { goal in
            let amount = allocations[goal.id] ?? 0
            return amount > 0 ? (goal, amount) : nil
        }
    }
    
    var pieData: (allocations: [(goal: Goal, percentage: Double)], unallocated: Double) {
        let totalForPie = max(bestKnownBalance, totalAmount)
        guard totalForPie > 0 else {
            return ([], 1.0)
        }
        let allocationsPercent = allocationData.map { (goal: $0.goal, percentage: max(0, $0.amount / totalForPie)) }
        let used = allocationsPercent.map(\.percentage).reduce(0, +)
        let unallocated = max(0, 1.0 - used)
        return (allocationsPercent, unallocated)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    assetInfoCard
                    instructionsCard
                    goalsAllocationSection
                    closeMonthClampWarningView
                    quickActionsSection
                    if isOverAllocated {
                        overAllocationWarning
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Share Asset")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAllocations()
                    }
                    .disabled(isOverAllocated)
                    .accessibilityIdentifier("saveAllocationsButton")
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if !hasLoadedInitial {
                loadExistingAllocations()
                Task {
                    await refreshOnChainBalanceIfNeeded()
                    await loadCloseMonthSuggestionsIfNeeded()
                }
                hasLoadedInitial = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .monthlyPlanningAssetUpdated)) { _ in
            Task {
                await loadCloseMonthSuggestionsIfNeeded()
            }
        }
    }
    
    private func loadExistingAllocations() {
        // Load existing allocations for this asset
        for allocation in asset.allocations {
            if let goal = allocation.goal {
                allocations[goal.id] = allocation.amountValue
            }
        }
    }

    private var assetInfoCard: some View {
        VStack(spacing: 12) {
            Text(asset.currency)
                .font(.largeTitle)
                .fontWeight(.bold)

            if let address = asset.address {
                Text(address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .monospaced()
            }

            SimplePieChart(
                allocations: pieData.allocations,
                unallocatedPercentage: pieData.unallocated
            )
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(15)
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How to share this asset:", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundColor(.blue)

            Text("Enter fixed amounts (in \(asset.currency)) to allocate to each goal. Total cannot exceed your asset balance.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(10)
    }

    private var goalsAllocationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Allocate to Goals")
                .font(.headline)

            if hasActiveExecution {
                HStack(spacing: 6) {
                    if isLoadingCloseMonth {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "target")
                    }
                    Text("Quick add: close current month")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            if orderedGoals.isEmpty {
                Text("No goals available. Create goals first to share this asset.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(10)
            } else {
                ForEach(orderedGoals) { goal in
                    GoalAllocationCard(
                        goal: goal,
                        allocation: allocationBinding(for: goal),
                        assetCurrency: asset.currency,
                        assetBalance: bestKnownBalance,
                        remainingAmount: remainingAmount,
                        onAllocateRemaining: { allocateRemaining(to: goal) },
                        closeMonthAmount: closeMonthAmount(for: goal),
                        onAddToCloseMonth: closeMonthAction(for: goal)
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            Button(action: clearAll) {
                Label("Clear All Allocations", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.horizontal)
    }

    private var closeMonthClampWarningView: some View {
        Group {
            if let closeMonthClampWarning {
                Label(closeMonthClampWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .accessibilityIdentifier("closeMonthClampWarning")
            }
        }
    }

    private var overAllocationWarning: some View {
        Label("Allocated amount exceeds balance. Please reduce allocations.", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundColor(.red)
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(10)
            .padding(.horizontal)
    }

    private var orderedGoals: [Goal] {
        guard let currentGoalId else { return goals }
        if let currentGoal = goals.first(where: { $0.id == currentGoalId }) {
            let remaining = goals.filter { $0.id != currentGoalId }
            return [currentGoal] + remaining
        }
        return goals
    }
    
    private func clearAll() {
        allocations.removeAll()
        closeMonthClampWarning = nil
    }

    private func allocationBinding(for goal: Goal) -> Binding<Double> {
        Binding(
            get: { allocations[goal.id] ?? 0 },
            set: { allocations[goal.id] = $0 }
        )
    }

    private func allocateRemaining(to goal: Goal) {
        let epsilon = 0.0000001
        let remaining = remainingAmount
        guard remaining > epsilon else { return }
        allocations[goal.id] = (allocations[goal.id] ?? 0) + remaining
    }

    private func closeMonthAmount(for goal: Goal) -> Double? {
        hasActiveExecution ? closeMonthSuggestions[goal.id] : nil
    }

    private func closeMonthAction(for goal: Goal) -> (() -> Void)? {
        guard hasActiveExecution else { return nil }
        return { addCloseMonthAllocation(for: goal) }
    }

    private func addCloseMonthAllocation(for goal: Goal) {
        let epsilon = 0.0000001
        guard let suggestion = closeMonthSuggestions[goal.id], suggestion > epsilon else { return }
        let available = max(0, remainingAmount)
        let toAllocate = min(suggestion, available)
        guard toAllocate > epsilon else {
            closeMonthClampWarning = "No unallocated balance available to add for \(goal.name)."
            return
        }
        allocations[goal.id] = (allocations[goal.id] ?? 0) + toAllocate
        if suggestion > available + epsilon {
            closeMonthClampWarning = "Only \(formatAmount(toAllocate)) \(asset.currency) available to add for \(goal.name)."
        } else {
            closeMonthClampWarning = nil
        }
    }

    private func formatAmount(_ amount: Double) -> String {
        String(format: "%.4f", amount)
    }
    
    private func saveAllocations() {
        // Ensure the backing cache is updated so validation reflects the displayed balance.
        cacheFetchedBalanceIfNeeded()

        do {
            let service = AllocationService(modelContext: modelContext)
            let newAllocations = goals.map { goal in
                (goal: goal, amount: allocations[goal.id] ?? 0)
            }
            try service.updateAllocations(for: asset, newAllocations: newAllocations)
            dismiss()
        } catch {
            // Error handling would go here
        }
    }

    @MainActor
    private func loadCloseMonthSuggestionsIfNeeded() async {
        guard !isLoadingCloseMonth else { return }
        isLoadingCloseMonth = true
        defer { isLoadingCloseMonth = false }

        let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
        do {
            guard let record = try executionService.getActiveRecord() else {
                hasActiveExecution = false
                closeMonthSuggestions = [:]
                pendingPrefillGoalId = nil
                return
            }

            hasActiveExecution = true

            let planService = DIContainer.shared.makeMonthlyPlanService(modelContext: modelContext)
            let plans = try planService.fetchPlans(for: record.monthLabel)
            let trackedIds = Set(record.goalIds)
            let trackedPlans = plans.filter { trackedIds.contains($0.goalId) }
            let contributions = try await executionService.getContributionTotals(for: record)
            let calculator = ExecutionContributionCalculator(exchangeRateService: DIContainer.shared.exchangeRateService)

            var suggestions: [UUID: Double] = [:]
            for plan in trackedPlans {
                let planned = plan.effectiveAmount
                guard planned > 0 else { continue }

                let contributed = contributions[plan.goalId] ?? 0
                let remaining = max(0, planned - contributed)
                guard remaining > 0 else { continue }

                if let converted = await calculator.convertAmount(
                    remaining,
                    from: plan.currency,
                    to: asset.currency
                ), converted > 0 {
                    suggestions[plan.goalId] = converted
                }
            }

            closeMonthSuggestions = suggestions
            applyPendingPrefillIfNeeded()
        } catch {
            hasActiveExecution = false
            closeMonthSuggestions = [:]
            pendingPrefillGoalId = nil
        }
    }

    private func applyPendingPrefillIfNeeded() {
        guard let goalId = pendingPrefillGoalId else { return }
        guard let goal = goals.first(where: { $0.id == goalId }) else { return }
        addCloseMonthAllocation(for: goal)
        pendingPrefillGoalId = nil
    }

    private func cacheFetchedBalanceIfNeeded() {
        guard hasOnChainAddress else { return }
        guard let fetchedOnChainBalance else { return }
        guard let chainId = asset.chainId, let address = asset.address else { return }
        let key = BalanceCacheManager.balanceCacheKey(chainId: chainId, address: address, symbol: asset.currency)
        BalanceCacheManager.shared.cacheBalance(fetchedOnChainBalance, for: key)
    }

    @MainActor
    private func refreshOnChainBalanceIfNeeded() async {
        guard hasOnChainAddress else { return }
        guard let chainId = asset.chainId, let address = asset.address else { return }
        guard !isLoadingBalance else { return }

        isLoadingBalance = true
        defer { isLoadingBalance = false }

        do {
            let balance = try await DIContainer.shared.balanceService.fetchBalance(
                chainId: chainId,
                address: address,
                symbol: asset.currency,
                forceRefresh: false
            )
            fetchedOnChainBalance = balance
            cacheFetchedBalanceIfNeeded()
        } catch {
            // Keep best-effort behavior: allocations UI should still work off cached values.
        }
    }
}
