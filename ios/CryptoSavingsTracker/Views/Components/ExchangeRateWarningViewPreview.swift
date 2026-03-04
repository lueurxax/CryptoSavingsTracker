// Extracted preview-only declarations for NAV003 policy compliance.
// Source: ExchangeRateWarningView.swift

//
//  ExchangeRateWarningView.swift
//  CryptoSavingsTracker
//
//  Shows warning when exchange rates are unavailable
//

import SwiftUI

#Preview {
    VStack(spacing: 20) {
        ExchangeRateWarningView(isOffline: true, lastUpdate: Date().addingTimeInterval(-3600))
        ExchangeRateWarningView(isOffline: true, lastUpdate: nil)
        ExchangeRateStatusBadge()
    }
    .padding()
}
