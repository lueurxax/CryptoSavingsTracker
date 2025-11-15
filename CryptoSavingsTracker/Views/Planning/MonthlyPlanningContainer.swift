//
//  MonthlyPlanningContainer.swift
//  CryptoSavingsTracker
//
//  Created for v2.1 - Monthly Planning Execution & Tracking
//  Container that switches between planning and execution views
//

import SwiftUI
import SwiftData

/// Container view that shows either planning or execution view based on state
struct MonthlyPlanningContainer: View {
    @Environment(\.modelContext) private var modelContext
    @State private var executionRecord: MonthlyExecutionRecord?
    @State private var isLoading = true
    @State private var showStartTrackingConfirmation = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if let record = executionRecord, record.status == .executing || record.status == .closed {
                // Show execution view
                MonthlyExecutionView(modelContext: modelContext)
            } else {
                // Show planning view with start tracking button
                planningViewWithStartButton
            }
        }
        .navigationTitle("Monthly Planning")
        .task {
            await loadExecutionRecord()
        }
    }

    private var planningViewWithStartButton: some View {
        VStack {
            // Planning view
            PlanningView(viewModel: MonthlyPlanningViewModel(modelContext: modelContext))

            // Start Tracking button
            VStack(spacing: 12) {
                Divider()

                Button {
                    showStartTrackingConfirmation = true
                } label: {
                    Label("Start Tracking This Month", systemImage: "chart.line.uptrend.xyaxis.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .alert("Start Tracking?", isPresented: $showStartTrackingConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Start Tracking") {
                        Task {
                            await startTracking()
                        }
                    }
                } message: {
                    Text("This will begin tracking your contributions for this month. You can undo this action within 24 hours.")
                }
            }
            .padding(.bottom)
        }
    }

    // MARK: - Actions

    private func loadExecutionRecord() async {
        isLoading = true

        do {
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            executionRecord = try executionService.getCurrentMonthRecord()
        } catch {
            print("Error loading execution record: \(error)")
        }

        isLoading = false
    }

    private func startTracking() async {
        do {
            // Fetch all active goals
            let descriptor = FetchDescriptor<Goal>(
                predicate: #Predicate { goal in
                    goal.archivedDate == nil
                }
            )
            let goals = try modelContext.fetch(descriptor)

            // Fetch all monthly plans
            let planDescriptor = FetchDescriptor<MonthlyPlan>()
            let plans = try modelContext.fetch(planDescriptor)

            // Start tracking
            let executionService = DIContainer.shared.executionTrackingService(modelContext: modelContext)
            let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
            let record = try executionService.startTracking(for: monthLabel, from: plans, goals: goals)

            executionRecord = record
        } catch {
            print("Error starting tracking: \(error)")
        }
    }
}
