//
//  TestAllocationView.swift
//  CryptoSavingsTracker
//

import SwiftUI
import SwiftData

struct TestAllocationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let asset: Asset
    @State private var goals: [Goal] = []
    @State private var allocations: [UUID: Double] = [:]
    @State private var isLoading = true
    
    var totalAllocation: Double {
        allocations.values.reduce(0, +)
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Loading goals...")
                        .padding()
                } else if goals.isEmpty {
                    ContentUnavailableView(
                        "No Goals Available",
                        systemImage: "target",
                        description: Text("Create at least one goal to allocate this asset")
                    )
                } else {
                    List {
                        Section {
                            Text("Asset: \(asset.currency)")
                                .font(.headline)
                            Text("Total Allocated: \(Int(totalAllocation * 100))%")
                                .foregroundColor(totalAllocation > 1.0 ? .red : .primary)
                        }
                        
                        Section("Allocate to Goals (\(goals.count) available)") {
                            ForEach(goals) { goal in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(goal.name)
                                                .font(.headline)
                                            Text("Target: \(goal.currency) \(Int(goal.targetAmount))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text("\(Int((allocations[goal.id] ?? 0) * 100))%")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(allocations[goal.id] ?? 0 > 0 ? .blue : .secondary)
                                    }
                                    
                                    Slider(
                                        value: Binding(
                                            get: { allocations[goal.id] ?? 0 },
                                            set: { allocations[goal.id] = $0 }
                                        ),
                                        in: 0...1,
                                        step: 0.05
                                    )
                                    
                                    HStack {
                                        ForEach([0, 25, 50, 75, 100], id: \.self) { percent in
                                            Button("\(percent)%") {
                                                allocations[goal.id] = Double(percent) / 100.0
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        
                        Section {
                            Button(action: {
                                // Distribute evenly
                                let share = 1.0 / Double(goals.count)
                                for goal in goals {
                                    allocations[goal.id] = share
                                }
                            }) {
                                Label("Distribute Evenly", systemImage: "equal.circle")
                            }
                            
                            Button(action: {
                                allocations.removeAll()
                            }) {
                                Label("Clear All", systemImage: "xmark.circle")
                            }
                            .foregroundColor(.red)
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
        .task {
            await loadData()
        }
    }
    
    private func loadData() async {
        let descriptor = FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.name)])
        
        do {
            let fetchedGoals = try modelContext.fetch(descriptor)
            
            await MainActor.run {
                self.goals = fetchedGoals
                
                // Load current allocations
                for allocation in asset.allocations {
                    if let goal = allocation.goal {
                        allocations[goal.id] = allocation.percentage
                    }
                }
                
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func saveAllocations() {
        // Remove all existing allocations
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
            // Silent failure
        }
    }
}