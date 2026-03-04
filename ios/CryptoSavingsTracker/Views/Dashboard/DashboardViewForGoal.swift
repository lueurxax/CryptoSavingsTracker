//
//  DashboardViewForGoal.swift
//  CryptoSavingsTracker
//
//  Production entry point for goal dashboard tab.
//

import SwiftUI

struct DashboardViewForGoal: View {
    let goal: Goal

    var body: some View {
        GoalDashboardScreen(goal: goal)
    }
}
