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
    @State private var allocations: [UUID: Double] = [:]
    @State private var hasLoadedInitial = false
    @State private var fetchedOnChainBalance: Double? = nil
    @State private var isLoadingBalance: Bool = false

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
        goals.compactMap { goal in
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
                    // Asset info card
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
                        
                        // Allocation status (amount-based pie)
                        SimplePieChart(
                            allocations: pieData.allocations,
                            unallocatedPercentage: pieData.unallocated
                        )
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(15)
                    
                    // Instructions
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
                    
                    // Goals allocation section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Allocate to Goals")
                            .font(.headline)
                        
                        if goals.isEmpty {
                            Text("No goals available. Create goals first to share this asset.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(10)
                        } else {
                            ForEach(goals) { goal in
                                GoalAllocationCard(
                                    goal: goal,
                                    allocation: Binding(
                                        get: { allocations[goal.id] ?? 0 },
                                        set: { allocations[goal.id] = $0 }
                                    ),
                                    assetCurrency: asset.currency,
                                    assetBalance: bestKnownBalance,
                                    remainingAmount: remainingAmount,
                                    onAllocateRemaining: {
                                        let epsilon = 0.0000001
                                        let remaining = remainingAmount
                                        guard remaining > epsilon else { return }
                                        allocations[goal.id] = (allocations[goal.id] ?? 0) + remaining
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Quick actions
                    VStack(spacing: 12) {
                        Button(action: clearAll) {
                            Label("Clear All Allocations", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(.horizontal)
                    
                    if isOverAllocated {
                        Label("Allocated amount exceeds balance. Please reduce allocations.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal)
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
                }
                hasLoadedInitial = true
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
    
    private func clearAll() {
        allocations.removeAll()
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
