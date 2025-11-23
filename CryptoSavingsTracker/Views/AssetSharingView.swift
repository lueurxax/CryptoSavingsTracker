//
//  AssetSharingView.swift
//  CryptoSavingsTracker
//

import SwiftUI
import SwiftData

struct AssetSharingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Goal.name) private var goals: [Goal]
    
    let asset: Asset
    @State private var allocations: [UUID: Double] = [:]
    @State private var hasLoadedInitial = false
    
    var totalAmount: Double {
        allocations.values.reduce(0, +)
    }
    
    var remainingAmount: Double {
        max(0, asset.currentAmount - totalAmount)
    }
    
    var isOverAllocated: Bool {
        totalAmount > asset.currentAmount + 0.000001
    }
    
    var allocationData: [(goal: Goal, amount: Double)] {
        goals.compactMap { goal in
            let amount = allocations[goal.id] ?? 0
            return amount > 0 ? (goal, amount) : nil
        }
    }
    
    var pieData: (allocations: [(goal: Goal, percentage: Double)], unallocated: Double) {
        let totalForPie = max(asset.currentAmount, totalAmount)
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
                                    )
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
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if !hasLoadedInitial {
                loadExistingAllocations()
                hasLoadedInitial = true
            }
        }
    }
    
    private func loadExistingAllocations() {
        // Load existing allocations for this asset
        for allocation in asset.allocations {
            if let goal = allocation.goal {
                let amount = allocation.amount > 0 ? allocation.amount : allocation.percentage * asset.currentAmount
                allocations[goal.id] = amount
            }
        }
    }
    
    private func clearAll() {
        allocations.removeAll()
    }
    
    private func saveAllocations() {
        // Remove all existing allocations for this asset
        for allocation in asset.allocations {
            modelContext.delete(allocation)
        }
        
        // Create new allocations
        for goal in goals {
            if let amount = allocations[goal.id], amount > 0 {
                let allocation = AssetAllocation(
                    asset: asset,
                    goal: goal,
                    amount: amount
                )
                modelContext.insert(allocation)
            }
        }
        
        // Save changes
        do {
            try modelContext.save()
            dismiss()
        } catch {
            // Error handling would go here
        }
    }
}
