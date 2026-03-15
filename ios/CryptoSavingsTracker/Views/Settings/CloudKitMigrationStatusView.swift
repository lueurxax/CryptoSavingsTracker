//
//  CloudKitMigrationStatusView.swift
//  CryptoSavingsTracker
//
//  Created by Codex on 15/03/2026.
//

import SwiftUI

struct CloudKitMigrationStatusView: View {
    @ObservedObject var controller: CloudKitMigrationController

    var body: some View {
        Form {
            Section("Current Status") {
                LabeledContent("Runtime") {
                    Text(controller.snapshot.runtimeState.rawValue)
                }
                .accessibilityIdentifier("cloudkitMigration.runtime")

                LabeledContent("Migration Status") {
                    Text(controller.snapshot.statusSummary)
                }
                .accessibilityIdentifier("cloudkitMigration.status")

                LabeledContent("Diagnostics") {
                    Text(controller.snapshot.diagnosticsSummary)
                }
                .accessibilityIdentifier("cloudkitMigration.diagnosticsSummary")
            }

            Section("Blocking Prerequisites") {
                ForEach(controller.snapshot.blockers) { blocker in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(blocker.title)
                            .font(.headline)
                        Text(blocker.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("cloudkitMigration.blocker.\(blocker.id)")
                }
            }

            Section("Exit Criteria") {
                ForEach(controller.snapshot.exitCriteria, id: \.self) { criterion in
                    Text(criterion)
                        .accessibilityIdentifier("cloudkitMigration.exitCriterion")
                }
            }

            Section("Bridge Gating") {
                Text(controller.snapshot.bridgeGatingSummary)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cloudkitMigration.bridgeGating")
            }
        }
        .navigationTitle("CloudKit Migration")
        .onAppear {
            controller.refresh()
        }
    }
}
