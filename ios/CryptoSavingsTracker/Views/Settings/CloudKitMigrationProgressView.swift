//
//  CloudKitMigrationProgressView.swift
//  CryptoSavingsTracker
//
//  Shows migration progress during the local-to-CloudKit cutover.
//

import SwiftUI

struct CloudKitMigrationProgressView: View {
    @ObservedObject var controller: CloudKitMigrationController

    @State private var migrationError: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            stateIcon
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)

            Text(stateTitle)
                .font(.title2.bold())

            Text(stateDetail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let progress = currentProgress {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 48)

                    Text(progressLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if isIdle {
                Button("Migrate to iCloud") {
                    startMigration()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if isComplete {
                VStack(spacing: 12) {
                    if let evidence = migrationEvidence {
                        evidenceView(evidence)
                    }

                    Text("Restart the app to activate CloudKit sync.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()
        }
        .navigationTitle("iCloud Migration")
        .navigationBarBackButtonHidden(isInProgress)
        .alert("Migration Failed", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(migrationError ?? "An unknown error occurred.")
        }
    }

    // MARK: - State Helpers

    private var isIdle: Bool {
        controller.cutoverState == .idle
    }

    private var isInProgress: Bool {
        switch controller.cutoverState {
        case .idle, .complete, .failed, .rolledBack:
            return false
        default:
            return true
        }
    }

    private var isComplete: Bool {
        if case .complete = controller.cutoverState { return true }
        return false
    }

    private var stateIcon: Image {
        switch controller.cutoverState {
        case .idle:
            return Image(systemName: "icloud.and.arrow.up")
        case .checkingPrerequisites:
            return Image(systemName: "checkmark.shield")
        case .preparingBackup, .backupComplete:
            return Image(systemName: "externaldrive.badge.timemachine")
        case .copyingData:
            return Image(systemName: "doc.on.doc")
        case .validatingCopy:
            return Image(systemName: "checkmark.circle")
        case .switchingMode:
            return Image(systemName: "arrow.triangle.2.circlepath")
        case .complete:
            return Image(systemName: "checkmark.icloud.fill")
        case .failed, .rolledBack:
            return Image(systemName: "exclamationmark.icloud")
        }
    }

    private var stateTitle: String {
        switch controller.cutoverState {
        case .idle:
            return "Ready to Migrate"
        case .checkingPrerequisites:
            return "Checking Prerequisites"
        case .preparingBackup:
            return "Creating Backup"
        case .backupComplete:
            return "Backup Complete"
        case .copyingData(_, let entity):
            return "Copying \(entity)"
        case .validatingCopy:
            return "Validating Data"
        case .switchingMode:
            return "Switching to CloudKit"
        case .complete:
            return "Migration Complete"
        case .failed(let msg):
            return "Migration Failed"
        case .rolledBack(let msg):
            return "Rolled Back"
        }
    }

    private var stateDetail: String {
        switch controller.cutoverState {
        case .idle:
            return "Your local data will be copied to iCloud. A backup is created automatically."
        case .checkingPrerequisites:
            return "Verifying iCloud account and network availability..."
        case .preparingBackup:
            return "Backing up your local data before migration..."
        case .backupComplete(let path):
            return "Backup saved. Starting data copy..."
        case .copyingData:
            return "Copying your data to iCloud..."
        case .validatingCopy:
            return "Verifying all data was copied correctly..."
        case .switchingMode:
            return "Activating CloudKit sync..."
        case .complete:
            return "All data has been migrated to iCloud successfully."
        case .failed(let msg):
            return msg
        case .rolledBack(let msg):
            return msg
        }
    }

    private var currentProgress: Double? {
        if case .copyingData(let progress, _) = controller.cutoverState {
            return progress
        }
        return nil
    }

    private var progressLabel: String {
        if case .copyingData(let progress, let entity) = controller.cutoverState {
            return "\(entity) — \(Int(progress * 100))%"
        }
        return ""
    }

    private var migrationEvidence: CloudKitCutoverCoordinator.MigrationEvidence? {
        if case .complete(let evidence) = controller.cutoverState {
            return evidence
        }
        return nil
    }

    // MARK: - Actions

    private func startMigration() {
        Task {
            do {
                try await controller.attemptMigration()
            } catch {
                migrationError = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Evidence

    @ViewBuilder
    private func evidenceView(_ evidence: CloudKitCutoverCoordinator.MigrationEvidence) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Migration Summary")
                .font(.headline)

            let totalEntities = evidence.entityCounts.values.reduce(0, +)
            LabeledContent("Total Records") {
                Text("\(totalEntities)")
            }
            LabeledContent("Duration") {
                Text(String(format: "%.1fs", evidence.durationSeconds))
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 32)
    }
}
