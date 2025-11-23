//
//  PlanHistoryListView.swift
//  CryptoSavingsTracker
//
//  Created for v2.1 - Monthly Planning Execution & Tracking
//  Shows list of completed monthly execution records
//

import SwiftUI
import SwiftData

struct PlanHistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var completedRecords: [MonthlyExecutionRecord] = []
    @State private var isLoading = false
    @State private var selectedRecord: MonthlyExecutionRecord?

    var body: some View {
        List {
            if completedRecords.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Completed months will appear here")
                )
            } else {
                ForEach(completedRecords, id: \.id) { record in
                    NavigationLink(value: record) {
                        HistoryRecordRow(record: record, modelContext: modelContext)
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationDestination(for: MonthlyExecutionRecord.self) { record in
            PlanHistoryDetailView(record: record, modelContext: modelContext)
        }
        .task {
            await loadCompletedRecords()
        }
        .refreshable {
            await loadCompletedRecords()
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    private func loadCompletedRecords() async {
        isLoading = true

        do {
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            completedRecords = try executionService.getCompletedRecords(limit: 12)
        } catch {
            print("Error loading completed records: \(error)")
        }

        isLoading = false
    }
}

// MARK: - History Record Row

struct HistoryRecordRow: View {
    let record: MonthlyExecutionRecord
    let modelContext: ModelContext

    @State private var progress: Double = 0
    @State private var totalContributed: Double = 0
    @State private var totalPlanned: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatMonthLabel(record.monthLabel))
                    .font(.headline)

                Spacer()

                if progress >= 100 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            let pct = min(max(progress, 0), 100)
            ProgressView(value: pct, total: 100)
                .tint(pct >= 100 ? .green : .orange)

            HStack {
                Text("\(Int(progress))% complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let snapshot = record.snapshot {
                    Text("\(snapshot.activeGoalCount) goals")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let completedAt = record.completedAt {
                Text("Completed \(completedAt, format: .dateTime.month().day())")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .task {
            await calculateProgress()
        }
    }

    private func calculateProgress() async {
        do {
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            progress = try executionService.calculateProgress(for: record)

            let totals = try executionService.getContributionTotals(for: record)
            totalContributed = totals.values.reduce(0, +)
            totalPlanned = record.snapshot?.totalPlanned ?? 0
        } catch {
            print("Error calculating progress: \(error)")
        }
    }

    private func formatMonthLabel(_ label: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        if let date = formatter.date(from: label) {
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
        return label
    }
}
