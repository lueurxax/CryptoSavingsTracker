//
//  ContentView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI

private enum AppleRootSurface: String, CaseIterable, Hashable {
    case dashboard
    case goals
    case settings

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .goals:
            return "Goals"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "chart.pie"
        case .goals:
            return "flag"
        case .settings:
            return "gearshape"
        }
    }
}

private struct AppleRootShellState {
    var selectedRootSurface: AppleRootSurface = .dashboard
    var selectedGoalDetailView: DetailViewType = .details
}

struct ContentView: View {
    @Environment(\.platformCapabilities) private var platform

    @ViewBuilder
    var body: some View {
        switch platform.navigationStyle {
        case .stack, .tabs:
            iOSContentView()
        case .splitView:
            #if os(macOS)
                macOSContentView()
            #else
                iOSContentView()
            #endif
        }
    }
}

struct iOSContentView: View {
    @State private var shellState = AppleRootShellState()

    var body: some View {
        TabView(selection: $shellState.selectedRootSurface) {
            DashboardView()
            .tabItem {
                Label(AppleRootSurface.dashboard.title, systemImage: AppleRootSurface.dashboard.systemImage)
            }
            .tag(AppleRootSurface.dashboard)

            GoalsListContainer(selectedView: $shellState.selectedGoalDetailView)
                .tabItem {
                    Label(AppleRootSurface.goals.title, systemImage: AppleRootSurface.goals.systemImage)
                }
                .tag(AppleRootSurface.goals)

            SettingsView()
            .tabItem {
                Label(AppleRootSurface.settings.title, systemImage: AppleRootSurface.settings.systemImage)
            }
            .tag(AppleRootSurface.settings)
        }
    }
}

#if os(macOS)
struct macOSContentView: View {
    @State private var shellState = AppleRootShellState()
    @State private var selectedGoal: Goal?

    var body: some View {
        NavigationSplitView {
            List(AppleRootSurface.allCases, id: \.self, selection: $shellState.selectedRootSurface) { surface in
                Label(surface.title, systemImage: surface.systemImage)
                    .tag(surface)
            }
            .navigationTitle("CryptoSavingsTracker")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
        } detail: {
            switch shellState.selectedRootSurface {
            case .dashboard:
                DashboardView()
            case .goals:
                GoalsSidebarContainer(
                    selectedGoal: $selectedGoal,
                    selectedView: $shellState.selectedGoalDetailView
                )
            case .settings:
                SettingsView()
            }
        }
        .onChange(of: shellState.selectedRootSurface) { _, newValue in
            if newValue != .goals {
                selectedGoal = nil
            }
        }
    }
}
#endif
