//
//  SettingsView.swift
//  CryptoSavingsTracker
//
//  Created by Claude on 08/08/2025.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    static let syncSectionFooterCopy = SettingsUXCopy.syncSectionFooter

    @Environment(\.dismiss) private var dismiss
    @AppStorage("mvp.settings.displayCurrency") private var displayCurrency = "USD"
    @AppStorage("mvp.settings.appearance") private var appearance = "system"

    @Query(filter: #Predicate<Goal> { $0.lifecycleStatusRawValue == "active" })
    private var activeGoals: [Goal]

    private let supportURL = URL(string: "https://lueurxax.github.io/CryptoSavingsTracker/support/")!

    var body: some View {
        NavigationStack {
            Form {
                Section("Preferences") {
                    Picker("Display Currency", selection: $displayCurrency) {
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                        Text("GBP").tag("GBP")
                    }

                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }

                Section {
                    NavigationLink {
                        FamilyAccessView(
                            model: DIContainer.shared.familyShareAcceptanceCoordinator.makeFamilyAccessModel(
                                currentGoals: activeGoals
                            ),
                            onShareWithFamily: {
                                let goals = activeGoals
                                Task { await DIContainer.shared.familyShareAcceptanceCoordinator.shareAllGoals(goals) }
                            },
                            onRefresh: {
                                let goals = activeGoals
                                Task { await DIContainer.shared.familyShareAcceptanceCoordinator.refreshFamilyAccessOwnerData(currentGoals: goals) }
                            },
                            onShowScopePreview: {},
                            onShowParticipants: {}
                        )
                        .navigationTitle("Family Access")
                    } label: {
                        Text("Family Access")
                    }
                    .accessibilityIdentifier("settings.cloudkit.familyAccessRow")
                    .accessibilityHint(SettingsUXCopy.navigationHint(destination: "Family Access"))

                    NavigationLink {
                        LocalBridgeSyncView(persistenceSnapshot: PersistenceController.shared.snapshot)
                            .navigationTitle("Local Bridge Sync")
                    } label: {
                        Text("Local Bridge Sync")
                    }
                    .accessibilityIdentifier("settings.cloudkit.localBridgeSyncRow")
                    .accessibilityHint(SettingsUXCopy.navigationHint(destination: "Local Bridge Sync"))
                } header: {
                    Text("Sync & Sharing")
                } footer: {
                    Text(SettingsUXCopy.syncSectionFooter)
                }

                Section("About") {
                    Link(destination: supportURL) {
                        settingsRow(title: "Support", value: "Open")
                    }

                    settingsRow(title: "Version", value: appVersion)
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
        .frame(width: 500, height: 400)
        #endif
    }

    @ViewBuilder
    private func settingsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }
}
