//
//  SettingsView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var familyShareCoordinator: FamilyShareAcceptanceCoordinator
    @Query(filter: #Predicate<Goal> { goal in
        goal.lifecycleStatusRawValue == "active"
    })
    private var activeGoals: [Goal]
    @ObservedObject private var monthlySettings = MonthlyPlanningSettings.shared
    @StateObject private var persistenceController = PersistenceController.shared
    @StateObject private var bridgeController = LocalBridgeSyncController.shared
    @State private var showingMonthlyPlanningSettings = false
    @State private var settingsVisualEnabled = VisualSystemRollout.shared.isEnabled(flow: .settings)
    @State private var exportResult: CSVExportResult?
    @State private var exportErrorMessage: String?
    @State private var showingExportError = false
    @State private var familyShareEnabled = DIContainer.shared.familyShareRollout.isEnabled()
    @StateObject private var healthMonitor = DIContainer.shared.cloudKitHealthMonitor

    var body: some View {
        NavigationStack {
            Form {
                Section("Data") {
                    Button {
                        do {
                            let urls = try CSVExportService.exportCSVFiles(using: modelContext)
                            exportResult = CSVExportResult(fileURLs: urls)
                        } catch {
                            exportErrorMessage = error.localizedDescription
                            showingExportError = true
                        }
                    } label: {
                        Text("Export Data (CSV)")
                            .accessibilityIdentifier("exportCSVButton")
                    }
                    .accessibilityIdentifier("exportCSVButton")
                    
                    Button("Import Data") {
                        // Import functionality
                    }
                }

                Section {
                    if familyShareEnabled {
                        NavigationLink {
                            FamilyAccessView(
                                model: familyShareCoordinator.makeFamilyAccessModel(currentGoals: activeGoals),
                                onShareWithFamily: {
                                    Task {
                                        await familyShareCoordinator.shareAllGoals(activeGoals)
                                    }
                                },
                                onRefresh: {
                                    Task {
                                        await familyShareCoordinator.refreshFamilyAccessOwnerData(currentGoals: activeGoals)
                                    }
                                },
                                onShowScopePreview: {},
                                onShowParticipants: {
                                    Task {
                                        await familyShareCoordinator.manageParticipants()
                                    }
                                }
                            )
                        } label: {
                            let familyAccessSummary = familyShareCoordinator.settingsRowSummary(currentGoalCount: activeGoals.count)
                            if settingsVisualEnabled {
                                SettingsSectionRow(
                                    title: "Family Access",
                                    systemImage: "person.2.badge.gearshape",
                                    value: familyAccessSummary,
                                    accessibilityIdentifier: "settings.cloudkit.familyAccessRow"
                                )
                            } else {
                                LegacySettingsValueRow(
                                    title: "Family Access",
                                    value: familyAccessSummary,
                                    accessibilityIdentifier: "settings.cloudkit.familyAccessRow"
                                )
                            }
                        }
                        .accessibilityIdentifier("settings.cloudkit.familyAccess")
                    }

                    NavigationLink {
                        LocalBridgeSyncView(persistenceSnapshot: persistenceController.snapshot)
                    } label: {
                        let bridgeSummary = bridgeController
                            .statusSnapshot(persistenceSnapshot: persistenceController.snapshot)
                            .topLevelSummary
                        if settingsVisualEnabled {
                            SettingsSectionRow(
                                title: "Local Bridge Sync",
                                systemImage: "arrow.triangle.2.circlepath.icloud",
                                value: bridgeSummary,
                                accessibilityIdentifier: "settings.cloudkit.localBridgeSyncRow"
                            )
                        } else {
                            LegacySettingsValueRow(
                                title: "Local Bridge Sync",
                                value: bridgeSummary,
                                accessibilityIdentifier: "settings.cloudkit.localBridgeSyncRow"
                            )
                        }
                    }
                    .accessibilityIdentifier("settings.cloudkit.localBridgeSync")
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Authoritative application data now lives only in CloudKit. Local persistence remains available only for caches and other non-authoritative helper data.")
                }

                Section("Monthly Planning") {
                    if settingsVisualEnabled {
                        SettingsSectionRow(
                            title: "Display Currency",
                            systemImage: "dollarsign.circle",
                            value: monthlySettings.displayCurrency,
                            accessibilityIdentifier: "settings.section_row"
                        )

                        SettingsSectionRow(
                            title: "Payment Day",
                            systemImage: "calendar",
                            value: "\(monthlySettings.paymentDay)\(monthlySettings.paymentDay.ordinalSuffix) of month",
                            accessibilityIdentifier: "settings.section_row.payment_day"
                        )

                        SettingsSectionRow(
                            title: "Next Payment",
                            systemImage: "clock",
                            value: "\(monthlySettings.daysUntilPayment) days",
                            accessibilityIdentifier: "settings.section_row.next_payment"
                        )
                    } else {
                        LegacySettingsValueRow(
                            title: "Display Currency",
                            value: monthlySettings.displayCurrency,
                            accessibilityIdentifier: "settings.section_row"
                        )
                        LegacySettingsValueRow(
                            title: "Payment Day",
                            value: "\(monthlySettings.paymentDay)\(monthlySettings.paymentDay.ordinalSuffix) of month",
                            accessibilityIdentifier: "settings.section_row.payment_day"
                        )
                        LegacySettingsValueRow(
                            title: "Next Payment",
                            value: "\(monthlySettings.daysUntilPayment) days",
                            accessibilityIdentifier: "settings.section_row.next_payment"
                        )
                    }
                    
                    Button("Configure Monthly Planning") {
                        showingMonthlyPlanningSettings = true
                    }
                }

            }
            .accessibilityIdentifier("settingsForm")
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("dismissSettingsButton")
                }
            }
            #endif
        }
        #if os(macOS)
        .platformPadding()
        .frame(width: 500, height: 400)
        #endif
        // NAV-MOD: MOD-01
        .sheet(isPresented: $showingMonthlyPlanningSettings) {
            MonthlyPlanningSettingsView(goals: [])
        }
        // NAV-MOD: MOD-01
        .sheet(item: $exportResult) { result in
            CSVExportShareView(fileURLs: result.fileURLs)
        }
        .sheet(item: $familyShareCoordinator.pendingCloudSharingRequest) { request in
            FamilyCloudSharingControllerSheet(
                request: request,
                onDidSave: {
                    familyShareCoordinator.dismissPendingCloudSharingRequest()
                    Task {
                        await familyShareCoordinator.noteOwnerParticipantsDidChange()
                    }
                },
                onDidFail: { message in
                    familyShareCoordinator.latestErrorMessage = message
                    familyShareCoordinator.dismissPendingCloudSharingRequest()
                },
                onDidStopSharing: {
                    familyShareCoordinator.dismissPendingCloudSharingRequest()
                    Task {
                        await familyShareCoordinator.revokeOwnerShare()
                    }
                }
            )
        }
        .alert("Export Failed", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "Unknown error")
        }
        .alert(
            "Family Sharing",
            isPresented: Binding(
                get: { familyShareCoordinator.latestErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        familyShareCoordinator.latestErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                familyShareCoordinator.latestErrorMessage = nil
            }
        } message: {
            Text(familyShareCoordinator.latestErrorMessage ?? "Unknown error")
        }
        .onAppear {
            familyShareEnabled = DIContainer.shared.familyShareRollout.isEnabled()
            settingsVisualEnabled = VisualSystemRollout.shared.isEnabled(flow: .settings)
            persistenceController.refresh()
            bridgeController.refresh()
            if familyShareEnabled {
                Task {
                    await familyShareCoordinator.refreshAllState()
                }
            }
        }
    }
}

private struct SettingsSectionRow: View {
    let title: String
    let systemImage: String
    let value: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: VisualComponentTokens.settingsRowCornerRadius)
                .fill(VisualComponentTokens.settingsRowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VisualComponentTokens.settingsRowCornerRadius)
                .stroke(VisualComponentTokens.financeSurfaceStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: VisualComponentTokens.settingsRowCornerRadius))
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct LegacySettingsValueRow: View {
    let title: String
    let value: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

// MARK: - Extensions

private extension Int {
    var ordinalSuffix: String {
        switch self % 100 {
        case 11...13:
            return "th"
        default:
            switch self % 10 {
            case 1: return "st"
            case 2: return "nd"  
            case 3: return "rd"
            default: return "th"
            }
        }
    }
}

// MARK: - CSV Export Result

/// Wrapper for sheet(item:) presentation to ensure URLs are passed correctly
struct CSVExportResult: Identifiable {
    let id = UUID()
    let fileURLs: [URL]
}
