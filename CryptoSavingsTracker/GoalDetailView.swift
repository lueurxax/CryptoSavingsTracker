//
//  GoalDetailView.swift
//  CryptoSavingsTracker
//
//  Created by user on 26/07/2025.
//

import SwiftUI
import SwiftData

struct GoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let goal: Goal
    
    @Query private var allAssets: [Asset]
    @Query private var allTransactions: [Transaction]
    @State private var showingAddAsset = false
    @State private var expandedAssets: Set<UUID> = []
    @State private var currentTotal: Double = 0
    @State private var progress: Double = 0
    
    private var goalAssets: [Asset] {
        allAssets.filter { $0.goal.id == goal.id }
    }
    
    init(goal: Goal) {
        self.goal = goal
        let goalId = goal.id
        self._allAssets = Query(filter: #Predicate<Asset> { asset in
            asset.goal.id == goalId
        }, sort: \Asset.currency)
    }
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(goal.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Deadline: \(goal.deadline, format: .dateTime.day().month().year()) (\(goal.daysRemaining) days remaining)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Target: \(goal.targetAmount, specifier: "%.2f") \(goal.currency)")
                        Spacer()
                        Text("\(Int(progress * 100))%")
                    }
                    .font(.subheadline)
                    
                    HStack {
                        Text("Current: \(currentTotal, specifier: "%.2f") \(goal.currency)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                }
                .padding(.vertical, 8)
            }
            
            Section(header: Text("Assets")) {
                ForEach(goalAssets) { asset in
                    AssetRowView(
                        asset: asset,
                        isExpanded: expandedAssets.contains(asset.id)
                    ) {
                        withAnimation(.default) {
                            if expandedAssets.contains(asset.id) {
                                expandedAssets.remove(asset.id)
                            } else {
                                expandedAssets.insert(asset.id)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteAssets)
                .animation(.default, value: goalAssets.count)
                
                Button(action: {
                    showingAddAsset = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Asset")
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .navigationTitle("Goal Details")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task {
            await updateValues()
        }
        .onChange(of: goalAssets.count) { _, _ in
            Task {
                await updateValues()
            }
        }
        .onChange(of: allTransactions.count) { _, _ in
            Task {
                await updateValues()
            }
        }
#if os(macOS)
        .popover(isPresented: $showingAddAsset) {
            AddAssetView(goal: goal)
                .frame(minWidth: 400, minHeight: 300)
        }
#else
        .sheet(isPresented: $showingAddAsset) {
            AddAssetView(goal: goal)
        }
#endif
    }
    
    private func updateValues() async {
        var total: Double = 0
        
        for asset in goalAssets {
            let assetTransactions = allTransactions.filter { $0.asset.id == asset.id }
            let assetAmount = assetTransactions.reduce(0) { $0 + $1.amount }
            
            if asset.currency == goal.currency {
                total += assetAmount
            } else {
                do {
                    let rate = try await ExchangeRateService.shared.fetchRate(from: asset.currency, to: goal.currency)
                    total += assetAmount * rate
                } catch {
                    total += assetAmount
                }
            }
        }
        
        let prog = goal.targetAmount > 0 ? min(total / goal.targetAmount, 1.0) : 0
        
        await MainActor.run {
            currentTotal = total
            progress = prog
        }
    }
    
    private func deleteAssets(offsets: IndexSet) {
        withAnimation(.default) {
            for index in offsets {
                modelContext.delete(goalAssets[index])
            }
            try? modelContext.save()
        }
    }
}


#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Sample Goal", currency: "USD", targetAmount: 10000.0, deadline: Date().addingTimeInterval(86400 * 30))
    container.mainContext.insert(goal)
    
    return NavigationView {
        GoalDetailView(goal: goal)
    }
    .modelContainer(container)
}
