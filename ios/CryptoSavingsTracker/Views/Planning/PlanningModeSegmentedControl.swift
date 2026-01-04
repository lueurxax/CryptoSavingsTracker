//
//  PlanningModeSegmentedControl.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 03/01/2026.
//

import SwiftUI

/// Segmented control for switching between Per Goal and Fixed Budget planning modes
struct PlanningModeSegmentedControl: View {
    @Binding var selectedMode: PlanningMode

    var body: some View {
        Picker("Planning Mode", selection: $selectedMode) {
            ForEach(PlanningMode.allCases, id: \.self) { mode in
                Text(mode.displayName)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Planning mode")
        .accessibilityHint("Select between Per Goal and Fixed Budget planning modes")
    }
}

/// Standalone view for help tooltip about planning modes
struct PlanningModeHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Per Goal", systemImage: "target")
                            .font(.headline)
                        Text("Calculate individual monthly requirements for each goal based on its target and deadline.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Fixed Budget", systemImage: "dollarsign.circle")
                            .font(.headline)
                        Text("Set one monthly savings amount and we optimize which goals to fund first based on deadlines.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("When to use Fixed Budget mode:")
                            .font(.headline)
                        Text("Perfect for users with fixed salaries who want predictable monthly payments instead of variable amounts based on each goal's timeline.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Planning Modes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        PlanningModeSegmentedControl(selectedMode: .constant(.perGoal))
            .padding()

        PlanningModeSegmentedControl(selectedMode: .constant(.fixedBudget))
            .padding()
    }
}
