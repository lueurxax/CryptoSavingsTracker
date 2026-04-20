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
    case monthlyPlanning
    case settings

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .goals:
            return "Goals"
        case .monthlyPlanning:
            return "Planning"
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
        case .monthlyPlanning:
            return "calendar"
        case .settings:
            return "gearshape"
        }
    }

    static func visibleSurfaces(for runtimeMode: HiddenRuntimeMode) -> [AppleRootSurface] {
        var surfaces: [AppleRootSurface] = [.dashboard, .goals]
        if runtimeMode.allowsMonthlyPlanning {
            surfaces.append(.monthlyPlanning)
        }
        surfaces.append(.settings)
        return surfaces
    }
}

private struct AppleRootShellState {
    var selectedRootSurface: AppleRootSurface = Self.defaultRootSurface
    var selectedGoalDetailView: DetailViewType = .details

    private static var defaultRootSurface: AppleRootSurface {
        #if DEBUG
        if UITestFlags.shouldStartOnGoals {
            return .goals
        }
        if HiddenRuntimeMode.current.allowsFamilySharing,
           UITestFlags.familyShareScenario != nil {
            return .goals
        }
        #endif
        return .dashboard
    }
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
    @AppStorage(PreviewFeaturesRuntime.userDefaultsKey) private var previewFeaturesEnabled = false

    private var visibleRootSurfaces: [AppleRootSurface] {
        _ = previewFeaturesEnabled
        return AppleRootSurface.visibleSurfaces(for: HiddenRuntimeMode.current)
    }

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

            if HiddenRuntimeMode.current.allowsMonthlyPlanning {
                MonthlyPlanningContainer()
                    .tabItem {
                        Label(
                            AppleRootSurface.monthlyPlanning.title,
                            systemImage: AppleRootSurface.monthlyPlanning.systemImage
                        )
                    }
                    .tag(AppleRootSurface.monthlyPlanning)
            }

            SettingsView()
            .tabItem {
                Label(AppleRootSurface.settings.title, systemImage: AppleRootSurface.settings.systemImage)
            }
            .tag(AppleRootSurface.settings)
        }
        .onChange(of: previewFeaturesEnabled) { _, _ in
            guard visibleRootSurfaces.contains(shellState.selectedRootSurface) else {
                shellState.selectedRootSurface = .dashboard
                return
            }
        }
    }
}

#if os(macOS)
struct macOSContentView: View {
    @State private var shellState = AppleRootShellState()
    @State private var selectedGoal: Goal?
    @AppStorage(PreviewFeaturesRuntime.userDefaultsKey) private var previewFeaturesEnabled = false

    private var visibleRootSurfaces: [AppleRootSurface] {
        _ = previewFeaturesEnabled
        return AppleRootSurface.visibleSurfaces(for: HiddenRuntimeMode.current)
    }

    var body: some View {
        NavigationSplitView {
            List(visibleRootSurfaces, id: \.self, selection: $shellState.selectedRootSurface) { surface in
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
            case .monthlyPlanning:
                MonthlyPlanningContainer()
            case .settings:
                SettingsView()
            }
        }
        .onChange(of: shellState.selectedRootSurface) { _, newValue in
            if newValue != .goals {
                selectedGoal = nil
            }
        }
        .onChange(of: previewFeaturesEnabled) { _, _ in
            guard visibleRootSurfaces.contains(shellState.selectedRootSurface) else {
                shellState.selectedRootSurface = .dashboard
                return
            }
        }
    }
}
#endif
