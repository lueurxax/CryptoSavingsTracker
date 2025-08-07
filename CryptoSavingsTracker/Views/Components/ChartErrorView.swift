//
//  ChartErrorView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

struct ChartErrorView: View {
    let error: ChartError
    let canRetry: Bool
    let onRetry: () -> Void
    
    @State private var isRetrying = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Error Icon
            Image(systemName: errorIcon)
                .font(.system(size: 48))
                .foregroundColor(AccessibleColors.error)
                .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                // Error Title
                Text(errorTitle)
                    .font(.headline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                
                // Error Description
                if let description = error.errorDescription {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.accessibleSecondary)
                        .multilineTextAlignment(.center)
                }
                
                // Recovery Suggestion
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundColor(.accessibleSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            
            // Action Buttons
            VStack(spacing: 8) {
                if canRetry {
                    Button(action: {
                        isRetrying = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onRetry()
                            isRetrying = false
                        }
                    }) {
                        HStack(spacing: 8) {
                            if isRetrying {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Try Again")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AccessibleColors.primaryInteractive)
                        .cornerRadius(8)
                    }
                    .disabled(isRetrying)
                    .accessibilityLabel("Retry loading chart data")
                    .accessibilityHint(error.recoverySuggestion ?? "Attempt to reload the chart")
                }
                
                if let helpAnchor = error.helpAnchor {
                    Button("Learn More") {
                        // TODO: Implement help system navigation
                        print("Navigate to help: \(helpAnchor)")
                    }
                    .font(.caption)
                    .foregroundColor(.accessiblePrimary)
                    .accessibilityLabel("Get help with this error")
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(AccessibleColors.lightBackground)
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chart error: \(errorTitle)")
        .accessibilityValue(error.errorDescription ?? "")
    }
    
    private var errorIcon: String {
        switch error {
        case .dataUnavailable:
            return "chart.line.uptrend.xyaxis.circle"
        case .networkError:
            return "wifi.slash"
        case .conversionError:
            return "arrow.left.arrow.right.circle"
        case .calculationError:
            return "exclamationmark.triangle"
        case .invalidDateRange:
            return "calendar.badge.exclamationmark"
        case .insufficientData:
            return "chart.bar.doc.horizontal"
        }
    }
    
    private var errorTitle: String {
        switch error {
        case .dataUnavailable:
            return "No Data Available"
        case .networkError:
            return "Connection Error"
        case .conversionError:
            return "Currency Conversion Failed"
        case .calculationError:
            return "Calculation Error"
        case .invalidDateRange:
            return "Invalid Date Range"
        case .insufficientData:
            return "Insufficient Data"
        }
    }
}

// MARK: - Compact Error View for smaller spaces
struct CompactChartErrorView: View {
    let error: ChartError
    let onRetry: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AccessibleColors.warning)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Chart Error")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(error.errorDescription ?? "Unknown error")
                    .font(.caption2)
                    .foregroundColor(.accessibleSecondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if let onRetry = onRetry {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.accessiblePrimary)
                }
                .accessibilityLabel("Retry")
            }
        }
        .padding(12)
        .background(AccessibleColors.warningBackground)
        .cornerRadius(8)
    }
}

#Preview("Chart Error View") {
    VStack(spacing: 20) {
        ChartErrorView(
            error: .dataUnavailable("No transactions found"),
            canRetry: true,
            onRetry: {}
        )
        
        ChartErrorView(
            error: .networkError("Unable to fetch exchange rates"),
            canRetry: true,
            onRetry: {}
        )
        
        CompactChartErrorView(
            error: .insufficientData(minimum: 5, actual: 2),
            onRetry: {}
        )
    }
    .padding()
}