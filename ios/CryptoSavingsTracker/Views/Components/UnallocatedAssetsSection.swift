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
            let unallocatedValue = asset.unallocatedAmount
            let balance = asset.currentAmount
            let unallocatedPercentage = balance > 0 ? min(1.0, max(0, unallocatedValue / balance)) : 0
            guard unallocatedValue > 0.0000001 else { return nil }
            return (asset, unallocatedPercentage, unallocatedValue)
        }
    }
    
    var body: some View {
        if !unallocatedAssets.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Section header
                HStack {
                    Label("Unallocated Assets", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundColor(AccessibleColors.warning)
                    
                    Spacer()
                    
                    Text("\(unallocatedAssets.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AccessibleColors.warningBackground)
                        .cornerRadius(8)
                }
                .padding(.horizontal)
                
                // Info message
                Text("These assets have unallocated portions. Use the allocation workspace to allocate this asset to one or more goals.")
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
            .background(AccessibleColors.warningBackground.opacity(0.5))
            .cornerRadius(12)
            // NAV-MOD: MOD-01
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
                            .foregroundColor(AccessibleColors.warning)
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
                        .foregroundColor(AccessibleColors.warning)
                        .imageScale(.large)

                    Text("Allocate")
                        .font(.caption2)
                        .foregroundColor(AccessibleColors.warning)
                }
            }
            .padding()
            .background(AccessibleColors.lightBackground.opacity(0.8))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AccessibleColors.secondaryText.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)
    }
}
