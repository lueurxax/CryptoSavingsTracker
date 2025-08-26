//
//  GoalAllocationCard.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct GoalAllocationCard: View {
    let goal: Goal
    @Binding var allocation: Double
    
    var body: some View {
        VStack(spacing: 12) {
            // Goal header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.name)
                        .font(.headline)
                    Text("Target: \(goal.currency) \(Int(goal.targetAmount))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Current allocation
                VStack(alignment: .trailing) {
                    Text("\(Int(allocation * 100))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(allocation > 0 ? .blue : .secondary)
                    
                    if allocation > 0 {
                        Text("allocated")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            // Slider
            AllocationSlider(allocation: $allocation, goalName: goal.name)
            
            // Quick percentage buttons
            QuickPercentageButtons(allocation: $allocation)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
}

struct AllocationSlider: View {
    @Binding var allocation: Double
    let goalName: String
    
    var body: some View {
        Slider(
            value: $allocation,
            in: 0...1,
            step: 0.05
        ) { _ in
            #if os(iOS)
            HapticManager.shared.selection()
            #endif
        }
        .tint(.blue)
        .accessibilityLabel("Allocation for \(goalName)")
        .accessibilityValue("\(Int(allocation * 100)) percent")
    }
}

struct QuickPercentageButtons: View {
    @Binding var allocation: Double
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach([0, 25, 50, 75, 100], id: \.self) { percent in
                Button(action: {
                    allocation = Double(percent) / 100.0
                    #if os(iOS)
                    HapticManager.shared.impact(.light)
                    #endif
                }) {
                    Text("\(percent)%")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(allocation == Double(percent) / 100.0 ? .blue : .gray)
            }
        }
    }
}