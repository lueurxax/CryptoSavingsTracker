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
    
    var totalPercentage: Double {
        allocations.values.reduce(0, +)
    }
    
    var remainingPercentage: Double {
        max(0, 1.0 - totalPercentage)
    }
    
    var isOverAllocated: Bool {
        totalPercentage > 1.0
    }
    
    var allocationData: [(goal: Goal, percentage: Double)] {
        goals.compactMap { goal in
            let percentage = allocations[goal.id] ?? 0
            return percentage > 0 ? (goal, percentage) : nil
        }
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
                        
                        // Allocation status
                        // Pie chart visualization
                        AllocationPieChart(
                            allocations: allocationData,
                            unallocatedPercentage: remainingPercentage
                        )
                        .frame(height: 250)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(15)
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How to share this asset:", systemImage: "info.circle.fill")
                            .font(.headline)
                            .foregroundColor(.blue)
                        
                        Text("Adjust the sliders below to allocate percentages of this asset to different goals. The total cannot exceed 100%.")
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
                                VStack(spacing: 12) {
                                    // Goal header
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(goal.name)
                                                .font(.headline)
                                            Text("Target: \(goal.currency) \(Int(goal.targetAmount))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        // Current allocation
                                        VStack(alignment: .trailing) {
                                            Text("\(Int((allocations[goal.id] ?? 0) * 100))%")
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(allocations[goal.id] ?? 0 > 0 ? .blue : .secondary)
                                            
                                            if allocations[goal.id] ?? 0 > 0 {
                                                Text("allocated")
                                                    .font(.caption2)
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                    }
                                    
                                    // Slider
                                    Slider(
                                        value: Binding(
                                            get: { allocations[goal.id] ?? 0 },
                                            set: { allocations[goal.id] = $0 }
                                        ),
                                        in: 0...1,
                                        step: 0.05
                                    )
                                    .tint(.blue)
                                    
                                    // Quick percentage buttons
                                    HStack(spacing: 8) {
                                        ForEach([0, 25, 50, 75, 100], id: \.self) { percent in
                                            Button(action: {
                                                allocations[goal.id] = Double(percent) / 100.0
                                            }) {
                                                Text("\(percent)%")
                                                    .font(.caption)
                                                    .frame(maxWidth: .infinity)
                                            }
                                            .buttonStyle(.bordered)
                                            .tint(allocations[goal.id] == Double(percent) / 100.0 ? .blue : .gray)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(10)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Quick actions
                    VStack(spacing: 12) {
                        Button(action: distributeEvenly) {
                            Label("Distribute Evenly", systemImage: "equal.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(goals.isEmpty)
                        
                        Button(action: clearAll) {
                            Label("Clear All Allocations", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(.horizontal)
                    
                    if isOverAllocated {
                        Label("Total exceeds 100%. Please reduce allocations.", systemImage: "exclamationmark.triangle.fill")
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
                allocations[goal.id] = allocation.percentage
            }
        }
    }
    
    private func distributeEvenly() {
        guard !goals.isEmpty else { return }
        let equalShare = 1.0 / Double(goals.count)
        for goal in goals {
            allocations[goal.id] = equalShare
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
            if let percentage = allocations[goal.id], percentage > 0 {
                let allocation = AssetAllocation(
                    asset: asset,
                    goal: goal,
                    percentage: percentage
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