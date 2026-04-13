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
    @State private var viewState: ViewState = .idle

    var body: some View {
        AsyncContentView(state: viewState) {
            if entries.isEmpty {
                EmptyStateView(
                    icon: "clock.badge.questionmark",
                    title: PlanHistoryPresentation.detailEmptyStateTitle(monthLabel: monthLabel),
                    description: PlanHistoryPresentation.detailEmptyStateDescription(monthLabel: monthLabel),
                    primaryAction: EmptyStateAction(
                        title: "Refresh",
                        icon: "arrow.clockwise",
                        accessibilityIdentifier: "planning.history.detail.empty.refresh.\(monthLabel)"
                    ) {
                        Task {
                            await loadData()
                        }
                    }
                )
            } else {
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
                .refreshable {
                    await loadData()
                }
            }
        } loading: {
            ProgressView("Loading history details...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } error: { error in
            ErrorStateView(error: error) {
                await loadData()
            }
        }
        .navigationTitle(formatMonthLabel(monthLabel))
        .task {
            await loadData()
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

    private var latestRequiredTotal: Double {
        latestEntry?.snapshot?.goalSnapshots.reduce(0, { $0 + $1.plannedAmount }) ?? 0
    }

    private var latestActualTotal: Double {
        latestEntry?.snapshot?.contributedTotalsByGoalId.values.reduce(0, +) ?? 0
    }

    private var historyCurrency: String {
        latestEntry?.snapshot?.goalSnapshots.first?.currency ?? "USD"
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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("planning.history.detail.header.\(monthLabel)")
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
            .accessibilityLabel("Undo latest completion")
            .accessibilityHint("Reopens this month for tracking if the undo window is still active.")
            .accessibilityIdentifier("planning.history.detail.undo")
        }
        .padding()
        .background(AccessibleColors.warningBackground)
        .cornerRadius(12)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)
            Text("Planned: \(formatCurrency(latestRequiredTotal))")
            Text("Actual: \(formatCurrency(latestActualTotal))")
            Text("Events: \(entries.count)")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(windowBackground)
        .cornerRadius(12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Summary")
        .accessibilityValue(
            PlanHistoryPresentation.detailSummaryAccessibilityValue(
                actualTotal: latestActualTotal,
                requiredTotal: latestRequiredTotal,
                eventsCount: entries.count,
                currency: historyCurrency
            )
        )
        .accessibilityIdentifier("planning.history.detail.summary.\(monthLabel)")
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completion Events")
                .font(.headline)
            ForEach(entries) { entry in
                let required = entry.snapshot?.goalSnapshots.reduce(0, { $0 + $1.plannedAmount }) ?? 0
                let actual = entry.snapshot?.contributedTotalsByGoalId.values.reduce(0, +) ?? 0
                let status = statusText(for: entry)

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.event.completedAt, format: .dateTime.month().day().year().hour().minute())
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Sequence: \(entry.event.sequence)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(statusColor(for: entry))
                    Text("Planned \(formatCurrency(required)) · Actual \(formatCurrency(actual))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(windowBackground)
                .cornerRadius(10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    PlanHistoryPresentation.timelineAccessibilityLabel(
                        completedAt: entry.event.completedAt,
                        sequence: entry.event.sequence,
                        status: status,
                        actualTotal: actual,
                        requiredTotal: required,
                        currency: historyCurrency
                    )
                )
                .accessibilityIdentifier("planning.history.detail.event.\(entry.event.eventId.uuidString)")
            }
        }
        .padding()
        .background(windowBackground)
        .cornerRadius(12)
    }

    private func loadData() async {
        viewState = .loading

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
            viewState = .loaded
        } catch {
            entries = []
            viewState = .error(PlanHistoryPresentation.detailLoadError(monthLabel: monthLabel))
            AppLog.error(
                "Failed to load history for \(monthLabel): \(error.localizedDescription)",
                category: .monthlyPlanning
            )
        }
    }

    private func undoLatestCompletion() async {
        guard let latestOpenEntry else { return }
        do {
            let service = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            try service.undoCompletion(latestOpenEntry.record)
            await loadData()
        } catch {
            AppLog.error(
                "Failed to undo completion for \(monthLabel): \(error.localizedDescription)",
                category: .monthlyPlanning
            )
        }
    }

    private func formatMonthLabel(_ label: String) -> String {
        PlanHistoryPresentation.monthTitle(from: label)
    }

    private func formatCurrency(_ value: Double) -> String {
        CurrencyFormatter.format(amount: value, currency: historyCurrency, maximumFractionDigits: 2)
    }

    private func statusText(for entry: HistoryEventEntry) -> String {
        PlanHistoryPresentation.eventStatusText(
            undoneAt: entry.event.undoneAt,
            isLatestOpen: latestOpenEntry?.id == entry.id,
            canUndo: latestOpenEntry?.record.canUndo ?? false
        )
    }

    private func statusColor(for entry: HistoryEventEntry) -> Color {
        if entry.event.undoneAt != nil {
            return AccessibleColors.warning
        }
        if let latestOpenEntry, latestOpenEntry.id == entry.id, latestOpenEntry.record.canUndo {
            return AccessibleColors.primaryInteractive
        }
        return AccessibleColors.success
    }
}
