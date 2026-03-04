//
//  PlanHistoryDetailView.swift
//  CryptoSavingsTracker
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
private let windowBackground = Color(NSColor.windowBackgroundColor)
#else
import UIKit
private let windowBackground = Color(.systemBackground)
#endif

private struct HistoryEventEntry: Identifiable {
    var id: UUID { event.eventId }
    let event: CompletionEvent
    let record: MonthlyExecutionRecord
    let snapshot: CompletedExecution?
}

struct PlanHistoryDetailView: View {
    let monthLabel: String
    let modelContext: ModelContext

    @State private var entries: [HistoryEventEntry] = []
    @State private var showUndoAlert = false
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection
                if canUndoLatest {
                    undoBanner
                }
                summarySection
                timelineSection
            }
            .padding()
        }
        .navigationTitle(formatMonthLabel(monthLabel))
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .alert("Undo Completion?", isPresented: $showUndoAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Undo") {
                Task {
                    await undoLatestCompletion()
                }
            }
        } message: {
            Text("This will reopen this month for tracking.")
        }
    }

    private var latestEntry: HistoryEventEntry? {
        entries.first
    }

    private var latestOpenEntry: HistoryEventEntry? {
        entries.first(where: { $0.event.undoneAt == nil })
    }

    private var canUndoLatest: Bool {
        guard let latestOpenEntry else { return false }
        return latestOpenEntry.record.canUndo
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar")
                Text(formatMonthLabel(monthLabel))
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            if let completedAt = latestEntry?.event.completedAt {
                Text("Latest completion: \(completedAt, format: .dateTime.month().day().year())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(windowBackground)
        .cornerRadius(12)
    }

    private var undoBanner: some View {
        HStack {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundStyle(AccessibleColors.warning)
            Text("Undo available for latest completion")
                .font(.subheadline)
            Spacer()
            Button("Undo") {
                showUndoAlert = true
            }
            .buttonStyle(.borderedProminent)
            .tint(AccessibleColors.warning)
        }
        .padding()
        .background(AccessibleColors.warningBackground)
        .cornerRadius(12)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)
            let required = latestEntry?.snapshot?.goalSnapshots.reduce(0, { $0 + $1.plannedAmount }) ?? 0
            let actual = latestEntry?.snapshot?.contributedTotalsByGoalId.values.reduce(0, +) ?? 0
            Text("Planned: \(formatCurrency(required))")
            Text("Actual: \(formatCurrency(actual))")
            Text("Events: \(entries.count)")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(windowBackground)
        .cornerRadius(12)
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completion Events")
                .font(.headline)
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.event.completedAt, format: .dateTime.month().day().year().hour().minute())
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Sequence: \(entry.event.sequence)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(statusText(for: entry))
                        .font(.caption)
                        .foregroundStyle(statusColor(for: entry))
                    let required = entry.snapshot?.goalSnapshots.reduce(0, { $0 + $1.plannedAmount }) ?? 0
                    let actual = entry.snapshot?.contributedTotalsByGoalId.values.reduce(0, +) ?? 0
                    Text("Planned \(formatCurrency(required)) · Actual \(formatCurrency(actual))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(windowBackground)
                .cornerRadius(10)
            }
        }
        .padding()
        .background(windowBackground)
        .cornerRadius(12)
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let service = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            let events = try service.getCompletionEvents(limit: 500)
            entries = events
                .filter { $0.monthLabel == monthLabel }
                .compactMap { event in
                    guard let record = event.executionRecord else { return nil }
                    return HistoryEventEntry(event: event, record: record, snapshot: event.completionSnapshot)
                }
                .sorted {
                    if $0.event.sequence == $1.event.sequence {
                        return $0.event.completedAt > $1.event.completedAt
                    }
                    return $0.event.sequence > $1.event.sequence
                }
        } catch {
            print("Error loading month history: \(error)")
        }
    }

    private func undoLatestCompletion() async {
        guard let latestOpenEntry else { return }
        do {
            let service = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            try service.undoCompletion(latestOpenEntry.record)
            await loadData()
        } catch {
            print("Error undoing completion: \(error)")
        }
    }

    private func formatMonthLabel(_ label: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM"
        if let date = formatter.date(from: label) {
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
        return label
    }

    private func formatCurrency(_ value: Double) -> String {
        let number = NumberFormatter()
        number.numberStyle = .currency
        number.currencyCode = "USD"
        number.maximumFractionDigits = 2
        return number.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private func statusText(for entry: HistoryEventEntry) -> String {
        if let undoneAt = entry.event.undoneAt {
            return "Undone at \(undoneAt.formatted(date: .abbreviated, time: .shortened))"
        }

        if let latestOpenEntry, latestOpenEntry.id == entry.id {
            return latestOpenEntry.record.canUndo ? "Undo available" : "Undo expired"
        }

        return "Completed"
    }

    private func statusColor(for entry: HistoryEventEntry) -> Color {
        if entry.event.undoneAt != nil {
            return AccessibleColors.warning
        }
        if let latestOpenEntry, latestOpenEntry.id == entry.id, latestOpenEntry.record.canUndo {
            return .blue
        }
        return AccessibleColors.success
    }
}
