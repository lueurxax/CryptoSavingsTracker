//
//  GoalsSidebarContainer.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

/// macOS-specific goals sidebar container with split view navigation
struct GoalsSidebarContainer: View {
    @Query private var goals: [Goal]
    @Query private var archivedGoals: [Goal]
    @Binding var selectedGoal: Goal?
    @Binding var selectedView: DetailViewType
    @State private var didInitializeSelection = false
    @State private var awaitsInitialSelection = false

    init(
        selectedGoal: Binding<Goal?>,
        selectedView: Binding<DetailViewType>
    ) {
        _selectedGoal = selectedGoal
        _selectedView = selectedView
        _goals = Query(
            filter: GoalListQuery.activePredicate,
            sort: \Goal.deadline,
            order: .forward
        )
        _archivedGoals = Query(
            filter: GoalListQuery.archivedPredicate,
            sort: \Goal.lastModifiedDate,
            order: .reverse
        )
    }

    var body: some View {
        NavigationSplitView {
            GoalsSidebarView(
                goals: goals,
                archivedGoals: archivedGoals,
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
            initializeSelection()
        }
        .onChange(of: goals.map(\.id)) { _, _ in
            if awaitsInitialSelection {
                selectedGoal = GoalSidebarSelectionPolicy.initialSelection(activeGoals: goals)
                awaitsInitialSelection = selectedGoal == nil && goals.isEmpty
            } else {
                repairSelection()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goalDeleted)) { notification in
            if let deletedGoal = notification.object as? Goal,
               selectedGoal?.id == deletedGoal.id {
                selectedGoal = GoalSidebarSelectionPolicy.reconcile(
                    selectedGoal: selectedGoal,
                    activeGoals: goals,
                    excludingGoalID: deletedGoal.id
                )
            }
        }
    }

    private func initializeSelection() {
        guard !didInitializeSelection else { return }
        didInitializeSelection = true

        if selectedGoal == nil {
            selectedGoal = GoalSidebarSelectionPolicy.initialSelection(activeGoals: goals)
            awaitsInitialSelection = selectedGoal == nil && goals.isEmpty
        } else {
            awaitsInitialSelection = false
            repairSelection()
        }
    }

    private func repairSelection() {
        guard didInitializeSelection else { return }
        selectedGoal = GoalSidebarSelectionPolicy.reconcile(
            selectedGoal: selectedGoal,
            activeGoals: goals
        )
    }
}
