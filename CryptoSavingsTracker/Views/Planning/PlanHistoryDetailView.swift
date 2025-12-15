//
//  PlanHistoryDetailView.swift
//  CryptoSavingsTracker
//
//  Created for v2.1 - Monthly Planning Execution & Tracking
//  Shows detailed view of a completed monthly execution record
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
private let windowBackground = Color(NSColor.windowBackgroundColor)
private let controlBackground = Color(NSColor.controlBackgroundColor)
#else
import UIKit
private let windowBackground = Color(.systemBackground)
private let controlBackground = Color(.secondarySystemBackground)
#endif

struct PlanHistoryDetailView: View {
    let record: MonthlyExecutionRecord
    let modelContext: ModelContext

    @State private var contributionCountsByGoal: [UUID: Int] = [:]
    @State private var contributedTotals: [UUID: Double] = [:]
    @State private var overallProgress: Double = 0
    @State private var isLoading = false
    @State private var showUndoAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection

                // Undo banner if available
                if record.canUndo {
                    undoBanner
                }

                // Overall Summary
                summarySection

                // Goals Breakdown
                goalsBreakdownSection

                // Timeline
                timelineSection
            }
            .padding()
        }
        .navigationTitle(formatMonthLabel(record.monthLabel))
        .task {
            await loadData()
        }
        .alert("Undo Completion?", isPresented: $showUndoAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Undo") {
                Task {
                    await undoCompletion()
                }
            }
        } message: {
            Text("This will reopen this month for tracking. You can still add contributions.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: record.status.icon)
                    .font(.title2)
                Text(record.status.displayName)
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if overallProgress >= 100 {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
            }

            if let completedAt = record.completedAt {
                Text("Completed on \(completedAt, format: .dateTime.month().day().year())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(windowBackground)
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Undo Banner

    private var undoBanner: some View {
        HStack {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading) {
                Text("Undo Available")
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let expiresAt = record.canUndoUntil {
                    Text("Expires in \(timeRemaining(until: expiresAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Undo") {
                showUndoAlert = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)

            if let snapshot = record.snapshot {
                VStack(spacing: 16) {
                    // Progress bar
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Overall Progress")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(overallProgress))%")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        let pct = min(max(overallProgress, 0), 100)
                        ProgressView(value: pct, total: 100)
                            .tint(pct >= 100 ? .green : .orange)
                    }

                    // Stats grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        HistoryStatCard(
                            title: "Planned",
                            value: formatCurrency(snapshot.totalPlanned),
                            icon: "target"
                        )

                        HistoryStatCard(
                            title: "Contributed",
                            value: formatCurrency(contributedTotals.values.reduce(0, +)),
                            icon: "arrow.up.circle.fill"
                        )

                        HistoryStatCard(
                            title: "Goals",
                            value: "\(snapshot.activeGoalCount)",
                            icon: "flag.fill"
                        )

                        HistoryStatCard(
                            title: "Fulfilled",
                            value: "\(fulfilledCount)",
                            icon: "checkmark.circle.fill"
                        )
                    }
                }
            }
        }
        .padding()
        .background(windowBackground)
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Goals Breakdown

    private var goalsBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Goals Breakdown")
                .font(.headline)

            if let snapshot = record.snapshot {
                ForEach(snapshot.goalSnapshots, id: \.goalId) { goalSnapshot in
                    GoalHistoryCard(
                        goalSnapshot: goalSnapshot,
                        contributed: contributedTotals[goalSnapshot.goalId] ?? 0,
                        contributionCount: contributionCountsByGoal[goalSnapshot.goalId] ?? 0
                    )
                }
            }
        }
        .padding()
        .background(windowBackground)
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline")
                .font(.headline)

            VStack(alignment: .leading, spacing: 16) {
                TimelineEvent(
                    icon: "plus.circle.fill",
                    title: "Created",
                    date: record.createdAt,
                    color: .blue
                )

                if let startedAt = record.startedAt {
                    TimelineEvent(
                        icon: "play.circle.fill",
                        title: "Started Tracking",
                        date: startedAt,
                        color: .green
                    )
                }

                if let completedAt = record.completedAt {
                    TimelineEvent(
                        icon: "checkmark.circle.fill",
                        title: "Completed",
                        date: completedAt,
                        color: .green
                    )
                }
            }
        }
        .padding()
        .background(windowBackground)
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Computed Properties

    private var fulfilledCount: Int {
        guard let snapshot = record.snapshot else { return 0 }
        return snapshot.goalSnapshots.filter { goalSnapshot in
            let contributed = contributedTotals[goalSnapshot.goalId] ?? 0
            return contributed >= goalSnapshot.plannedAmount
        }.count
    }

    // MARK: - Actions

    private func loadData() async {
        isLoading = true

        do {
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            contributedTotals = try executionService.getContributionTotals(for: record)
            overallProgress = try executionService.calculateProgress(for: record)

            if let completed = record.completedExecution {
                contributionCountsByGoal = completed.contributionSnapshots.reduce(into: [:]) { partial, snapshot in
                    partial[snapshot.goalId, default: 0] += 1
                }
            } else {
                let byGoal = try executionService.getContributionsByGoal(for: record)
                contributionCountsByGoal = byGoal.reduce(into: [:]) { partial, item in
                    partial[item.key] = item.value.count
                }
            }
        } catch {
            print("Error loading data: \(error)")
        }

        isLoading = false
    }

    private func undoCompletion() async {
        do {
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            try executionService.undoCompletion(record)
            // Navigate back
        } catch {
            print("Error undoing completion: \(error)")
        }
    }

    // MARK: - Helpers

    private func formatMonthLabel(_ label: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        if let date = formatter.date(from: label) {
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
        return label
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    private func timeRemaining(until date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Supporting Views

struct HistoryStatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(controlBackground)
        .cornerRadius(8)
    }
}

struct GoalHistoryCard: View {
    let goalSnapshot: ExecutionGoalSnapshot
    let contributed: Double
    let contributionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(goalSnapshot.goalName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if contributed >= goalSnapshot.plannedAmount {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            let total = max(goalSnapshot.plannedAmount, 0.0001)
            let safeContributed = min(max(contributed, 0), total)
            ProgressView(value: safeContributed, total: total)
                .tint(safeContributed >= total ? .green : .orange)

            HStack {
                Text("\(formatCurrency(contributed, currency: goalSnapshot.currency)) / \(formatCurrency(goalSnapshot.plannedAmount, currency: goalSnapshot.currency))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(contributionCount) contributions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(contributed >= goalSnapshot.plannedAmount ? Color.green.opacity(0.1) : controlBackground)
        .cornerRadius(8)
    }

    private func formatCurrency(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(amount)"
    }
}

struct TimelineEvent: View {
    let icon: String
    let title: String
    let date: Date
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(date, format: .dateTime.month().day().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
