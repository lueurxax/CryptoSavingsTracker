//
//  AllocationManagementView.swift
//  CryptoSavingsTracker
//

import SwiftUI
import SwiftData

struct AllocationManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Use @Query to get goals directly
    @Query(sort: \Goal.name) private var allGoals: [Goal]
    
    let asset: Asset
    @State private var allocations: [UUID: Double] = [:]
    @State private var isInitialized = false
    
    var totalAllocation: Double {
        allocations.values.reduce(0, +)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text(asset.currency)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    if let address = asset.address, !address.isEmpty {
                        Text("\(String(address.prefix(12)))...\(String(address.suffix(8)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospaced()
                    }
                    
                    // Allocation summary
                    HStack(spacing: 16) {
                        VStack {
                            Text("\(Int(totalAllocation * 100))%")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(totalAllocation > 1.0 ? .red : .blue)
                            Text("Allocated")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Text("\(Int((1.0 - totalAllocation) * 100))%")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                            Text("Available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Text("\(allGoals.count)")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("Goals")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                }
                .padding()
                
                if totalAllocation > 1.0 {
                    Label("Total allocation exceeds 100%", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                // Goals list
                if allGoals.isEmpty {
                    ContentUnavailableView(
                        "No Goals Available",
                        systemImage: "target",
                        description: Text("Create goals first to allocate this asset")
                    )
                } else {
                    List {
                        Section("Allocate to Goals") {
                            ForEach(allGoals) { goal in
                                GoalAllocationRow(
                                    goal: goal,
                                    allocation: Binding(
                                        get: { allocations[goal.id] ?? 0 },
                                        set: { newValue in
                                            allocations[goal.id] = newValue
                                        }
                                    ),
                                    maxAllocation: min(1.0, (allocations[goal.id] ?? 0) + (1.0 - totalAllocation))
                                )
                            }
                        }
                        
                        Section {
                            Button(action: distributeEvenly) {
                                Label("Distribute Evenly", systemImage: "equal.circle")
                            }
                            
                            Button(action: clearAll) {
                                Label("Clear All", systemImage: "xmark.circle")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manage Allocations")
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
                    .disabled(totalAllocation > 1.0)
                }
            }
        }
        .onAppear {
            if !isInitialized {
                loadExistingAllocations()
                isInitialized = true
            }
        }
    }
    
    private func loadExistingAllocations() {
        for allocation in asset.allocations {
            if let goal = allocation.goal {
                allocations[goal.id] = allocation.percentage
            }
        }
    }
    
    private func distributeEvenly() {
        guard !allGoals.isEmpty else { return }
        let share = 1.0 / Double(allGoals.count)
        for goal in allGoals {
            allocations[goal.id] = share
        }
    }
    
    private func clearAll() {
        allocations.removeAll()
    }
    
    private func saveAllocations() {
        // Remove existing allocations
        for allocation in asset.allocations {
            modelContext.delete(allocation)
        }
        
        // Create new allocations
        for goal in allGoals {
            if let percentage = allocations[goal.id], percentage > 0 {
                let allocation = AssetAllocation(
                    asset: asset,
                    goal: goal,
                    percentage: percentage
                )
                modelContext.insert(allocation)
            }
        }
        
        // Save
        do {
            try modelContext.save()
            dismiss()
        } catch {
            // Silent failure - UI will show error state if needed
        }
    }
}

struct GoalAllocationRow: View {
    let goal: Goal
    @Binding var allocation: Double
    let maxAllocation: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.name)
                        .font(.headline)
                    Text("Target: \(goal.currency) \(Int(goal.targetAmount))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(Int(allocation * 100))%")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(allocation > 0 ? .blue : .secondary)
                    .frame(width: 60, alignment: .trailing)
            }
            
            // Slider
            Slider(
                value: $allocation,
                in: 0...maxAllocation,
                step: 0.05
            )
            .tint(.blue)
            
            // Quick buttons
            HStack(spacing: 8) {
                ForEach([0, 25, 50, 75, 100], id: \.self) { percent in
                    Button("\(percent)%") {
                        let targetValue = Double(percent) / 100.0
                        if targetValue <= maxAllocation {
                            allocation = targetValue
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(Double(percent) / 100.0 > maxAllocation)
                }
            }
        }
        .padding(.vertical, 4)
    }
}