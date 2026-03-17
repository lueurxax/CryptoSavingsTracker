import SwiftUI

struct LocalBridgeSyncView: View {
    let persistenceSnapshot: PersistenceRuntimeSnapshot

    @StateObject private var controller = LocalBridgeSyncController.shared
    @State private var bridgeNotice: String?

    private var bridgeSnapshot: LocalBridgeSyncStatusSnapshot {
        controller.statusSnapshot(persistenceSnapshot: persistenceSnapshot)
    }

    var body: some View {
        Form {
            Section("Bridge Status") {
                LabeledContent("Runtime") {
                    Text(persistenceSnapshot.activeMode.displayName)
                        .foregroundStyle(isCloudKitPrimaryActive ? .green : .orange)
                }
                .accessibilityIdentifier("localBridge.runtime")

                LabeledContent("Availability") {
                    Text(bridgeSnapshot.availabilityState.displayTitle)
                        .foregroundStyle(availabilityColor)
                }
                .accessibilityIdentifier("localBridge.availability")

                LabeledContent("Pending Action") {
                    Text(bridgeSnapshot.pendingAction.displayTitle)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("localBridge.pendingAction")

                LabeledContent("Top-Level Summary") {
                    Text(bridgeSnapshot.topLevelSummary)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityIdentifier("localBridge.topLevelSummary")

                Text(bridgeSnapshot.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("localBridge.detail")
            }

            Section("Pairing") {
                Button {
                    controller.pairMac(using: .scanQR)
                    bridgeNotice = controller.operatorMessage
                } label: {
                    Label("Pair Mac", systemImage: "desktopcomputer")
                }
                .disabled(bridgeSnapshot.availabilityState == .unavailable)
                .accessibilityIdentifier("localBridge.pairMac")

                HStack {
                    Button("Enter Code Manually") {
                        controller.pairMac(using: .enterCodeManually)
                        bridgeNotice = controller.operatorMessage
                    }
                    .disabled(bridgeSnapshot.availabilityState == .unavailable)

                    Button("Paste Bootstrap Token") {
                        controller.pairMac(using: .pasteBootstrapToken)
                        bridgeNotice = controller.operatorMessage
                    }
                    .disabled(bridgeSnapshot.availabilityState == .unavailable)
                }
                .accessibilityIdentifier("localBridge.manualPairingActions")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Manual Bootstrap")
                        .font(.subheadline.weight(.semibold))
                    Text("Camera-based QR pairing will use the new privacy declarations, and manual code entry remains the fallback path in the final bridge workflow.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let token = bridgeSnapshot.sessionState.bootstrapToken {
                        LabeledContent("Bootstrap Expires") {
                            Text(token.expiresAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        LabeledContent("Pairing ID") {
                            Text(token.pairingID.uuidString)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .accessibilityIdentifier("localBridge.manualBootstrap")
            }

            Section("Session State") {
                LabeledContent("Transport") {
                    Text(bridgeSnapshot.sessionState.transportState.displayTitle)
                        .foregroundStyle(sessionTransportColor)
                }
                .accessibilityIdentifier("localBridge.session.transport")

                LabeledContent("Compatibility") {
                    Text(bridgeSnapshot.sessionState.compatibilityState.displayTitle)
                        .foregroundStyle(bridgeSnapshot.sessionState.compatibilityState == .compatible ? .green : .orange)
                }
                .accessibilityIdentifier("localBridge.session.compatibility")

                LabeledContent("CloudKit Checkpoint") {
                    Text(bridgeSnapshot.sessionState.cloudKitReconciliationState.displayTitle)
                }
                .accessibilityIdentifier("localBridge.session.reconciliation")

                LabeledContent("Workspace") {
                    Text(bridgeSnapshot.sessionState.workspaceState.displayTitle)
                }
                .accessibilityIdentifier("localBridge.session.workspace")

                LabeledContent("Live Store Mutation") {
                    Text(bridgeSnapshot.sessionState.liveStoreMutationAllowed ? "Allowed" : "Blocked")
                        .foregroundStyle(bridgeSnapshot.sessionState.liveStoreMutationAllowed ? .red : .green)
                }
                .accessibilityIdentifier("localBridge.session.liveMutation")
            }

            Section("Trusted Devices") {
                if controller.trustedDevices.isEmpty {
                    Text("No trusted devices stored yet.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("localBridge.trustedDevices.empty")
                } else {
                    ForEach(controller.trustedDevices) { device in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(device.displayName)
                                    .font(.headline)
                                Spacer()
                                Text(device.trustState.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(device.trustState == .active ? .green : .orange)
                            }

                            Text("Fingerprint: \(device.shortFingerprint)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Text("Added: \(device.addedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let lastSuccessfulSyncAt = device.lastSuccessfulSyncAt {
                                Text("Last sync: \(lastSuccessfulSyncAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button(role: .destructive) {
                                controller.revokeTrust(deviceID: device.id)
                                bridgeNotice = controller.operatorMessage
                            } label: {
                                Text("Revoke Trust")
                            }
                            .accessibilityIdentifier("localBridge.revokeTrust.\(device.id.uuidString)")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .accessibilityIdentifier("localBridge.trustedDevices")

            Section("Sync") {
                LabeledContent("Last Sync Status") {
                    Text(bridgeSnapshot.lastSyncOutcome.displayTitle)
                        .foregroundStyle(lastSyncColor)
                }
                .accessibilityIdentifier("localBridge.lastSyncStatus")

                Button {
                    controller.syncNow()
                    bridgeNotice = controller.operatorMessage
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(bridgeSnapshot.availabilityState == .unavailable)
                .accessibilityIdentifier("localBridge.syncNow")
            }

            Section("Import") {
                Button {
                    controller.openImportReview()
                    bridgeNotice = controller.operatorMessage
                } label: {
                    Label("Prepare Import Review", systemImage: "tray.and.arrow.down")
                }
                .disabled(bridgeSnapshot.availabilityState == .unavailable)
                .accessibilityIdentifier("localBridge.importReview")

                NavigationLink {
                    BridgeImportReviewView(
                        status: bridgeSnapshot.importReviewStatus,
                        onApprove: {
                            controller.markImportDecision(.approvedPlaceholder)
                            bridgeNotice = controller.operatorMessage
                        },
                        onReject: {
                            controller.markImportDecision(.rejected)
                            bridgeNotice = controller.operatorMessage
                        },
                        onResetPending: {
                            controller.markImportDecision(.awaitingDecision)
                            bridgeNotice = controller.operatorMessage
                        }
                    )
                } label: {
                    Label("Import Review", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(bridgeSnapshot.availabilityState == .unavailable)
                .accessibilityIdentifier("localBridge.importReview.open")

                if bridgeSnapshot.importReviewStatus.requiresOperatorReview {
                    Button("Dismiss Review") {
                        controller.dismissImportReview()
                        bridgeNotice = controller.operatorMessage
                    }
                    .accessibilityIdentifier("localBridge.dismissImportReview")
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Import Validation Result")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(validationStateLabel)
                            .foregroundStyle(importValidationColor)
                    }
                    LabeledContent("Drift Status") {
                        Text(bridgeSnapshot.importReviewStatus.driftStatus.displayTitle)
                            .foregroundStyle(importDriftColor)
                    }
                    .accessibilityIdentifier("localBridge.importValidationResult.drift")

                    LabeledContent("Operator Decision") {
                        Text(bridgeSnapshot.importReviewStatus.operatorDecision.displayTitle)
                            .foregroundStyle(importDecisionColor)
                    }
                    .accessibilityIdentifier("localBridge.importValidationResult.decision")

                    Text(bridgeSnapshot.importReviewStatus.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !bridgeSnapshot.importReviewStatus.validationWarnings.isEmpty {
                        ForEach(bridgeSnapshot.importReviewStatus.validationWarnings, id: \.self) { warning in
                            Text("• \(warning)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if !bridgeSnapshot.importReviewStatus.changedEntityCounts.isEmpty {
                        ForEach(bridgeSnapshot.importReviewStatus.changedEntityCounts.keys.sorted(), id: \.self) { key in
                            LabeledContent(key) {
                                Text("\(bridgeSnapshot.importReviewStatus.changedEntityCounts[key] ?? 0)")
                            }
                        }
                    }
                }
                .accessibilityIdentifier("localBridge.importValidationResult")
            }

            Section("Capability Manifest") {
                LabeledContent("Bridge Protocol") {
                    Text("v\(bridgeSnapshot.capabilityManifest.bridgeProtocolVersion)")
                }
                LabeledContent("Canonical Encoding") {
                    Text(bridgeSnapshot.capabilityManifest.maximumSupportedCanonicalEncodingVersion)
                }
                LabeledContent("Snapshot Schema") {
                    Text("\(bridgeSnapshot.capabilityManifest.minimumSupportedSnapshotSchemaVersion)-\(bridgeSnapshot.capabilityManifest.maximumSupportedSnapshotSchemaVersion)")
                }
                LabeledContent("App Model Schema") {
                    Text(bridgeSnapshot.capabilityManifest.appModelSchemaVersion)
                }
                LabeledContent("Build") {
                    Text(bridgeSnapshot.capabilityManifest.appBuild)
                }
            }
            .accessibilityIdentifier("localBridge.capabilityManifest")

            Section("Phase 2A Scope") {
                Text("This surface now reflects the dedicated Local Bridge Sync workflow defined by the proposal. Session state, trust storage, bootstrap-token modeling, authoritative snapshot export, and import review validation scaffolding are implemented. Transport, QR scanning, Multipeer session management, macOS transient workspace, cryptographic signature verification, and apply remain intentionally unimplemented in this build.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("localBridge.scope")
            }
        }
        .navigationTitle("Local Bridge Sync")
        .onAppear {
            controller.refresh()
        }
        .alert("Local Bridge Sync", isPresented: Binding(
            get: { bridgeNotice != nil },
            set: { if !$0 { bridgeNotice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(bridgeNotice ?? "")
        }
    }

    private var isCloudKitPrimaryActive: Bool {
        persistenceSnapshot.cloudKitEnabled
            && persistenceSnapshot.activeStoreKind == .cloudPrimary
    }

    private var availabilityColor: Color {
        switch bridgeSnapshot.availabilityState {
        case .ready:
            return .green
        case .reviewRequired, .updateRequired, .pairingRequired:
            return .orange
        case .unavailable:
            return .secondary
        }
    }

    private var sessionTransportColor: Color {
        switch bridgeSnapshot.sessionState.transportState {
        case .idle, .connected, .importApplied:
            return .green
        case .pairingRequired, .pairingTokenReady, .waitingForPeer, .exportingSnapshot, .waitingForEditedSnapshot, .validatingImport, .awaitingImportReview:
            return .orange
        case .importCancelledByUser, .importRejectedDueToDrift, .trustRevoked, .trustExpired:
            return .red
        }
    }

    private var lastSyncColor: Color {
        switch bridgeSnapshot.lastSyncOutcome {
        case .neverSynced:
            return .secondary
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }

    private var validationStateLabel: String {
        bridgeSnapshot.importReviewStatus.validationStatus.displayTitle
    }

    private var importValidationColor: Color {
        switch bridgeSnapshot.importReviewStatus.validationStatus {
        case .notRun:
            return .secondary
        case .passed:
            return .green
        case .warnings:
            return .orange
        case .failed:
            return .red
        }
    }

    private var importDriftColor: Color {
        switch bridgeSnapshot.importReviewStatus.driftStatus {
        case .unknown:
            return .secondary
        case .none:
            return .green
        case .additiveOnly:
            return .orange
        case .conflicting, .destructive:
            return .red
        }
    }

    private var importDecisionColor: Color {
        switch bridgeSnapshot.importReviewStatus.operatorDecision {
        case .notRequired:
            return .secondary
        case .awaitingDecision:
            return .orange
        case .approvedPlaceholder:
            return .green
        case .rejected:
            return .red
        }
    }
}
