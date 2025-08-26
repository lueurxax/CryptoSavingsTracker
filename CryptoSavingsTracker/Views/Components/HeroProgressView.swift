//
//  HeroProgressView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

struct HeroProgressView: View {
    let goal: Goal
    @State private var currentTotal: Double = 0
    @State private var progress: Double = 0
    @State private var isLoading = true
    @State private var showingDetails = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    var body: some View {
        VStack(spacing: 0) {
            // Hero Progress Ring - Enhanced Design
            VStack(spacing: 20) {
                // Progress Ring with better visuals
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(Color.gray.opacity(0.15), lineWidth: 16)
                        .frame(width: 180, height: 180)
                    
                    // Progress ring with shadow
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            progressGradient,
                            style: StrokeStyle(lineWidth: 16, lineCap: .round)
                        )
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: progressColor.opacity(0.3), radius: 8, x: 0, y: 4)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: progress)
                    
                    // Center content with better spacing
                    VStack(spacing: 6) {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .contentTransition(.numericText())
                        
                        Text("Complete")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accessibleSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                    }
                }
                .accessibilityLabel("Goal progress")
                .accessibilityValue("\(Int(progress * 100)) percent complete")
                .accessibilityHint("Double tap to see details")
                
                // Key Metrics Row - Always Visible
                HStack(spacing: 24) {
                    // Current Amount
                    VStack(spacing: 4) {
                        Text(formatCurrency(currentTotal))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text("Current")
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                            .textCase(.uppercase)
                            .tracking(0.3)
                    }
                    
                    Divider()
                        .frame(height: 40)
                    
                    // Days Left
                    VStack(spacing: 4) {
                        Text("\(goal.daysRemaining)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(goal.daysRemaining < 30 ? .red : .primary)
                        Text("Days Left")
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                            .textCase(.uppercase)
                            .tracking(0.3)
                    }
                    
                    Divider()
                        .frame(height: 40)
                    
                    // Daily Target
                    VStack(spacing: 4) {
                        Text(formatCurrency(dailyTarget))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text("Per Day")
                            .font(.caption2)
                            .foregroundColor(.accessibleSecondary)
                            .textCase(.uppercase)
                            .tracking(0.3)
                    }
                }
                .padding(.horizontal, 20)
                
                // Quick status message
                statusMessage
                    .padding(.horizontal, 20)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(progressColor.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 8)
            )
            
            // Remove the awkward expandable section - metrics are now always visible above
        }
        .task {
            await updateMetrics()
        }
        .onChange(of: goal.allocations) { _, _ in
            Task {
                await updateMetrics()
            }
        }
    }
    
    private func updateMetrics() async {
        isLoading = true
        
        let calc = DIContainer.shared.goalCalculationService
        let total = await calc.getCurrentTotal(for: goal)
        let prog = await calc.getProgress(for: goal)
        
        await MainActor.run {
            currentTotal = total
            progress = prog
            isLoading = false
        }
    }
    
    private var progressColor: Color {
        if progress >= 0.9 { return .green }
        if progress >= 0.7 { return .blue }
        if progress >= 0.5 { return .orange }
        return .red
    }
    
    private var progressGradient: LinearGradient {
        let colors: [Color] = {
            if progress >= 0.9 { return [.green, .mint] }
            if progress >= 0.7 { return [.blue, .cyan] }
            if progress >= 0.5 { return [.orange, .yellow] }
            return [.red, .pink]
        }()
        
        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var statusMessage: some View {
        Group {
            if progress >= 1.0 {
                Label("🎉 Goal Achieved! Congratulations!", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundColor(.green)
            } else if progress >= 0.9 {
                Label("Almost there! You're doing amazing!", systemImage: "flame.fill")
                    .font(.subheadline)
                    .foregroundColor(.orange)
            } else if progress >= 0.5 {
                Label("Halfway there! Keep up the great work!", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            } else if dailyTarget > 0 {
                Text("Save **\(formatCurrency(dailyTarget))** daily to stay on track")
                    .font(.subheadline)
                    .foregroundColor(.accessibleSecondary)
            } else {
                Text("Ready to start your savings journey!")
                    .font(.subheadline)
                    .foregroundColor(.accessibleSecondary)
            }
        }
    }
    
    private var dailyTarget: Double {
        let remaining = max(goal.targetAmount - currentTotal, 0)
        let days = max(goal.daysRemaining, 1)
        return remaining / Double(days)
    }
    
    private var dailyTargetColor: Color {
        if dailyTarget > currentTotal * 0.1 { return .red }
        if dailyTarget > currentTotal * 0.05 { return .orange }
        return .green
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        if amount >= 1000 {
            return String(format: "%.1fK", amount / 1000)
        }
        return String(format: "%.0f", amount)
    }
}

struct CompactMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.accessibleSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)
    
    let goal = Goal(name: "Emergency Fund", currency: "EUR", targetAmount: 1600, deadline: Date().addingTimeInterval(86400 * 85))
    container.mainContext.insert(goal)
    
    return ScrollView {
        HeroProgressView(goal: goal)
            .padding()
    }
    .modelContainer(container)
}
