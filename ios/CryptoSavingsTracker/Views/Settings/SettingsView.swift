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
    @Query(filter: #Predicate<Goal> { goal in
        goal.lifecycleStatusRawValue == "active"
    })
    private var activeGoals: [Goal]
    @AppStorage("mvp.settings.displayCurrency") private var displayCurrency = "USD"
    @AppStorage(AppAppearance.storageKey) private var appearance = "system"
    @AppStorage(PreviewFeaturesRuntime.userDefaultsKey) private var previewFeaturesEnabled = false
    @State private var isShowingPreviewFeaturesWarning = false

    private let supportURL = URL(string: "https://support.cryptosavingstracker.app")!
    private let syncSharingGateway: any SettingsSyncSharingGateway

    @MainActor
    init(syncSharingGateway: (any SettingsSyncSharingGateway)? = nil) {
        self.syncSharingGateway = syncSharingGateway ?? RuntimeSettingsSyncSharingGateway()
    }

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
                    Button {
                        handlePreviewFeaturesButtonTapped()
                    } label: {
                        previewFeaturesRow
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.previewFeaturesButton")
                    .accessibilityLabel("Preview Features")
                    .accessibilityValue(previewFeaturesEnabled ? "On" : "Off")
                } header: {
                    Text("Preview")
                } footer: {
                    Text(previewFeaturesFooterCopy)
                }

                if syncSharingGateway.isSyncSharingSectionEnabled {
                    Section {
                        ForEach(syncSharingGateway.rows) { row in
                            NavigationLink {
                                syncSharingGateway.makeDestination(for: row, activeGoals: activeGoals)
                            } label: {
                                syncSharingRow(row)
                            }
                            .accessibilityIdentifier(row.accessibilityIdentifier)
                            .accessibilityLabel(row.accessibilityLabel)
                            .accessibilityHint(SettingsUXCopy.navigationHint(destination: row.title))
                        }
                    } header: {
                        Text("Sync & Sharing")
                    } footer: {
                        Text(Self.syncSectionFooterCopy)
                    }
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
            .alert("Preview Features", isPresented: $isShowingPreviewFeaturesWarning) {
                Button("Enable Preview") {
                    previewFeaturesEnabled = true
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("These features are still being tested and may be incomplete, unstable, or change without notice.")
            }
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
    private func syncSharingRow(_ row: SettingsSyncSharingRow) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .foregroundStyle(AccessibleColors.primaryText)
                Text(row.detail)
                    .font(.footnote)
                    .foregroundStyle(AccessibleColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: row.systemImage)
                .foregroundStyle(AccessibleColors.primaryInteractive)
        }
    }

    @ViewBuilder
    private func settingsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(AccessibleColors.secondaryText)
        }
    }

    private var previewFeaturesRow: some View {
        HStack {
            Label {
                Text("Preview Features")
                    .foregroundStyle(AccessibleColors.primaryText)
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(AccessibleColors.primaryInteractive)
            }
            Spacer()
            Text(previewFeaturesEnabled ? "On" : "Off")
                .foregroundStyle(AccessibleColors.secondaryText)
        }
    }

    private var previewFeaturesFooterCopy: String {
        if previewFeaturesEnabled {
            return "Preview features are visible. Turn this off to return to the stable experience."
        }

        return "Enable unreleased app surfaces for early testing only."
    }

    private func handlePreviewFeaturesButtonTapped() {
        if previewFeaturesEnabled {
            previewFeaturesEnabled = false
        } else {
            isShowingPreviewFeaturesWarning = true
        }
    }

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }
}
