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
}

struct PlanHistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var groups: [HistoryMonthGroup] = []
    @State private var isLoading = false

    var body: some View {
        List {
            if groups.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Completed months will appear here")
                )
            } else {
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
        .navigationTitle("History")
        .task {
            await loadHistory()
        }
        .refreshable {
            await loadHistory()
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    private func loadHistory() async {
        isLoading = true
        defer { isLoading = false }

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
                    undoAvailable: undoAvailable
                )
            }
            .sorted(by: { $0.monthLabel > $1.monthLabel })
        } catch {
            print("Error loading history: \(error)")
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

            Text("Planned: \(formatCurrency(group.actualTotal)) of \(formatCurrency(group.requiredTotal))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
}
