import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct LocalBridgeSyncView: View {
    let persistenceSnapshot: PersistenceRuntimeSnapshot

    @StateObject private var controller = LocalBridgeSyncController.shared
    @StateObject private var nearbyTransport = LocalBridgeTransportCoordinator()
    @State private var bridgeNotice: String?
    @State private var presentsImportPackagePicker = false
    @State private var presentsPairingTokenEntry = false
    @State private var pairingMethod: BridgePairingMethod = .enterCodeManually
    @State private var pairingTokenInput = ""
    @State private var revealBootstrapToken = false
    @State private var presentsQRScanner = false

    private var bridgeSnapshot: LocalBridgeSyncStatusSnapshot {
        controller.statusSnapshot(persistenceSnapshot: persistenceSnapshot)
    }

    var body: some View {
        Form {
            Section("Bridge Status") {
                LabeledContent("Runtime") {
                    Text(persistenceSnapshot.activeMode.displayName)
                        .foregroundStyle(isCloudKitPrimaryActive ? AccessibleColors.success : AccessibleColors.warning)
                }
                .accessibilityIdentifier("localBridge.runtime")

                LabeledContent("Availability") {
                    Text(bridgeSnapshot.availabilityState.displayTitle)
                        .foregroundStyle(availabilityColor)
                }
                .accessibilityIdentifier("localBridge.availability")
                .accessibilityValue(bridgeSnapshot.availabilityState.displayTitle)

                LabeledContent("Pending Action") {
                    Text(bridgeSnapshot.pendingAction.displayTitle)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("localBridge.pendingAction")
                .accessibilityValue(bridgeSnapshot.pendingAction.displayTitle)

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
                #if !os(macOS)
                Picker("Pairing Method", selection: $pairingMethod) {
                    ForEach(Array(pairingMethods.enumerated()), id: \.offset) { _, method in
                        Text(method.displayTitle)
                            .tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("localBridge.pairingMethod")
                #endif

                Button {
                    runPairingAction(for: pairingMethod)
                } label: {
                    Label(pairingActionTitle(for: pairingMethod), systemImage: pairingActionSystemImage(for: pairingMethod))
                }
                .disabled(bridgeSnapshot.availabilityState == .unavailable)
                .accessibilityIdentifier("localBridge.pairMac")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Trusted Pairing")
                        .font(.subheadline.weight(.semibold))
                    Text("Signed bridge pairing is foreground-only. Select a pairing method, scan a QR code, or use a nearby token. Camera permission is requested only when the QR scanner opens.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let token = bridgeSnapshot.sessionState.bootstrapToken {
                        LabeledContent("Bootstrap Expires") {
                            Text(token.expiresAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        LabeledContent("Pairing ID") {
                            let metadata = LocalBridgeIdentifierPresentation.metadata(
                                title: "Pairing ID",
                                value: token.pairingID.uuidString
                            )
                            Text(token.pairingID.uuidString)
                                .font(.caption.monospaced())
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel(metadata.label)
                                .accessibilityValue(metadata.value)
                                .accessibilityHint(metadata.hint)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Manual Pairing Code")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(manualPairingCode(for: token))
                                .font(.caption.monospaced())
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("localBridge.pairingCode")
                        .accessibilityValue(manualPairingCode(for: token))

                        Button("Copy Pairing Code") {
                            #if os(iOS)
                                UIPasteboard.general.string = manualPairingCode(for: token)
                            #endif
                            bridgeNotice = "Pairing code copied. Share it only during the current bridge session."
                        }
                        .accessibilityIdentifier("localBridge.pairingCode.copy")

                        LabeledContent("Manual Pairing Token") {
                            Text(revealBootstrapToken ? fullBootstrapToken(for: token) : redactedBootstrapToken(for: token))
                                .font(.caption.monospaced())
                                .lineLimit(3)
                                .textSelection(.enabled)
                                .privacySensitive()
                        }
                        .accessibilityIdentifier("localBridge.bootstrapToken")
                        .accessibilityValue(revealBootstrapToken ? "Visible" : "Hidden")

                        if !revealBootstrapToken {
                            Text("Token remains hidden until you explicitly reveal it.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("localBridge.bootstrapToken.hiddenHint")
                        }

                        HStack {
                            Button(revealBootstrapToken ? "Hide Token" : "Reveal Token") {
                                revealBootstrapToken.toggle()
                            }
                            .accessibilityIdentifier("localBridge.bootstrapToken.toggle")

                            Button("Copy Token") {
                                #if os(iOS)
                                    UIPasteboard.general.string = fullBootstrapToken(for: token)
                                #endif
                                bridgeNotice = "Bootstrap token copied. Treat it as short-lived session material."
                            }
                            .accessibilityIdentifier("localBridge.bootstrapToken.copy")
                        }
                    }
                }
                .accessibilityIdentifier("localBridge.manualBootstrap")
                .accessibilityValue(
                    bridgeSnapshot.sessionState.bootstrapToken == nil
                        ? "Unavailable"
                        : (revealBootstrapToken ? "Visible" : "Hidden")
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Nearby Pairing")
                        .font(.subheadline.weight(.semibold))

                    LabeledContent("Nearby State") {
                        Text(nearbyTransport.state.displayTitle)
                            .foregroundStyle(nearbyStateColor)
                    }
                    .accessibilityIdentifier("localBridge.nearby.state")
                    .accessibilityValue(nearbyTransport.state.displayTitle)

                    if !nearbyTransport.discoveredPeers.isEmpty {
                        Text("Peers: \(nearbyTransport.discoveredPeers.joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("localBridge.nearby.peers")
                    }

                    HStack {
                        Button("Advertise Nearby") {
                            nearbyTransport.startAdvertising()
                        }
                        .accessibilityIdentifier("localBridge.nearby.advertise")

                        Button("Browse Nearby") {
                            nearbyTransport.startBrowsing()
                        }
                        .accessibilityIdentifier("localBridge.nearby.browse")
                    }

                    HStack {
                        Button("Stop Nearby") {
                            nearbyTransport.stop()
                        }
                        .accessibilityIdentifier("localBridge.nearby.stop")

                        if let token = bridgeSnapshot.sessionState.bootstrapToken {
                            Button("Send Token Nearby") {
                                nearbyTransport.sendBootstrapToken(fullBootstrapToken(for: token))
                            }
                            .accessibilityIdentifier("localBridge.nearby.sendToken")
                        }
                    }

                    if nearbyTransport.lastReceivedBootstrapToken != nil {
                        Button("Use Received Nearby Token") {
                            consumeNearbyBootstrapToken()
                        }
                        .accessibilityIdentifier("localBridge.nearby.useReceivedToken")
                    }

                    if let latestExportArtifact = controller.latestExportArtifact {
                        Button("Send Latest Snapshot Nearby") {
                            nearbyTransport.sendArtifact(at: latestExportArtifact.fileURL)
                        }
                        .accessibilityIdentifier("localBridge.nearby.sendLatestSnapshot")
                    }

                    if let latestSignedPackageArtifact = controller.latestSignedPackageArtifact {
                        Button("Send Signed Package Nearby") {
                            nearbyTransport.sendArtifact(at: latestSignedPackageArtifact.fileURL)
                        }
                        .accessibilityIdentifier("localBridge.nearby.sendSignedPackage")
                    }

                    if nearbyTransport.resumableOutgoingArtifactURL != nil {
                        Button("Resume Nearby Transfer") {
                            nearbyTransport.resumeLastOutgoingTransfer()
                        }
                        .accessibilityIdentifier("localBridge.nearby.resumeTransfer")
                    }

                    if let receivedArtifactURL = nearbyTransport.lastReceivedArtifactURL {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Received Nearby Package")
                                .font(.footnote.weight(.semibold))
                            Text(receivedArtifactURL.lastPathComponent)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        .accessibilityIdentifier("localBridge.nearby.receivedArtifact")

                        Button("Use Received Nearby Package") {
                            consumeNearbyArtifact()
                        }
                        .accessibilityIdentifier("localBridge.nearby.useReceivedArtifact")
                    }

                    if let lastTransferSummary = nearbyTransport.lastTransferSummary {
                        Text(lastTransferSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("localBridge.nearby.transferSummary")
                    }

                    if let transferDiagnostics = nearbyTransport.transferDiagnostics {
                        Text(transferDiagnostics)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("localBridge.nearby.transferDiagnostics")
                    }
                }
            }

            Section("Session State") {
                LabeledContent("Transport") {
                    Text(bridgeSnapshot.sessionState.transportState.displayTitle)
                        .foregroundStyle(sessionTransportColor)
                }
                .accessibilityIdentifier("localBridge.session.transport")

                LabeledContent("Compatibility") {
                    Text(bridgeSnapshot.sessionState.compatibilityState.displayTitle)
                        .foregroundStyle(
                            bridgeSnapshot.sessionState.compatibilityState == .compatible
                                ? AccessibleColors.success
                                : AccessibleColors.warning
                        )
                }
                .accessibilityIdentifier("localBridge.session.compatibility")
                .accessibilityValue(bridgeSnapshot.sessionState.compatibilityState.displayTitle)

                LabeledContent("Sync Checkpoint") {
                    Text(bridgeSnapshot.sessionState.cloudKitReconciliationState.displayTitle)
                }
                .accessibilityIdentifier("localBridge.session.reconciliation")

                LabeledContent("Workspace") {
                    Text(bridgeSnapshot.sessionState.workspaceState.displayTitle)
                }
                .accessibilityIdentifier("localBridge.session.workspace")

                LabeledContent("Live Store Mutation") {
                    Text(bridgeSnapshot.sessionState.liveStoreMutationAllowed ? "Allowed" : "Blocked")
                        .foregroundStyle(
                            bridgeSnapshot.sessionState.liveStoreMutationAllowed
                                ? AccessibleColors.error
                                : AccessibleColors.success
                        )
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
                                    .foregroundStyle(
                                        device.trustState == .active
                                            ? AccessibleColors.success
                                            : AccessibleColors.warning
                                    )
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

                            if let lastValidationOutcome = device.lastValidationOutcome {
                                Text(validationOutcomeLabel(for: device, outcome: lastValidationOutcome))
                                    .font(.caption)
                                    .foregroundStyle(
                                        lastValidationOutcome == .failed
                                            ? AccessibleColors.error
                                            : AccessibleColors.secondaryText
                                    )
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

                if let exportArtifact = controller.latestExportArtifact {
                    LabeledContent("Latest Export") {
                        Text(exportArtifact.displayName)
                            .font(.caption.monospaced())
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityIdentifier("localBridge.latestExportArtifact")

                    LabeledContent("Exported At") {
                        Text(exportArtifact.exportedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .accessibilityIdentifier("localBridge.latestExportArtifactDate")

                    Text(exportArtifact.fileURL.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("localBridge.latestExportArtifactPath")

                    ShareLink(item: exportArtifact.fileURL) {
                        Label("Share Latest Export", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("localBridge.shareLatestExport")
                }

                Button {
                    controller.syncNow()
                    bridgeNotice = controller.operatorMessage
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(bridgeSnapshot.availabilityState == .unavailable || bridgeSnapshot.pendingAction == .pairMac)
                .accessibilityIdentifier("localBridge.syncNow")
            }

            Section("Import") {
                Button {
                    presentsImportPackagePicker = true
                } label: {
                    Label("Load Import Package", systemImage: "doc.badge.plus")
                }
                .disabled(bridgeSnapshot.availabilityState == .unavailable)
                .accessibilityIdentifier("localBridge.loadImportPackage")

                if let importArtifact = controller.latestImportArtifact {
                    LabeledContent("Loaded Package") {
                        Text(importArtifact.displayName)
                            .font(.caption.monospaced())
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityIdentifier("localBridge.latestImportArtifact")

                    LabeledContent("Signed At") {
                        Text(importArtifact.signedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .accessibilityIdentifier("localBridge.latestImportArtifactDate")

                    Text(importArtifact.fileURL.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("localBridge.latestImportArtifactPath")

                    ShareLink(item: importArtifact.fileURL) {
                        Label("Share Loaded Package", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("localBridge.shareLoadedImportPackage")

                    if let packageID = controller.latestLoadedImportPackageID {
                        LabeledContent("Loaded Package ID") {
                            let metadata = LocalBridgeIdentifierPresentation.metadata(
                                title: "Loaded Package ID",
                                value: packageID
                            )
                            Text(packageID)
                                .font(.caption.monospaced())
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel(metadata.label)
                                .accessibilityValue(metadata.value)
                                .accessibilityHint(metadata.hint)
                        }
                        .accessibilityIdentifier("localBridge.latestImportPackageID")
                    }

                    Button {
                        controller.openImportReview()
                        bridgeNotice = controller.operatorMessage
                    } label: {
                        Label("Refresh Import Review", systemImage: "arrow.clockwise")
                    }
                    .disabled(bridgeSnapshot.availabilityState == .unavailable)
                    .accessibilityIdentifier("localBridge.importReview.refresh")

                    if bridgeSnapshot.importReviewStatus.reviewSummaryDTO == nil {
                        Text("Load review metadata from the selected package before apply becomes available.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("localBridge.importReview.hint")
                    } else if let review = bridgeSnapshot.importReviewStatus.reviewSummaryDTO {
                        LabeledContent("Loaded Signature") {
                            Text(review.package.signatureStatus.displayTitle)
                                .foregroundStyle(importSignatureColor(review.package.signatureStatus))
                        }
                        .accessibilityIdentifier("localBridge.importReview.signatureSummary")

                        LabeledContent("Loaded Source") {
                            Text(review.package.sourceDeviceName)
                                .multilineTextAlignment(.trailing)
                        }
                        .accessibilityIdentifier("localBridge.importReview.sourceSummary")
                    }
                }

                NavigationLink {
                    BridgeImportReviewView(controller: controller)
                } label: {
                    Label("Import Review", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(
                    bridgeSnapshot.availabilityState == .unavailable ||
                    !controller.hasLoadedImportPackage ||
                    !bridgeSnapshot.importReviewStatus.requiresOperatorReview
                )
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
                                .foregroundStyle(AccessibleColors.warning)
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

            #if os(macOS)
            Section("Transient Workspace") {
                if controller.hasLoadedTransientWorkspace,
                   let artifact = controller.transientWorkspaceArtifact,
                   let snapshot = controller.transientWorkspaceSnapshot {
                    LabeledContent("Workspace File") {
                        Text(artifact.displayName)
                            .font(.caption.monospaced())
                    }

                    Text(artifact.fileURL.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    LabeledContent("Goals Loaded") {
                        Text("\(snapshot.goals.count)")
                    }

                    NavigationLink {
                        LocalBridgeTransientWorkspaceEditorView(
                            snapshot: snapshot,
                            artifact: artifact,
                            onSave: { updated in
                                controller.saveTransientWorkspaceDraft(updated)
                                bridgeNotice = controller.operatorMessage
                            },
                            onExport: { updated in
                                controller.saveTransientWorkspaceDraft(updated)
                                controller.exportSignedPackageFromTransientWorkspace()
                                bridgeNotice = controller.operatorMessage
                            },
                            onDiscard: {
                                controller.discardTransientWorkspace()
                                bridgeNotice = controller.operatorMessage
                            }
                        )
                    } label: {
                        Label("Open Workspace Editor", systemImage: "square.and.pencil")
                    }
                    .accessibilityIdentifier("localBridge.transientWorkspace.open")
                } else {
                    Text("No transient workspace loaded.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("localBridge.transientWorkspace.empty")
                }

                Button {
                    controller.loadAuthoritativeSnapshotIntoTransientWorkspace()
                    bridgeNotice = controller.operatorMessage
                } label: {
                    Label("Load Authoritative Snapshot", systemImage: "tray.and.arrow.down")
                }
                .accessibilityIdentifier("localBridge.transientWorkspace.load")

                if let signedPackage = controller.latestSignedPackageArtifact {
                    LabeledContent("Latest Signed Package") {
                        Text(signedPackage.displayName)
                            .font(.caption.monospaced())
                    }

                    Text(signedPackage.fileURL.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    ShareLink(item: signedPackage.fileURL) {
                        Label("Share Signed Package", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("localBridge.transientWorkspace.sharePackage")
                }
            }
            #endif

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
                Text("This surface supports file-based bridge handoff end to end, plus QR-assisted and nearby bootstrap pairing. The authoritative snapshot export persists a shareable artifact, import review loads a signed package from Files, signature validation runs before review, and apply writes only into the sync runtime after explicit approval.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("localBridge.scope")
            }
        }
        .navigationTitle("Local Bridge Sync")
        .onAppear {
            controller.refresh()
        }
        .onDisappear {
            nearbyTransport.stop()
        }
        .alert("Local Bridge Sync", isPresented: Binding(
            get: { bridgeNotice != nil },
            set: { if !$0 { bridgeNotice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(bridgeNotice ?? "")
        }
        .fileImporter(
            isPresented: $presentsImportPackagePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let fileURL = urls.first else {
                    bridgeNotice = "No import package was selected."
                    return
                }
                controller.loadImportPackage(from: fileURL)
                bridgeNotice = controller.operatorMessage
            case let .failure(error):
                bridgeNotice = "Failed to open import package picker: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $presentsPairingTokenEntry) {
            NavigationStack {
                Form {
                    Section(pairingEntrySectionTitle) {
                        Text(pairingEntryHelperCopy)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextField(pairingEntryPlaceholder, text: $pairingTokenInput, axis: .vertical)
                        #if !os(macOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        #endif
                            .font(.caption.monospaced())
                            .accessibilityIdentifier("localBridge.pairingEntry.input")
                    }
                }
                .navigationTitle(pairingEntryNavigationTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            presentsPairingTokenEntry = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Pair") {
                            controller.pairMac(using: pairingMethod, bootstrapTokenString: pairingTokenInput)
                            bridgeNotice = controller.operatorMessage
                            presentsPairingTokenEntry = false
                        }
                        .disabled(pairingTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $presentsQRScanner) {
            NavigationStack {
                LocalBridgeQRScannerView(
                    onCodeScanned: { scannedValue in
                        handleScannedBootstrapToken(scannedValue)
                        presentsQRScanner = false
                    },
                    onFailure: { message in
                        bridgeNotice = message
                        presentsQRScanner = false
                    }
                )
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            presentsQRScanner = false
                        }
                    }
                }
            }
        }
        #endif
    }

    private var isCloudKitPrimaryActive: Bool {
        persistenceSnapshot.cloudKitEnabled
            && persistenceSnapshot.activeStoreKind == .cloudPrimary
    }

    private var availabilityColor: Color {
        switch bridgeSnapshot.availabilityState {
        case .ready:
            return AccessibleColors.success
        case .reviewRequired, .updateRequired, .pairingRequired:
            return AccessibleColors.warning
        case .unavailable:
            return AccessibleColors.secondaryText
        }
    }

    private var sessionTransportColor: Color {
        switch bridgeSnapshot.sessionState.transportState {
        case .idle, .connected, .importApplied:
            return AccessibleColors.success
        case .pairingRequired, .pairingTokenReady, .waitingForPeer, .exportingSnapshot, .waitingForEditedSnapshot, .validatingImport, .awaitingImportReview:
            return AccessibleColors.warning
        case .importCancelledByUser, .importRejectedDueToDrift, .trustRevoked, .trustExpired:
            return AccessibleColors.error
        }
    }

    private var lastSyncColor: Color {
        switch bridgeSnapshot.lastSyncOutcome {
        case .neverSynced:
            return AccessibleColors.secondaryText
        case .succeeded:
            return AccessibleColors.success
        case .failed:
            return AccessibleColors.error
        case .cancelled:
            return AccessibleColors.warning
        }
    }

    private var validationStateLabel: String {
        bridgeSnapshot.importReviewStatus.validationStatus.displayTitle
    }

    private var importValidationColor: Color {
        switch bridgeSnapshot.importReviewStatus.validationStatus {
        case .notRun:
            return AccessibleColors.secondaryText
        case .passed:
            return AccessibleColors.success
        case .warnings:
            return AccessibleColors.warning
        case .failed:
            return AccessibleColors.error
        }
    }

    private var importDriftColor: Color {
        switch bridgeSnapshot.importReviewStatus.driftStatus {
        case .unknown:
            return AccessibleColors.secondaryText
        case .none:
            return AccessibleColors.success
        case .additiveOnly:
            return AccessibleColors.warning
        case .conflicting, .destructive:
            return AccessibleColors.error
        }
    }

    private var importDecisionColor: Color {
        switch bridgeSnapshot.importReviewStatus.operatorDecision {
        case .notRequired:
            return AccessibleColors.secondaryText
        case .awaitingDecision:
            return AccessibleColors.warning
        case .approved:
            return AccessibleColors.success
        case .rejected:
            return AccessibleColors.error
        }
    }

    private func importSignatureColor(_ status: BridgeImportSignatureStatus) -> Color {
        switch status {
        case .notVerified:
            return AccessibleColors.warning
        case .valid:
            return AccessibleColors.success
        case .invalid, .signerUntrusted:
            return AccessibleColors.error
        }
    }

    private func validationOutcomeLabel(for device: TrustedBridgeDevice, outcome: BridgeValidationOutcome) -> String {
        let timestamp = device.lastValidationAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown time"
        return "Last validation: \(outcome.displayTitle) • \(timestamp)"
    }

    private var pairingMethods: [BridgePairingMethod] {
#if os(macOS)
        [.enterCodeManually, .pasteBootstrapToken]
#else
        [.enterCodeManually, .scanQR, .pasteBootstrapToken]
#endif
    }

    private var pairingEntryNavigationTitle: String {
        switch pairingMethod {
        case .enterCodeManually:
            return "Enter Pairing Code"
        case .scanQR:
            return "Scan QR"
        case .pasteBootstrapToken:
            return "Paste Token"
        }
    }

    private var pairingEntrySectionTitle: String {
        switch pairingMethod {
        case .enterCodeManually:
            return "Pairing Code"
        case .scanQR, .pasteBootstrapToken:
            return "Bootstrap Token"
        }
    }

    private var pairingEntryPlaceholder: String {
        switch pairingMethod {
        case .enterCodeManually:
            return "AbCd.EfGh.IjKl"
        case .scanQR:
            return "Scan QR code"
        case .pasteBootstrapToken:
            return "Paste bootstrap token"
        }
    }

    private var pairingEntryHelperCopy: String {
        switch pairingMethod {
        case .enterCodeManually:
            return "Enter the grouped pairing code shown on the Mac. This is a separate flow from pasting the full bootstrap token."
        case .scanQR:
            return "Camera access is requested only when the QR scanner opens. If scanning is unavailable, return here and use manual pairing."
        case .pasteBootstrapToken:
            return "Paste the full bootstrap token exactly as provided by the paired Mac."
        }
    }

    private func runPairingAction(for method: BridgePairingMethod) {
#if os(macOS)
        let resolvedMethod: BridgePairingMethod
        switch method {
        case .enterCodeManually, .pasteBootstrapToken:
            resolvedMethod = method
        case .scanQR:
            resolvedMethod = .enterCodeManually
        }
        controller.preparePairingToken(displayName: "CryptoSavingsTracker Mac", method: resolvedMethod)
        bridgeNotice = controller.operatorMessage
#else
        switch method {
        case .enterCodeManually:
            pairingTokenInput = ""
            presentsPairingTokenEntry = true
        case .scanQR:
            presentsQRScanner = true
        case .pasteBootstrapToken:
            #if os(iOS)
            pairingTokenInput = UIPasteboard.general.string ?? ""
            #else
            pairingTokenInput = ""
            #endif
            presentsPairingTokenEntry = true
        }
#endif
    }

    private func pairingActionTitle(for method: BridgePairingMethod) -> String {
        switch method {
        case .enterCodeManually:
            return "Pair Mac"
        case .scanQR:
            return "Scan QR"
        case .pasteBootstrapToken:
            return "Paste Bootstrap Token"
        }
    }

    private func pairingActionSystemImage(for method: BridgePairingMethod) -> String {
        switch method {
        case .enterCodeManually:
            return "link.badge.plus"
        case .scanQR:
            return "qrcode.viewfinder"
        case .pasteBootstrapToken:
            return "doc.on.clipboard"
        }
    }

    private func handleScannedBootstrapToken(_ token: String) {
        pairingMethod = .scanQR
        controller.pairMac(using: .scanQR, bootstrapTokenString: token)
        bridgeNotice = controller.operatorMessage
    }

    private func consumeNearbyBootstrapToken() {
        guard let token = nearbyTransport.consumeReceivedBootstrapToken() else { return }
        pairingMethod = .pasteBootstrapToken
        controller.pairMac(using: .pasteBootstrapToken, bootstrapTokenString: token)
        bridgeNotice = controller.operatorMessage
    }

    private func consumeNearbyArtifact() {
        guard let artifactURL = nearbyTransport.consumeReceivedArtifactURL() else { return }
        controller.loadImportPackage(from: artifactURL)
        bridgeNotice = controller.operatorMessage
    }

    private func fullBootstrapToken(for token: BridgeBootstrapToken) -> String {
        (try? token.encodedManualEntryToken()) ?? "Unavailable"
    }

    private func manualPairingCode(for token: BridgeBootstrapToken) -> String {
        (try? token.encodedPairingCode()) ?? "Unavailable"
    }

    private func redactedBootstrapToken(for token: BridgeBootstrapToken) -> String {
        BridgeObservabilityRedactor.redactedBootstrapToken(fullBootstrapToken(for: token))
    }

    private var nearbyStateColor: Color {
        switch nearbyTransport.state {
        case .idle:
            return AccessibleColors.secondaryText
        case .advertising, .browsing, .connecting, .transferring:
            return AccessibleColors.warning
        case .connected:
            return AccessibleColors.success
        case .failed:
            return AccessibleColors.error
        }
    }
}
