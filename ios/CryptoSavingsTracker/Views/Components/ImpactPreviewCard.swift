//
//  ImpactPreviewCard.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI

struct ImpactPreviewCard: View {
    let impact: GoalImpact
    let currency: String
    
    @State private var animatedOldProgress: Double = 0
    @State private var animatedNewProgress: Double = 0
    
    init(impact: GoalImpact, currency: String = "USD") {
        self.impact = impact
        self.currency = currency
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: impact.isPositiveChange ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                    .foregroundColor(impact.isPositiveChange ? AccessibleColors.success : AccessibleColors.warning)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Impact Preview")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Text(impact.isPositiveChange ? "Positive change" : "Requires attention")
                        .font(.caption)
                        .foregroundColor(impact.isPositiveChange ? AccessibleColors.success : AccessibleColors.warning)
                }
                
                Spacer()
            }
            
            // Progress Comparison
            VStack(spacing: 12) {
                HStack {
                    Text("Progress")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
                
                HStack(spacing: 20) {
                    // Before
                    VStack(spacing: 8) {
                        Text("Before")
                            .font(.caption)
                            .foregroundColor(.accessibleSecondary)
                        
                        CircularProgressView(
                            progress: animatedOldProgress,
                            size: 60,
                            lineWidth: 6,
                            color: AccessibleColors.chartColor(at: 1)
                        )
                        
                        Text("\(Int(impact.oldProgress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .contentTransition(.numericText())
                    }
                    
                    // Arrow
                    Image(systemName: "arrow.right")
                        .foregroundColor(.accessibleSecondary)
                        .font(.title2)
                    
                    // After
                    VStack(spacing: 8) {
                        Text("After")
                            .font(.caption)
                            .foregroundColor(.accessibleSecondary)
                        
                        CircularProgressView(
                            progress: animatedNewProgress,
                            size: 60,
                            lineWidth: 6,
                            color: impact.isPositiveChange ? AccessibleColors.success : AccessibleColors.warning
                        )
                        
                        Text("\(Int(impact.newProgress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .contentTransition(.numericText())
                    }
                }
            }
            
            // Key Changes
            VStack(spacing: 8) {
                if abs(impact.targetAmountChange) > 0.01 {
                    ChangeRow(
                        title: "Target Amount",
                        oldValue: String(format: "%.2f %@", impact.oldTargetAmount, currency),
                        newValue: String(format: "%.2f %@", impact.newTargetAmount, currency),
                        isPositive: impact.targetAmountChange > 0
                    )
                }
                
                if abs(impact.dailyTargetChange) > 0.01 {
                    ChangeRow(
                        title: "Daily Target",
                        oldValue: String(format: "%.2f %@", impact.oldDailyTarget, currency),
                        newValue: String(format: "%.2f %@", impact.newDailyTarget, currency),
                        isPositive: impact.dailyTargetChange < 0 // Less daily target is better
                    )
                }
                
                if impact.daysRemainingChange != 0 {
                    ChangeRow(
                        title: "Days Remaining",
                        oldValue: "\(impact.oldDaysRemaining) days",
                        newValue: "\(impact.newDaysRemaining) days",
                        isPositive: impact.daysRemainingChange > 0 // More days is better
                    )
                }
            }
            
            // Warning if significant negative change
            if !impact.isPositiveChange && impact.significantChange {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AccessibleColors.warning)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Significant Change")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Text(getWarningMessage())
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AccessibleColors.warningBackground)
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(12)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0)) {
                animatedOldProgress = impact.oldProgress
            }
            
            withAnimation(.easeInOut(duration: 1.0).delay(0.3)) {
                animatedNewProgress = impact.newProgress
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Impact preview showing changes to your goal")
        .accessibilityValue(getAccessibilityDescription())
    }
    
    private func getWarningMessage() -> String {
        if impact.dailyTargetChange > 50 {
            return "Daily target increased significantly. Consider adjusting your deadline."
        } else if impact.progressChange < -0.2 {
            return "Progress percentage will decrease substantially."
        } else if impact.daysRemainingChange < -30 {
            return "Deadline moved much closer. Ensure the new timeline is realistic."
        } else {
            return "Review the changes carefully before saving."
        }
    }
    
    private func getAccessibilityDescription() -> String {
        let progressChange = Int((impact.newProgress - impact.oldProgress) * 100)
        let dailyChange = impact.newDailyTarget - impact.oldDailyTarget
        
        var description = "Progress will change by \(progressChange) percentage points. "
        description += String(format: "Daily target will change by %.2f %@. ", dailyChange, currency)
        
        if impact.isPositiveChange {
            description += "This is a positive change."
        } else {
            description += "This change requires attention."
        }
        
        return description
    }
}

// MARK: - Supporting Views
struct ChangeRow: View {
    let title: String
    let oldValue: String
    let newValue: String
    let isPositive: Bool
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.accessibleSecondary)
            
            Spacer()
            
            HStack(spacing: 8) {
                Text(oldValue)
                    .font(.caption)
                    .strikethrough()
                    .foregroundColor(.accessibleSecondary)
                
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.accessibleSecondary)
                
                Text(newValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isPositive ? AccessibleColors.success : AccessibleColors.warning)
            }
        }
    }
}

struct CircularProgressView: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Positive change example
        ImpactPreviewCard(
            impact: GoalImpact(
                oldProgress: 0.45,
                newProgress: 0.60,
                oldDailyTarget: 75.0,
                newDailyTarget: 50.0,
                oldDaysRemaining: 120,
                newDaysRemaining: 150,
                oldTargetAmount: 5000,
                newTargetAmount: 5000,
                significantChange: true
            ),
            currency: "USD"
        )
        
        // Negative change example
        ImpactPreviewCard(
            impact: GoalImpact(
                oldProgress: 0.60,
                newProgress: 0.40,
                oldDailyTarget: 50.0,
                newDailyTarget: 100.0,
                oldDaysRemaining: 150,
                newDaysRemaining: 90,
                oldTargetAmount: 5000,
                newTargetAmount: 8000,
                significantChange: true
            ),
            currency: "USD"
        )
    }
    .padding()
}