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
    @AppStorage("mvp.settings.appearance") private var appearance = "system"

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

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }
}
