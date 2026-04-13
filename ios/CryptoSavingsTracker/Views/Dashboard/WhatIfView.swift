//
//  WhatIfView.swift
//  CryptoSavingsTracker
//
//  Simple what-if simulator for contributions
//

import SwiftUI
import SwiftData

struct WhatIfView: View {
    let goal: Goal
    @ObservedObject var settings: WhatIfSettings
    @State private var currentTotal: Double = 0
    @State private var daysRemaining: Int = 0
    
    private var monthsRemaining: Double {
        max(0, Double(daysRemaining) / 30.0)
    }
    
    private var projectedTotal: Double {
        currentTotal + settings.oneTime + settings.monthly * monthsRemaining
    }
    
    private var onTrack: Bool {
        projectedTotal >= goal.targetAmount
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("What‑If Scenario")
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
                Text(onTrack ? "On Track" : "Behind")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((onTrack ? AccessibleColors.success : AccessibleColors.warning).opacity(0.1))
                    .foregroundColor(onTrack ? AccessibleColors.success : AccessibleColors.warning)
                    .cornerRadius(8)
                    .accessibilityLabel("Scenario status")
                    .accessibilityValue(DashboardAccessibilityCopy.whatIfStatusValue(onTrack: onTrack))
                    .accessibilityHint(DashboardAccessibilityCopy.whatIfStatusHint(onTrack: onTrack))
                    .accessibilityIdentifier("dashboard.what_if.status")
            }
            
            VStack(spacing: 10) {
                Toggle(isOn: $settings.enabled) {
                    Label("Enable Overlay", systemImage: "wand.and.stars")
                }
                .toggleStyle(.switch)
                .accessibilityHint(DashboardAccessibilityCopy.overlayToggleHint(isEnabled: settings.enabled))
                .accessibilityIdentifier("dashboard.what_if.overlay_toggle")
                
                HStack {
                    Image(systemName: "dollarsign.circle")
                        .foregroundColor(.accessiblePrimary)
                    Text("Monthly Contribution")
                        .font(.caption)
                        .foregroundColor(.accessibleSecondary)
                    Spacer()
                    Text(String(format: "%.0f %@", settings.monthly, goal.currency))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Monthly contribution amount")
                        .accessibilityValue(
                            DashboardAccessibilityCopy.contributionValue(
                                amount: settings.monthly,
                                currency: goal.currency,
                                kind: "Monthly contribution"
                            )
                        )
                }
                Slider(value: $settings.monthly, in: 0...1000, step: 25)
                    .accessibilityLabel("Monthly contribution adjustment")
                    .accessibilityHint("Adjusts the recurring monthly contribution used in the projection.")
                    .accessibilityIdentifier("dashboard.what_if.monthly_slider")
                    .accessibilityValue(CurrencyFormatter.accessibilityFormat(amount: settings.monthly, currency: goal.currency))
            }
            
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "creditcard")
                        .foregroundColor(.accessiblePrimary)
                    Text("One‑Time Investment")
                        .font(.caption)
                        .foregroundColor(.accessibleSecondary)
                    Spacer()
                    Text(String(format: "%.0f %@", settings.oneTime, goal.currency))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("One-time investment amount")
                        .accessibilityValue(
                            DashboardAccessibilityCopy.contributionValue(
                                amount: settings.oneTime,
                                currency: goal.currency,
                                kind: "One-time investment"
                            )
                        )
                }
                Slider(value: $settings.oneTime, in: 0...5000, step: 50)
                    .accessibilityLabel("One-time investment adjustment")
                    .accessibilityHint("Adjusts the one-time contribution used in the projection.")
                    .accessibilityIdentifier("dashboard.what_if.one_time_slider")
                    .accessibilityValue(CurrencyFormatter.accessibilityFormat(amount: settings.oneTime, currency: goal.currency))
            }
            
            Divider().padding(.vertical, 4)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Projected Total by Deadline")
                        .font(.caption)
                        .foregroundColor(.accessibleSecondary)
                    Text(String(format: "%.0f %@", projectedTotal, goal.currency))
                        .font(.headline)
                        .fontWeight(.bold)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Days Remaining")
                        .font(.caption)
                        .foregroundColor(.accessibleSecondary)
                    Text("\(daysRemaining)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(daysRemaining < 30 ? AccessibleColors.warning : .primary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Days remaining")
                        .accessibilityValue(DashboardAccessibilityCopy.remainingDaysValue(daysRemaining))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Projected outcome")
            .accessibilityValue(
                DashboardAccessibilityCopy.projectedOutcomeValue(
                    projectedTotal: projectedTotal,
                    currency: goal.currency,
                    daysRemaining: daysRemaining,
                    onTrack: onTrack
                )
            )
            .accessibilityIdentifier("dashboard.what_if.projected_outcome")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(VisualComponentTokens.dashboardCardStroke, lineWidth: 1)
                )
        )
        .cornerRadius(16)
        .task {
            await loadCurrent()
        }
    }
    
    private func loadCurrent() async {
        let calc = DIContainer.shared.goalCalculationService
        let total = await calc.getCurrentTotal(for: goal)
        let days = GoalCalculationService.getDaysRemaining(for: goal)
        await MainActor.run {
            currentTotal = total
            daysRemaining = days
        }
    }
}

// Preview omitted to avoid ambiguous result builder issues in some toolchains.
