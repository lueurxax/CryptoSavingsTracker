//
//  AssetSharingView.swift
//  CryptoSavingsTracker
//

import SwiftUI
import SwiftData

struct AssetSharingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Goal.name)
    private var allGoals: [Goal]
    
    let asset: Asset
    let currentGoalId: UUID?
    @State private var allocations: [UUID: Double] = [:]
    @State private var hasLoadedInitial = false
    @State private var fetchedOnChainBalance: Double? = nil
    @State private var isLoadingBalance: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var legacyReviewCoordinator = LegacyFinishedAllocationReviewCoordinator()

    init(asset: Asset, currentGoalId: UUID? = nil) {
        self.asset = asset
        self.currentGoalId = currentGoalId
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
    
    private var activeGoals: [Goal] {
        allGoals.filter { $0.lifecycleStatus == .active }
    }

    private var existingAllocationEntries: [AssetAllocationEditorEntry] {
        (asset.allocations ?? []).compactMap { allocation in
            guard let goal = allocation.goal else { return nil }
            let finishedState = AssetAllocationEditorPolicy.finishedState(
                allocationID: allocation.id,
                goalID: goal.id,
                assetID: asset.id,
                amount: allocation.amountValue,
                goalStatus: goal.lifecycleStatus,
                hasCompletionSnapshotData: goal.completionSnapshotData != nil,
                snapshot: goal.completionSnapshot
            )
            return AssetAllocationEditorEntry(
                allocationID: allocation.id,
                assetID: asset.id,
                goalID: goal.id,
                goalName: goal.name,
                status: goal.lifecycleStatus,
                amount: allocation.amountValue,
                finishedState: finishedState
            )
        }
    }

    private var pendingReviewEntries: [AssetAllocationEditorEntry] {
        existingAllocationEntries
            .filter {
                $0.finishedState == .pendingReview
                    && AssetAllocationEditorPolicy.shouldPresentAllocation(amount: $0.amount)
            }
            .sorted { $0.goalName.localizedCaseInsensitiveCompare($1.goalName) == .orderedAscending }
    }

    private var reservedAsSpentEntries: [AssetAllocationEditorEntry] {
        existingAllocationEntries
            .filter {
                $0.finishedState == .reservedAsSpent
                    && AssetAllocationEditorPolicy.shouldPresentAllocation(amount: $0.amount)
            }
            .sorted { $0.goalName.localizedCaseInsensitiveCompare($1.goalName) == .orderedAscending }
    }

    private var invalidFinishedEntries: [AssetAllocationEditorEntry] {
        existingAllocationEntries.filter {
            $0.status == .finished
                && $0.finishedState == nil
                && AssetAllocationEditorPolicy.shouldPresentAllocation(amount: $0.amount)
        }
    }

    private var pendingReviewGoals: [Goal] {
        let goalIDs = Set(pendingReviewEntries.map(\.goalID))
        var seenGoalIDs = Set<UUID>()
        return (asset.allocations ?? []).compactMap { allocation in
            guard
                let goal = allocation.goal,
                goalIDs.contains(goal.id),
                seenGoalIDs.insert(goal.id).inserted
            else { return nil }
            return goal
        }
    }

    private var reviewGoalsByID: [UUID: Goal] {
        Dictionary(uniqueKeysWithValues: pendingReviewGoals.map { ($0.id, $0) })
    }

    private var presentationEntries: [AssetAllocationEditorEntry] {
        let activeEntries = activeGoals.compactMap { goal -> AssetAllocationEditorEntry? in
            let amount = allocations[goal.id] ?? 0
            guard AssetAllocationEditorPolicy.shouldPresentAllocation(amount: amount) else { return nil }
            let allocationID = (asset.allocations ?? [])
                .first(where: { $0.goal?.id == goal.id })?.id ?? goal.id
            return AssetAllocationEditorEntry(
                allocationID: allocationID,
                assetID: asset.id,
                goalID: goal.id,
                goalName: goal.name,
                status: .active,
                amount: amount,
                finishedState: nil
            )
        }
        return activeEntries + pendingReviewEntries + reservedAsSpentEntries
    }

    private var breakdown: AssetAllocationEditorBreakdown {
        AssetAllocationEditorPolicy.breakdown(
            balance: bestKnownBalance,
            entries: presentationEntries
        )
    }

    var totalAmount: Double {
        breakdown.activeAllocatedAmount
            + breakdown.pendingReviewAmount
            + breakdown.finishedReservedAmount
    }
    
    var remainingAmount: Double {
        breakdown.unallocatedAmount
    }
    
    var isOverAllocated: Bool {
        editorWarning != .none
    }

    private var editorWarning: AssetAllocationEditorWarning {
        AssetAllocationEditorPolicy.warning(
            balance: bestKnownBalance,
            entries: presentationEntries
        )
    }
    
    var allocationData: [(goal: Goal, amount: Double)] {
        orderedGoals.compactMap { goal in
            let amount = allocations[goal.id] ?? 0
            return amount > 0 ? (goal, amount) : nil
        }
    }
    
    var pieData: (
        allocations: [(goal: Goal, percentage: Double, chartPercentage: Double)],
        pendingReview: Double,
        pendingReviewChart: Double,
        finishedReserved: Double,
        finishedReservedChart: Double,
        unallocated: Double,
        unallocatedChart: Double
    ) {
        let chartDenominator = max(bestKnownBalance, totalAmount)
        guard chartDenominator > 0 else {
            return ([], 0, 0, 0, 0, 1.0, 1.0)
        }
        let displayDenominator = bestKnownBalance > AssetAllocationEditorPolicy.allocationEpsilon
            ? bestKnownBalance
            : chartDenominator
        let allocationsPercent = allocationData.map {
            (
                goal: $0.goal,
                percentage: max(0, $0.amount / displayDenominator),
                chartPercentage: max(0, $0.amount / chartDenominator)
            )
        }
        return (
            allocationsPercent,
            breakdown.pendingReviewPercentage,
            breakdown.pendingReviewChartPercentage,
            breakdown.finishedReservedPercentage,
            breakdown.finishedReservedChartPercentage,
            breakdown.unallocatedPercentage,
            breakdown.unallocatedChartPercentage
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    assetInfoCard
                    instructionsCard
                    goalsAllocationSection
                    quickActionsSection
                    if isOverAllocated {
                        overAllocationWarning
                    }
                    pendingReviewSection
                    reservedAsSpentSection
                }
                .padding(.vertical)
            }
            .navigationTitle("Manage Allocations")
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
                    .disabled(isOverAllocated || isSaving)
                    .accessibilityIdentifier("saveAllocationsButton")
                    .fontWeight(.semibold)
                }
            }
        }
        .alert("Could not save allocations", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Please try again.")
        }
        .sheet(isPresented: Binding(
            get: { legacyReviewCoordinator.isPresented },
            set: { if !$0 { legacyReviewCoordinator.later() } }
        )) {
            LegacyFinishedAllocationReviewSheet(
                coordinator: legacyReviewCoordinator,
                goalsByID: reviewGoalsByID,
                onApply: applyLegacyReview,
                onLater: legacyReviewCoordinator.later
            )
        }
        .onAppear {
            if !hasLoadedInitial {
                loadExistingAllocations()
                Task {
                    await refreshOnChainBalanceIfNeeded()
                }
                hasLoadedInitial = true
            }
        }
    }
    
    private func loadExistingAllocations() {
        // Load existing allocations for this asset
        for allocation in (asset.allocations ?? []) {
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
                pendingReviewPercentage: pieData.pendingReview,
                pendingReviewChartPercentage: pieData.pendingReviewChart,
                finishedReservedPercentage: pieData.finishedReserved,
                finishedReservedChartPercentage: pieData.finishedReservedChart,
                unallocatedPercentage: pieData.unallocated,
                unallocatedChartPercentage: pieData.unallocatedChart
            )
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(15)
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How to allocate this asset:", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundColor(.blue)

            Text(
                "Assign fixed amounts in \(asset.currency) to each active goal. "
                    + "The total cannot exceed the available balance."
            )
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

            if orderedGoals.isEmpty {
                Text("No goals available. Create a goal first to allocate this asset.")
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
                        onAllocateRemaining: { allocateRemaining(to: goal) }
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            Button(action: clearAll) {
                Label("Clear Active Allocations", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.horizontal)
    }

    private var overAllocationWarning: some View {
        Label(overAllocationWarningText, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundColor(.red)
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(10)
            .padding(.horizontal)
    }

    private var overAllocationWarningText: String {
        switch editorWarning {
        case .reviewFinishedAllocations:
            return "Finished allocations need review before the available balance can be calculated correctly."
        case .reduceActiveAllocations:
            return "Allocated amount exceeds balance. Please reduce allocations."
        case .reservedAllocationDataConflict:
            return "Reserved finished allocations exceed the recorded balance. Active allocations cannot "
                + "resolve this data conflict; restore the completion data before saving."
        case .none:
            return ""
        }
    }

    @ViewBuilder
    private var pendingReviewSection: some View {
        if pendingReviewEntries.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                Label("Pending review", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(AccessibleColors.error)

                Text(
                    "\(formattedAllocationAmount(breakdown.pendingReviewAmount)) "
                        + "\(asset.currency) affected"
                )
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    "These legacy finished allocations remain unavailable until every allocation "
                        + "of each affected goal has been reviewed."
                )
                    .font(.caption)
                    .foregroundStyle(AccessibleColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: reviewFinishedAllocations) {
                    Label("Review finished allocations", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("reviewFinishedAllocations")

                VStack(spacing: 8) {
                    ForEach(pendingReviewEntries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(entry.goalName, systemImage: "clock.badge.exclamationmark")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(formattedAllocationAmount(entry.amount)) \(asset.currency)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            Text("Finished · Decision required")
                                .font(.caption2)
                                .foregroundStyle(AccessibleColors.secondaryText)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(
                            "pendingReviewAllocation-\(entry.goalID.uuidString)-"
                                + entry.allocationID.uuidString
                        )
                    }
                }
            }
            .padding()
            .background(AccessibleColors.errorBackground.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .accessibilityIdentifier("pendingReviewAllocationsSection")
        }
    }

    @ViewBuilder
    private var reservedAsSpentSection: some View {
        if reservedAsSpentEntries.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                Label("Reserved as spent", systemImage: "lock.fill")
                    .font(.headline)
                    .foregroundStyle(AccessibleColors.warning)

                Text(
                    "\(formattedAllocationAmount(breakdown.finishedReservedAmount)) "
                        + "\(asset.currency) reserved"
                )
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    "These finished allocations were confirmed as spent. They are read-only and "
                        + "remain unavailable for new allocations."
                )
                    .font(.caption)
                    .foregroundStyle(AccessibleColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    ForEach(reservedAsSpentEntries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(entry.goalName, systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(formattedAllocationAmount(entry.amount)) \(asset.currency)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            Text("Finished · Read-only")
                                .font(.caption2)
                                .foregroundStyle(AccessibleColors.secondaryText)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(
                            "reservedAsSpentAllocation-\(entry.goalID.uuidString)-"
                                + entry.allocationID.uuidString
                        )
                    }
                }
            }
            .padding()
            .background(AccessibleColors.warningBackground.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .accessibilityIdentifier("reservedAsSpentAllocationsSection")
        }
    }

    private var orderedGoals: [Goal] {
        guard let currentGoalId else { return activeGoals }
        if let currentGoal = activeGoals.first(where: { $0.id == currentGoalId }) {
            let remaining = activeGoals.filter { $0.id != currentGoalId }
            return [currentGoal] + remaining
        }
        return activeGoals
    }
    
    private func clearAll() {
        allocations = AssetAllocationEditorPolicy.clearingActiveAllocations(
            in: allocations,
            activeGoalIDs: activeGoals.map(\.id)
        )
    }

    private func reviewFinishedAllocations() {
        let service = GoalCompletionSettlementService(modelContext: modelContext)
        do {
            try legacyReviewCoordinator.load(goals: pendingReviewGoals) {
                try service.prepareLegacyReview(for: $0)
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func applyLegacyReview() {
        let service = GoalCompletionSettlementService(modelContext: modelContext)
        Task { @MainActor in
            do {
                try await legacyReviewCoordinator.apply {
                    try await service.applyBatch($0)
                }
            } catch {
                // The coordinator keeps the sheet open and exposes the retryable message.
            }
        }
    }

    private func allocationBinding(for goal: Goal) -> Binding<Double> {
        Binding(
            get: { allocations[goal.id] ?? 0 },
            set: { allocations[goal.id] = $0 }
        )
    }

    private func allocateRemaining(to goal: Goal) {
        let remaining = remainingAmount
        guard AssetAllocationEditorPolicy.shouldPresentAllocation(amount: remaining) else { return }
        allocations[goal.id] = (allocations[goal.id] ?? 0) + remaining
    }

    private func formattedAllocationAmount(_ amount: Double) -> String {
        amount.formatted(.number.precision(.fractionLength(0...8)))
    }
    
    private func saveAllocations() {
        guard !isSaving else { return }
        guard invalidFinishedEntries.isEmpty else {
            saveError = "A finished allocation no longer matches its completion record. "
                + "Nothing was changed. Restore the data before saving."
            return
        }
        isSaving = true
        defer { isSaving = false }

        // Ensure the backing cache is updated so validation reflects the displayed balance.
        cacheFetchedBalanceIfNeeded()

        do {
            let service = AllocationService(modelContext: modelContext)
            let amounts = AssetAllocationEditorPolicy.amountsForSave(
                activeGoalIDs: activeGoals.map(\.id),
                draft: allocations,
                existingEntries: existingAllocationEntries
            )
            var goalsByID: [UUID: Goal] = [:]
            for goal in allGoals {
                goalsByID[goal.id] = goal
            }
            for allocation in (asset.allocations ?? []) {
                if let goal = allocation.goal {
                    goalsByID[goal.id] = goal
                }
            }
            let newAllocations: [(goal: Goal, amount: Double)] = amounts.compactMap { goalID, amount in
                guard let goal = goalsByID[goalID] else { return nil }
                return (goal, amount)
            }
            try service.updateAllocations(for: asset, newAllocations: newAllocations)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
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
