// Extracted preview-only declarations for NAV003 policy compliance.
// Source: SimpleStackedBarView.swift

//
//  SimpleStackedBarView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

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
