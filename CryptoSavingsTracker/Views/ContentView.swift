//
//  ContentViewClean.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

// Notification.Name extension moved to shared file

/// Clean, minimal ContentView using platform abstraction
struct ContentView: View {
    @Environment(\.platformCapabilities) private var platform

    var body: some View {
        Group {
            switch platform.navigationStyle {
            case .stack:
                iOSContentView()
            case .splitView:
                macOSContentView()
            case .tabs:
                // Future: Tab-based navigation
                iOSContentView()
            }
        }
    }
}

// MARK: - iOS Content View

struct iOSContentView: View {
    @Query private var goals: [Goal]
    @State private var selectedView: DetailViewType = .details
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            GoalsList(
                goals: goals,
                selectedView: $selectedView,
                onDelete: deleteGoal,
                onRefresh: refreshGoalData
            )
        }
    }

    private func deleteGoal(_ goal: Goal) {
        withAnimation {
            Task {
                await NotificationManager.shared.cancelNotifications(for: goal)
            }
            modelContext.delete(goal)
            try? modelContext.save()

            NotificationCenter.default.post(name: .goalDeleted, object: goal)
        }
    }

    private func refreshGoalData() async {
        let calc = DIContainer.shared.goalCalculationService
        for goal in goals {
            _ = await calc.getCurrentTotal(for: goal)
            _ = await calc.getProgress(for: goal)
        }
    }
}

// MARK: - macOS Content View

struct macOSContentView: View {
    @Query private var goals: [Goal]
    @State private var selectedGoal: Goal?
    @State private var selectedView: DetailViewType = .details

    var body: some View {
        NavigationSplitView {
            GoalsSidebarView(
                goals: goals,
                selectedGoal: $selectedGoal
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            if let goal = selectedGoal {
                DetailContainerView(
                    goal: goal,
                    selectedView: $selectedView
                )
            } else {
                EmptyDetailView()
            }
        }
        .onAppear {
            if selectedGoal == nil && !goals.isEmpty {
                selectedGoal = goals.first
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goalDeleted)) { notification in
            if let deletedGoal = notification.object as? Goal,
               selectedGoal?.id == deletedGoal.id {
                selectedGoal = goals.first
            }
        }
    }
}

// MARK: - Goals List Component

struct GoalsList: View {
    let goals: [Goal]
    @Binding var selectedView: DetailViewType
    let onDelete: (Goal) -> Void
    let onRefresh: () async -> Void
    @State private var showingAddGoal = false
    @State private var editingGoal: Goal?
    @State private var monthlyPlanningViewModel: MonthlyPlanningViewModel?
    @State private var refreshTrigger = UUID()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            // Portfolio-wide Monthly Planning Widget
            if !goals.isEmpty {
                Section {
                    if let viewModel = monthlyPlanningViewModel {
                        MonthlyPlanningWidget(viewModel: viewModel)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section("Your Goals") {
                if goals.isEmpty {
                    EmptyGoalsView {
                        showingAddGoal = true
                    }
                } else {
                    ForEach(goals) { goal in
                        NavigationLink(destination: DetailContainerView(goal: goal, selectedView: $selectedView)) {
                            UnifiedGoalRowView.iOS(goal: goal, refreshTrigger: refreshTrigger)
                        }
                        .accessibilityIdentifier("goalRow-\(goal.name)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                onDelete(goal)
                            }
                            .tint(.red)

                            Button("Edit") {
                                editingGoal = goal
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            GoalContextMenuContent(
                                goal: goal,
                                onDelete: { onDelete(goal) },
                                onEdit: { editingGoal = goal }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Goals")
        .navigationDestination(isPresented: $showingAddGoal) {
            AddGoalView()
        }
        .refreshable {
            await onRefresh()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddGoal = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add goal")
                .accessibilityIdentifier("addGoalButton")
                .platformTouchTarget()
            }
        }
        .onAppear {
            setupShortcuts()
            // Create the monthly planning view model with model context
            if monthlyPlanningViewModel == nil {
                monthlyPlanningViewModel = MonthlyPlanningViewModel(modelContext: modelContext)
            }
        }
        .sheet(item: $editingGoal) { goal in
            EditGoalView(goal: goal, modelContext: goal.modelContext!)
                .presentationDetents([.large])
        }
    }

    private func setupShortcuts() {
        // iOS Shortcuts integration handled in ShortcutsProvider.swift
    }
}

// MARK: - Shared Components

struct GoalContextMenuContent: View {
    let goal: Goal
    let onDelete: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Group {
            Button("Edit Goal") {
                onEdit()
            }

            Button("Add Asset") {
                // Add asset action
            }

            Button("Add Transaction") {
                // Add transaction action
            }

            Divider()

            Button("Delete Goal", role: .destructive) {
                onDelete()
            }
        }
    }
}

// DetailViewType is now defined in Models/DetailViewType.swift

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Asset.self, Transaction.self, configurations: config)

    let goal1 = Goal(name: "Bitcoin Savings", currency: "USD", targetAmount: 50000, deadline: Date().addingTimeInterval(86400 * 90))
    let goal2 = Goal(name: "Ethereum Fund", currency: "USD", targetAmount: 25000, deadline: Date().addingTimeInterval(86400 * 60))

    container.mainContext.insert(goal1)
    container.mainContext.insert(goal2)

    return ContentView()
        .modelContainer(container)
}
