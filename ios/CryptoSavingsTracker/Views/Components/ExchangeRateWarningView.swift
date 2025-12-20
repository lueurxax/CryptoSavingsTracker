//
//  ExchangeRateWarningView.swift
//  CryptoSavingsTracker
//
//  Shows warning when exchange rates are unavailable
//

import SwiftUI

struct ExchangeRateWarningView: View {
    let isOffline: Bool
    let lastUpdate: Date?
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Exchange Rates Unavailable")
                    .font(.caption)
                    .fontWeight(.medium)
                
                if let lastUpdate = lastUpdate {
                    Text("Using cached rates from \(lastUpdate, style: .relative)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Unable to calculate currency conversions")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ExchangeRateStatusBadge: View {
    @State private var hasRates = true
    @State private var lastCheck = Date()
    
    var body: some View {
        Group {
            if !hasRates {
                Label("Rates Unavailable", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .task {
            // Check rate availability periodically
            await checkRateAvailability()
        }
    }
    
    private func checkRateAvailability() async {
        // Check if we have recent cached rates
        let exchangeService = DIContainer.shared.exchangeRateService
        
        // Try to get a test rate
        do {
            _ = try await exchangeService.fetchRate(from: "USD", to: "USD")
            hasRates = true
        } catch {
            hasRates = false
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ExchangeRateWarningView(isOffline: true, lastUpdate: Date().addingTimeInterval(-3600))
        ExchangeRateWarningView(isOffline: true, lastUpdate: nil)
        ExchangeRateStatusBadge()
    }
    .padding()
}