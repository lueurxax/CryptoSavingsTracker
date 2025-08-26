//
//  SharedAssetIndicator.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 25/08/2025.
//

import SwiftUI
import SwiftData

struct SharedAssetIndicator: View {
    let asset: Asset
    let currentGoal: Goal
    
    private var isShared: Bool {
        asset.allocations.count > 1
    }
    
    private var allocationPercentage: Double {
        asset.getAllocationPercentage(for: currentGoal)
    }
    
    private var otherGoalsCount: Int {
        asset.allocations.compactMap { $0.goal }.filter { $0.id != currentGoal.id }.count
    }
    
    var body: some View {
        if isShared {
            HStack(spacing: 4) {
                Image(systemName: "chart.pie.fill")
                    .font(.caption2)
                    .foregroundColor(.purple)
                
                Text("\(Int(allocationPercentage * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.purple)
                
                if otherGoalsCount > 0 {
                    Text("• Shared with \(otherGoalsCount) other goal\(otherGoalsCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.1))
            .cornerRadius(6)
        }
    }
}

// Asset row view with shared indicator
struct AssetListItemView: View {
    let asset: Asset
    let goal: Goal
    @State private var currentBalance: Double = 0
    
    private var effectiveBalance: Double {
        let totalBalance = currentBalance
        let percentage = asset.getAllocationPercentage(for: goal)
        return totalBalance * percentage
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.currency)
                        .font(.headline)
                    
                    if asset.allocations.count > 1 {
                        SharedAssetIndicator(asset: asset, currentGoal: goal)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    if asset.allocations.count > 1 {
                        // Show allocated amount
                        Text("\(effectiveBalance, specifier: "%.4f") \(asset.currency)")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Text("of \(currentBalance, specifier: "%.4f") total")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        // Show full amount
                        Text("\(currentBalance, specifier: "%.4f") \(asset.currency)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
            
            if let address = asset.address {
                Text(address)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .task {
            await loadBalance()
        }
    }
    
    private func loadBalance() async {
        // Get manual balance
        let manualBalance = asset.transactions.reduce(0) { $0 + $1.amount }
        
        // Get on-chain balance if available
        if let chainId = asset.chainId, let address = asset.address {
            let balanceService = DIContainer.shared.balanceService
            
            do {
                let onChainBalance = try await balanceService.fetchBalance(
                    chainId: chainId,
                    address: address,
                    symbol: asset.currency,
                    forceRefresh: false
                )
                await MainActor.run {
                    currentBalance = onChainBalance + manualBalance
                }
            } catch {
                await MainActor.run {
                    currentBalance = manualBalance
                }
            }
        } else {
            await MainActor.run {
                currentBalance = manualBalance
            }
        }
    }
}

struct SharedAssetIndicator_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, AssetAllocation.self, configurations: config)
        
        let goal = Goal(name: "Test Goal", currency: "USD", targetAmount: 10000, deadline: Date().addingTimeInterval(86400 * 30))
        let asset = Asset(currency: "BTC")
        
        container.mainContext.insert(goal)
        container.mainContext.insert(asset)
        
        let allocation = AssetAllocation(asset: asset, goal: goal, percentage: 0.5)
        container.mainContext.insert(allocation)
        
        return VStack {
            SharedAssetIndicator(asset: asset, currentGoal: goal)
            AssetListItemView(asset: asset, goal: goal)
        }
        .padding()
        .modelContainer(container)
    }
}
