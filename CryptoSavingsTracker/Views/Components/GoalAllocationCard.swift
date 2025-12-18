//
//  GoalAllocationCard.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct GoalAllocationCard: View {
    let goal: Goal
    /// Fixed allocation amount in the asset's native currency
    @Binding var allocation: Double
    let assetCurrency: String
    let assetBalance: Double
    let remainingAmount: Double
    let onAllocateRemaining: (() -> Void)?
    
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
                
                // Current allocation amount
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(allocation, specifier: "%.4f") \(assetCurrency)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(allocation > 0 ? .blue : .secondary)
                    Text("of \(assetBalance, specifier: "%.4f") \(assetCurrency)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Amount input
            HStack(spacing: 12) {
                Text("Amount")
                    .font(.callout)
                TextField("0", value: $allocation, format: .number)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("allocGoalAmountField-\(goal.name)")
                Text(assetCurrency)
                    .foregroundColor(.secondary)
                    .font(.callout)
            }

            let epsilon = 0.0000001
            if remainingAmount > epsilon, let onAllocateRemaining {
                Button(action: onAllocateRemaining) {
                    Label(
                        "Allocate Unallocated (\(remainingAmount, specifier: "%.4f") \(assetCurrency))",
                        systemImage: "arrow.down.to.line.compact"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("allocateRemaining-\(goal.name)")
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
}
