//
//  StackedBarChartView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

// Wrapper that uses SimpleStackedBarView for broader compatibility
struct StackedBarChartView: View {
    let assetCompositions: [AssetComposition]
    let totalValue: Double
    let currency: String
    let showPercentages: Bool
    let showLegend: Bool
    let animateOnAppear: Bool
    
    init(
        assetCompositions: [AssetComposition],
        totalValue: Double,
        currency: String,
        showPercentages: Bool = true,
        showLegend: Bool = true,
        animateOnAppear: Bool = true
    ) {
        self.assetCompositions = assetCompositions
        self.totalValue = totalValue
        self.currency = currency
        self.showPercentages = showPercentages
        self.showLegend = showLegend
        self.animateOnAppear = animateOnAppear
    }
    
    var body: some View {
        SimpleStackedBarView(
            assetCompositions: assetCompositions,
            totalValue: totalValue,
            currency: currency,
            showPercentages: showPercentages,
            showLegend: showLegend
        )
    }
}

// Compact donut chart version
struct CompactAssetCompositionView: View {
    let assetCompositions: [AssetComposition]
    let size: CGFloat
    
    private let colors: [Color] = [.blue, .green, .orange, .purple, .red, .yellow, .pink, .mint]
    
    private var sortedAssets: [AssetComposition] {
        assetCompositions
            .filter { $0.value > 0 } // Only include assets with positive values
            .sorted { $0.value > $1.value }
    }
    
    var body: some View {
        ZStack {
            // Donut slices with hover tooltips for desktop
            ForEach(Array(sortedAssets.enumerated()), id: \.element.currency) { index, asset in
                let startAngle = angle(for: index)
                let endAngle = angle(for: index + 1)
                
                let slicePath = Path { path in
                    path.addArc(
                        center: CGPoint(x: size/2, y: size/2),
                        radius: size/2 - 10,
                        startAngle: startAngle,
                        endAngle: endAngle,
                        clockwise: false
                    )
                    
                    path.addLine(to: CGPoint(
                        x: size/2 + cos(endAngle.radians) * (size/4),
                        y: size/2 + sin(endAngle.radians) * (size/4)
                    ))
                    
                    path.addArc(
                        center: CGPoint(x: size/2, y: size/2),
                        radius: size/4,
                        startAngle: endAngle,
                        endAngle: startAngle,
                        clockwise: true
                    )
                    
                    path.closeSubpath()
                }
                
                #if os(macOS)
                HoverTooltipView(
                    title: asset.currency,
                    value: "\(String(format: "%.2f", asset.value))",
                    description: "\(String(format: "%.1f", asset.percentage))% of portfolio"
                ) {
                    slicePath.fill(asset.color)
                }
                #else
                slicePath.fill(asset.color)
                #endif
            }
            
            // Center content
            VStack(spacing: 2) {
                Text("\(sortedAssets.count)")
                    .font(.system(size: size * 0.15, weight: .bold, design: .rounded))
                Text("Assets")
                    .font(.system(size: size * 0.08))
                    .foregroundColor(.accessibleSecondary)
            }
        }
        .frame(width: size, height: size)
    }
    
    private func angle(for index: Int) -> Angle {
        let percentageUpToIndex = sortedAssets.prefix(index).reduce(0) { $0 + $1.percentage }
        return Angle.degrees(Double(percentageUpToIndex) * 3.6 - 90)
    }
}

#Preview("Stacked Bar Chart") {
    let sampleAssets = [
        AssetComposition(currency: "BTC", value: 5000, percentage: 50, color: .orange),
        AssetComposition(currency: "ETH", value: 2000, percentage: 20, color: .blue),
        AssetComposition(currency: "ADA", value: 1500, percentage: 15, color: .green),
        AssetComposition(currency: "SOL", value: 1000, percentage: 10, color: .purple),
        AssetComposition(currency: "DOT", value: 500, percentage: 5, color: .pink)
    ]
    
    return VStack(spacing: 20) {
        StackedBarChartView(
            assetCompositions: sampleAssets,
            totalValue: 10000,
            currency: "USD"
        )
        
        HStack(spacing: 20) {
            CompactAssetCompositionView(assetCompositions: sampleAssets, size: 100)
            CompactAssetCompositionView(assetCompositions: sampleAssets, size: 80)
            CompactAssetCompositionView(assetCompositions: sampleAssets, size: 60)
        }
    }
    .padding()
}