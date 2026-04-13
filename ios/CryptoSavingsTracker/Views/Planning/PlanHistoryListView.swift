//
//  PlanHistoryListView.swift
//  CryptoSavingsTracker
//

import SwiftUI
import SwiftData

private struct HistoryEventEntry {
    let event: CompletionEvent
    let record: MonthlyExecutionRecord
    let snapshot: CompletedExecution?
}

private struct HistoryMonthGroup: Identifiable {
    var id: String { monthLabel }
    let monthLabel: String
    let latestCompletedAt: Date
    let requiredTotal: Double
    let actualTotal: Double
    let undoAvailable: Bool
    let currency: String
}

struct PlanHistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var groups: [HistoryMonthGroup] = []
    @State private var viewState: ViewState = .idle

    var body: some View {
        AsyncContentView(state: viewState) {
            if groups.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: PlanHistoryPresentation.listEmptyStateTitle,
                    description: PlanHistoryPresentation.listEmptyStateDescription,
                    primaryAction: EmptyStateAction(
                        title: "Refresh",
                        icon: "arrow.clockwise",
                        accessibilityIdentifier: "planning.history.empty.refresh"
                    ) {
                        Task {
                            await loadHistory()
                        }
                    }
                )
            } else {
                List {
                    ForEach(groups) { group in
                        NavigationLink {
                            PlanHistoryDetailView(
                                monthLabel: group.monthLabel,
                                modelContext: modelContext
                            )
                        } label: {
                            HistoryMonthRow(group: group)
                        }
                    }
                }
            }
        } loading: {
            ProgressView("Loading history...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } error: { error in
            ErrorStateView(error: error) {
                await loadHistory()
            }
        }
        .navigationTitle("History")
        .task {
            await loadHistory()
        }
        .refreshable {
            await loadHistory()
        }
    }

    private func loadHistory() async {
        viewState = .loading

        do {
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            let events = try executionService.getCompletionEvents(limit: 500)
            let entries: [HistoryEventEntry] = events.compactMap { event in
                guard let record = event.executionRecord else { return nil }
                return HistoryEventEntry(event: event, record: record, snapshot: event.completionSnapshot)
            }

            let grouped = Dictionary(grouping: entries, by: { $0.event.monthLabel })
            groups = grouped.compactMap { (monthLabel, monthEntries) in
                let sorted = monthEntries.sorted {
                    if $0.event.sequence == $1.event.sequence {
                        return $0.event.completedAt > $1.event.completedAt
                    }
                    return $0.event.sequence > $1.event.sequence
                }
                guard let latest = sorted.first else { return nil }
                let required = latest.snapshot?.goalSnapshots.reduce(0, { $0 + $1.plannedAmount }) ?? 0
                let actual = latest.snapshot?.contributedTotalsByGoalId.values.reduce(0, +) ?? 0
                let latestOpen = sorted.first(where: { $0.event.undoneAt == nil })
                let undoAvailable = latestOpen?.record.canUndo ?? false

                return HistoryMonthGroup(
                    monthLabel: monthLabel,
                    latestCompletedAt: latest.event.completedAt,
                    requiredTotal: required,
                    actualTotal: actual,
                    undoAvailable: undoAvailable,
                    currency: latest.snapshot?.goalSnapshots.first?.currency ?? "USD"
                )
            }
            .sorted(by: { $0.monthLabel > $1.monthLabel })
            viewState = .loaded
        } catch {
            groups = []
            viewState = .error(PlanHistoryPresentation.listLoadError)
            AppLog.error(
                "Failed to load plan history: \(error.localizedDescription)",
                category: .monthlyPlanning
            )
        }
    }
}

private struct HistoryMonthRow: View {
    let group: HistoryMonthGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatMonthLabel(group.monthLabel))
                    .font(.headline)
                Spacer()
                if group.undoAvailable {
                    Text("Undo available")
                        .font(.caption)
                        .foregroundStyle(AccessibleColors.warning)
                }
            }

            Text("Completed \(group.latestCompletedAt, format: .dateTime.month().day().year())")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(PlanHistoryPresentation.monthSummary(
                actualTotal: group.actualTotal,
                requiredTotal: group.requiredTotal,
                currency: group.currency
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            PlanHistoryPresentation.monthRowAccessibilityLabel(
                monthLabel: group.monthLabel,
                latestCompletedAt: group.latestCompletedAt,
                actualTotal: group.actualTotal,
                requiredTotal: group.requiredTotal,
                undoAvailable: group.undoAvailable,
                currency: group.currency
            )
        )
        .accessibilityHint(PlanHistoryPresentation.monthRowAccessibilityHint(undoAvailable: group.undoAvailable))
        .accessibilityIdentifier("planning.history.month.\(group.monthLabel)")
    }

    private func formatMonthLabel(_ label: String) -> String {
        PlanHistoryPresentation.monthTitle(from: label)
    }
}
