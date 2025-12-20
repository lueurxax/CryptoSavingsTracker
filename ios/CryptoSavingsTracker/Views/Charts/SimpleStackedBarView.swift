//
//  SimpleStackedBarView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

struct SimpleStackedBarView: View {
    let assetCompositions: [AssetComposition]
    let totalValue: Double
    let currency: String
    let showPercentages: Bool
    let showLegend: Bool
    
    @State private var selectedAsset: AssetComposition?
    
    init(
        assetCompositions: [AssetComposition],
        totalValue: Double,
        currency: String,
        showPercentages: Bool = true,
        showLegend: Bool = true
    ) {
        self.assetCompositions = assetCompositions
        self.totalValue = totalValue
        self.currency = currency
        self.showPercentages = showPercentages
        self.showLegend = showLegend
    }
    
    private var sortedAssets: [AssetComposition] {
        assetCompositions.sorted { $0.value > $1.value }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Asset Composition")
                        .font(.headline)
                    MetricTooltips.assetComposition
                }
                
                Text("\(String(format: "%.2f", totalValue)) \(currency)")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("\(assetCompositions.count) assets")
                    .font(.caption)
                    .foregroundColor(.accessibleSecondary)
            }
            
            // Horizontal stacked bar
            VStack(spacing: 8) {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(sortedAssets) { asset in
                            let slice = Rectangle()
                                .fill(asset.color)
                                .frame(width: geometry.size.width * (asset.percentage / 100))
                                .onTapGesture {
                                    withAnimation(.spring()) {
                                        selectedAsset = selectedAsset?.id == asset.id ? nil : asset
                                    }
                                }
                            #if os(macOS)
                            HoverTooltipView(
                                title: asset.currency,
                                value: String(format: "%.2f %@", asset.value, currency),
                                description: String(format: "%.1f%% of portfolio", asset.percentage)
                            ) { slice }
                            #else
                            slice
                            #endif
                        }
                    }
                    .frame(height: 40)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .frame(height: 40)
                
                // Vertical bars
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(sortedAssets.prefix(6)) { asset in
                        VStack(spacing: 4) {
                            let bar = Rectangle()
                                .fill(asset.color)
                                .frame(width: 40, height: max(20, asset.percentage * 2))
                                .cornerRadius(4)
                                .onTapGesture {
                                    withAnimation(.spring()) {
                                        selectedAsset = selectedAsset?.id == asset.id ? nil : asset
                                    }
                                }
                            #if os(macOS)
                            HoverTooltipView(
                                title: asset.currency,
                                value: String(format: "%.2f %@", asset.value, currency),
                                description: String(format: "%.1f%% of portfolio", asset.percentage)
                            ) { bar }
                            #else
                            bar
                            #endif
                            
                            Text(asset.currency)
                                .font(.caption2)
                                .foregroundColor(.accessibleSecondary)
                                .rotationEffect(.degrees(-45))
                                .frame(width: 40)
                            
                            if showPercentages {
                                Text("\(String(format: "%.1f", asset.percentage))%")
                                    .font(.caption2)
                                    .foregroundColor(.accessibleSecondary)
                            }
                        }
                    }
                    
                    // Show "others" if there are more than 6 assets
                    if sortedAssets.count > 6 {
                        let othersValue = sortedAssets.dropFirst(6).reduce(0) { $0 + $1.value }
                        let othersPercentage = (othersValue / totalValue) * 100
                        
                        VStack(spacing: 4) {
                            Rectangle()
                                .fill(.gray)
                                .frame(width: 40, height: max(20, othersPercentage * 2))
                                .cornerRadius(4)
                            
                            Text("Others")
                                .font(.caption2)
                                .foregroundColor(.accessibleSecondary)
                                .rotationEffect(.degrees(-45))
                                .frame(width: 40)
                            
                            if showPercentages {
                                Text("\(String(format: "%.1f", othersPercentage))%")
                                    .font(.caption2)
                                    .foregroundColor(.accessibleSecondary)
                            }
                        }
                    }
                }
                .frame(height: 150)
            }
            
            // Asset details
            if let selected = selectedAsset {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(selected.color)
                            .frame(width: 12, height: 12)
                        
                        Text(selected.currency)
                            .font(.headline)
                        
                        Spacer()
                        
                        Button("Dismiss") {
                            withAnimation {
                                selectedAsset = nil
                            }
                        }
                        .font(.caption)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Value:")
                            Spacer()
                            Text("\(String(format: "%.2f", selected.value)) \(currency)")
                                .fontWeight(.medium)
                        }
                        
                        HStack {
                            Text("Percentage:")
                            Spacer()
                            Text("\(String(format: "%.1f", selected.percentage))%")
                                .fontWeight(.medium)
                        }
                    }
                    .font(.caption)
                }
                .padding(12)
                .background(Color.gray.opacity(0.03))
                .cornerRadius(8)
            }
            
            // Legend
            if showLegend {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                    ForEach(sortedAssets.prefix(6)) { asset in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(asset.color)
                                .frame(width: 10, height: 10)
                            
                            Text(asset.currency)
                                .font(.caption)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text("\(String(format: "%.1f", asset.percentage))%")
                                .font(.caption)
                                .foregroundColor(.accessibleSecondary)
                        }
                        .onTapGesture {
                            withAnimation(.spring()) {
                                selectedAsset = selectedAsset?.id == asset.id ? nil : asset
                            }
                        }
                    }
                    
                    // Show "others" if there are more than 6 assets
                    if sortedAssets.count > 6 {
                        let othersValue = sortedAssets.dropFirst(6).reduce(0) { $0 + $1.value }
                        let othersPercentage = (othersValue / totalValue) * 100
                        
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.gray)
                                .frame(width: 10, height: 10)
                            
                            Text("Others (\(sortedAssets.count - 6))")
                                .font(.caption)
                            
                            Spacer()
                            
                            Text("\(String(format: "%.1f", othersPercentage))%")
                                .font(.caption)
                                .foregroundColor(.accessibleSecondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

// Removed UIRectCorner extension for macOS compatibility

#Preview {
    let sampleAssets = [
        AssetComposition(currency: "BTC", value: 5000, percentage: 50, color: .orange),
        AssetComposition(currency: "ETH", value: 2000, percentage: 20, color: .blue),
        AssetComposition(currency: "ADA", value: 1500, percentage: 15, color: .green),
        AssetComposition(currency: "SOL", value: 1000, percentage: 10, color: .purple),
        AssetComposition(currency: "DOT", value: 500, percentage: 5, color: .pink)
    ]
    
    return SimpleStackedBarView(
        assetCompositions: sampleAssets,
        totalValue: 10000,
        currency: "USD"
    )
    .padding()
}
