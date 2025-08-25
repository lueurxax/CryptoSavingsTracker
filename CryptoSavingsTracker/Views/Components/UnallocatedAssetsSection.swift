//
//  UnallocatedAssetsSection.swift
//  CryptoSavingsTracker
//

import SwiftUI
import SwiftData

struct UnallocatedAssetsSection: View {
    @Query private var assets: [Asset]
    @State private var showingAllocationView = false
    @State private var selectedAsset: Asset? = nil
    
    private var unallocatedAssets: [(asset: Asset, unallocatedPercentage: Double, unallocatedValue: Double)] {
        assets.compactMap { asset in
            let totalAllocated = asset.allocations.reduce(0) { $0 + $1.percentage }
            let unallocatedPercentage = max(0, 1.0 - totalAllocated)
            
            if unallocatedPercentage > 0 {
                // Calculate total balance (manual + on-chain)
                let manualBalance = asset.transactions.reduce(0) { $0 + $1.amount }
                let unallocatedValue = manualBalance * unallocatedPercentage
                
                return (asset, unallocatedPercentage, unallocatedValue)
            }
            return nil
        }
    }
    
    var body: some View {
        if !unallocatedAssets.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Section header
                HStack {
                    Label("Unallocated Assets", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundColor(.orange)
                    
                    Spacer()
                    
                    Text("\(unallocatedAssets.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
                
                // Info message
                Text("These assets have unallocated portions. Assign them to goals to track progress accurately.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                // Asset cards
                ForEach(unallocatedAssets, id: \.asset.id) { item in
                    UnallocatedAssetCard(
                        asset: item.asset,
                        unallocatedPercentage: item.unallocatedPercentage,
                        unallocatedValue: item.unallocatedValue
                    ) {
                        selectedAsset = item.asset
                        showingAllocationView = true
                    }
                }
            }
            .padding(.vertical)
            .background(Color.orange.opacity(0.05))
            .cornerRadius(12)
            .sheet(isPresented: $showingAllocationView) {
                if let asset = selectedAsset {
                    AssetSharingView(asset: asset)
                }
            }
        }
    }
}

struct UnallocatedAssetCard: View {
    let asset: Asset
    let unallocatedPercentage: Double
    let unallocatedValue: Double
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(asset.currency)
                            .font(.headline)
                        
                        Text("• \(Int(unallocatedPercentage * 100))% unallocated")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    if let address = asset.address {
                        Text(address)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    Text("\(unallocatedValue, specifier: "%.4f") \(asset.currency) available")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.orange)
                        .imageScale(.large)
                    
                    Text("Allocate")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .background(Color.white.opacity(0.8))
            .cornerRadius(10)
            .shadow(radius: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)
    }
}