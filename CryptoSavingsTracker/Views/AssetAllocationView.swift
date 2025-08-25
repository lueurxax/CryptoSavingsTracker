//
//  AssetAllocationView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 25/08/2025.
//

import SwiftUI
import SwiftData

struct AssetAllocationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Goal.name) private var allGoals: [Goal]
    
    let asset: Asset
    @State private var allocations: [UUID: Double] = [:]
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init(asset: Asset) {
        self.asset = asset
    }
    
    var totalAllocation: Double {
        allocations.values.reduce(0, +)
    }
    
    var remainingAllocation: Double {
        max(0, 1.0 - totalAllocation)
    }
    
    var isValid: Bool {
        totalAllocation <= 1.0
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header showing asset info
                VStack(spacing: 8) {
                    Text(asset.currency)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    if let address = asset.address, !address.isEmpty {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    // Total allocation indicator
                    VStack(spacing: 4) {
                        Text("Total Allocated: \(totalAllocation * 100, specifier: "%.0f")%")
                            .font(.headline)
                            .foregroundColor(totalAllocation > 1.0 ? .red : .primary)
                        
                        ProgressView(value: min(totalAllocation, 1.0))
                            .tint(totalAllocation > 1.0 ? .red : .blue)
                        
                        if remainingAllocation > 0 {
                            Text("\(remainingAllocation * 100, specifier: "%.0f")% remaining")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding()
                
                // Allocation list
                List {
                    Section {
                        if allGoals.isEmpty {
                            Text("No goals available")
                                .foregroundColor(.secondary)
                                .italic()
                                .padding()
                        } else {
                            ForEach(allGoals) { goal in
                                AllocationRow(
                                    goal: goal,
                                    allocation: Binding(
                                        get: { allocations[goal.id] ?? 0 },
                                        set: { allocations[goal.id] = $0 }
                                    ),
                                    remainingAllocation: remainingAllocation
                                )
                            }
                        }
                    } header: {
                        Text("Allocate to Goals")
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            if totalAllocation > 1.0 {
                                Label("Total allocation cannot exceed 100%", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                            Text("Goals: \(allGoals.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Quick actions
                    Section("Quick Actions") {
                        Button(action: distributeEvenly) {
                            Label("Distribute Evenly", systemImage: "equal.circle")
                        }
                        .disabled(allGoals.isEmpty)
                        
                        Button(action: clearAllocations) {
                            Label("Clear All", systemImage: "xmark.circle")
                                .foregroundColor(.red)
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
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
                    .disabled(!isValid)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            loadCurrentAllocations()
        }
    }
    
    private func loadCurrentAllocations() {
        // Load existing allocations
        for allocation in asset.allocations {
            if let goal = allocation.goal {
                allocations[goal.id] = allocation.percentage
            }
        }
        
        // Debug: Print current state
        print("Loading allocations for asset: \(asset.currency)")
        print("Found \(asset.allocations.count) existing allocations")
        print("Found \(allGoals.count) total goals")
    }
    
    private func distributeEvenly() {
        guard !allGoals.isEmpty else { return }
        let equalShare = 1.0 / Double(allGoals.count)
        for goal in allGoals {
            allocations[goal.id] = equalShare
        }
    }
    
    private func clearAllocations() {
        allocations.removeAll()
    }
    
    private func saveAllocations() {
        guard isValid else {
            errorMessage = "Please ensure total allocation doesn't exceed 100%"
            showingError = true
            return
        }
        
        do {
            // Convert UUID allocations back to Goal allocations
            var goalAllocations: [Goal: Double] = [:]
            for goal in allGoals {
                if let percentage = allocations[goal.id], percentage > 0 {
                    goalAllocations[goal] = percentage
                }
            }
            
            let allocationService = AllocationService(modelContext: modelContext)
            try allocationService.updateAllocations(for: asset, newAllocations: goalAllocations)
            dismiss()
        } catch {
            errorMessage = "Failed to save allocations: \(error.localizedDescription)"
            showingError = true
        }
    }
}

struct AllocationRow: View {
    let goal: Goal
    @Binding var allocation: Double
    let remainingAllocation: Double
    
    @State private var isEditing = false
    
    var percentageText: String {
        if allocation > 0 {
            return "\(Int(allocation * 100))%"
        }
        return "0%"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.name)
                        .font(.headline)
                    
                    Text("Target: \(goal.targetAmount, specifier: "%.0f") \(goal.currency)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(percentageText)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(allocation > 0 ? .blue : .secondary)
            }
            
            Slider(
                value: $allocation,
                in: 0...min(allocation + remainingAllocation, 1.0),
                step: 0.05
            )
            .tint(.blue)
            
            // Quick percentage buttons
            HStack(spacing: 8) {
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { value in
                    Button(action: {
                        if value <= allocation + remainingAllocation {
                            allocation = value
                        }
                    }) {
                        Text("\(Int(value * 100))%")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(value > allocation + remainingAllocation && value != 0)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add to Asset Detail View
struct AssetDetailMenuButton: View {
    let asset: Asset
    @State private var showingAllocationView = false
    
    var body: some View {
        Button(action: {
            showingAllocationView = true
        }) {
            Label("Manage Allocations", systemImage: "chart.pie")
        }
        .sheet(isPresented: $showingAllocationView) {
            AssetAllocationView(asset: asset)
        }
    }
}

struct AssetAllocationView_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, AssetAllocation.self, configurations: config)
        
        // Create sample data
        let goal1 = Goal(name: "House Fund", currency: "USD", targetAmount: 100000, deadline: Date().addingTimeInterval(86400 * 365))
        let goal2 = Goal(name: "Emergency Fund", currency: "USD", targetAmount: 20000, deadline: Date().addingTimeInterval(86400 * 180))
        let goal3 = Goal(name: "Vacation", currency: "USD", targetAmount: 5000, deadline: Date().addingTimeInterval(86400 * 90))
        
        container.mainContext.insert(goal1)
        container.mainContext.insert(goal2)
        container.mainContext.insert(goal3)
        
        let asset = Asset(currency: "BTC", address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh")
        container.mainContext.insert(asset)
        
        return AssetAllocationView(asset: asset)
            .modelContainer(container)
    }
}