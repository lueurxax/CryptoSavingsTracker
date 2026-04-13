import SwiftUI

struct BridgeImportReviewView: View {
    @ObservedObject var controller: LocalBridgeSyncController

    private var status: BridgeImportReviewStatus {
        controller.importReviewStatus
    }

    var body: some View {
        Form {
            Section("Review Summary") {
                Text(status.summary)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("localBridge.importReview.summary")

                LabeledContent("Operator Decision") {
                    Text(status.operatorDecision.displayTitle)
                        .foregroundStyle(operatorDecisionColor)
                }
                .accessibilityIdentifier("localBridge.importReview.operatorDecision")
                .accessibilityValue(status.operatorDecision.displayTitle)
            }

            if let review = status.reviewSummaryDTO {
                Section("Validation & Drift") {
                    LabeledContent("Validation") {
                        Text(review.validationStatus.displayTitle)
                            .foregroundStyle(validationColor(review.validationStatus))
                    }
                    .accessibilityIdentifier("localBridge.importReview.validation")

                    LabeledContent("Drift") {
                        Text(review.driftStatus.displayTitle)
                            .foregroundStyle(driftColor(review.driftStatus))
                    }
                    .accessibilityIdentifier("localBridge.importReview.drift")

                    if !review.warnings.isEmpty {
                        ForEach(review.warnings, id: \.self) { warning in
                            Text("• \(warning)")
                                .font(.caption)
                                .foregroundStyle(AccessibleColors.warning)
                        }
                    }

                    if !review.blockingIssues.isEmpty {
                        ForEach(review.blockingIssues, id: \.self) { issue in
                            Text("• \(issue)")
                                .font(.caption)
                                .foregroundStyle(AccessibleColors.error)
                        }
                    }
                }

                Section("Concrete Diffs") {
                    ForEach(review.concreteDiffs) { diff in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(diff.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(diff.changeKind.displayTitle)
                                    .font(.caption)
                                    .foregroundStyle(changeKindColor(diff.changeKind))
                            }
                            if let beforeSummary = diff.beforeSummary {
                                Text("Before: \(beforeSummary)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let afterSummary = diff.afterSummary {
                                Text("After: \(afterSummary)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("localBridge.importReview.concreteDiffs")

                Section("Operator Actions") {
                    Button("Approve & Apply to Sync Runtime") {
                        controller.markImportDecision(.approved)
                    }
                    .disabled(!status.blockingIssues.isEmpty)
                    .accessibilityIdentifier("localBridge.importReview.approve")

                    Button("Reject") {
                        controller.markImportDecision(.rejected)
                    }
                    .accessibilityIdentifier("localBridge.importReview.reject")

                    Button("Reset to Pending") {
                        controller.markImportDecision(.awaitingDecision)
                    }
                    .accessibilityIdentifier("localBridge.importReview.resetPending")

                    if let applyBlockingReason {
                        Text(applyBlockingReason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("localBridge.importReview.applyHint")
                    }
                }

                Section("Signed Package") {
                    LabeledContent("Package ID") {
                        let metadata = LocalBridgeIdentifierPresentation.metadata(
                            title: "Package ID",
                            value: review.package.packageID
                        )
                        Text(review.package.packageID)
                            .font(.caption.monospaced())
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(metadata.label)
                            .accessibilityValue(metadata.value)
                            .accessibilityHint(metadata.hint)
                    }
                    .accessibilityIdentifier("localBridge.importReview.packageID")

                    LabeledContent("Source Device") {
                        Text(review.package.sourceDeviceName)
                    }
                    .accessibilityIdentifier("localBridge.importReview.sourceDevice")

                    LabeledContent("Source Fingerprint") {
                        let metadata = LocalBridgeIdentifierPresentation.metadata(
                            title: "Source Fingerprint",
                            value: review.package.sourceDeviceFingerprint
                        )
                        Text(review.package.sourceDeviceFingerprint)
                            .font(.caption.monospaced())
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(metadata.label)
                            .accessibilityValue(metadata.value)
                            .accessibilityHint(metadata.hint)
                    }
                    .accessibilityIdentifier("localBridge.importReview.sourceFingerprint")

                    LabeledContent("Canonical Encoding") {
                        Text(review.package.canonicalEncodingVersion)
                    }
                    .accessibilityIdentifier("localBridge.importReview.encoding")

                    LabeledContent("Produced At") {
                        Text(review.package.producedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .accessibilityIdentifier("localBridge.importReview.producedAt")

                    LabeledContent("Expires At") {
                        Text(review.package.expiresAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .accessibilityIdentifier("localBridge.importReview.expiresAt")

                    LabeledContent("Payload Size") {
                        Text(ByteCountFormatter.string(fromByteCount: review.package.payloadBytes, countStyle: .file))
                    }
                    .accessibilityIdentifier("localBridge.importReview.payloadBytes")

                    LabeledContent("Digest Prefix") {
                        Text(review.package.digestHexPrefix)
                            .font(.caption.monospaced())
                    }
                    .accessibilityIdentifier("localBridge.importReview.digestPrefix")

                    LabeledContent("Signature") {
                        Text(review.package.signatureStatus.displayTitle)
                            .foregroundStyle(signatureColor(review.package.signatureStatus))
                    }
                    .accessibilityIdentifier("localBridge.importReview.signature")

                    LabeledContent("Trust") {
                        Text(review.package.trustStatus.displayTitle)
                            .foregroundStyle(trustColor(review.package.trustStatus))
                    }
                    .accessibilityIdentifier("localBridge.importReview.trust")
                }

                if !review.entityDeltas.isEmpty {
                    Section("Entity Deltas") {
                        ForEach(review.entityDeltas, id: \.entityName) { delta in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(delta.entityName)
                                    .font(.subheadline.weight(.semibold))
                                Text("Incoming: \(delta.incomingCount) • Existing: \(delta.existingCount) • Changed: \(delta.changedCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("localBridge.importReview.entityDeltas")
                }
            } else {
                Section("Operator Actions") {
                    Button("Approve & Apply to Sync Runtime") {
                        controller.markImportDecision(.approved)
                    }
                    .disabled(true)
                    .accessibilityIdentifier("localBridge.importReview.approve")

                    Button("Reject") {
                        controller.markImportDecision(.rejected)
                    }
                    .disabled(true)
                    .accessibilityIdentifier("localBridge.importReview.reject")

                    Button("Reset to Pending") {
                        controller.markImportDecision(.awaitingDecision)
                    }
                    .disabled(true)
                    .accessibilityIdentifier("localBridge.importReview.resetPending")
                }

                Section("Signed Package") {
                    Text("No signed package is currently loaded for review.")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("localBridge.importReview.noPackage")
            }

            Section("Phase 2A Scope") {
                Text("This operator surface validates a signed package artifact loaded from local file transport and applies it to the sync runtime only after explicit approval.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("localBridge.importReview.scope")
            }
        }
        .navigationTitle("Import Review")
    }

    private var operatorDecisionColor: Color {
        switch status.operatorDecision {
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

    private func signatureColor(_ status: BridgeImportSignatureStatus) -> Color {
        switch status {
        case .notVerified:
            return AccessibleColors.warning
        case .valid:
            return AccessibleColors.success
        case .invalid, .signerUntrusted:
            return AccessibleColors.error
        }
    }

    private func validationColor(_ status: BridgeImportValidationStatus) -> Color {
        switch status {
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

    private func trustColor(_ status: BridgeImportTrustStatus) -> Color {
        switch status {
        case .activeTrusted:
            return AccessibleColors.success
        case .signerUntrusted, .trustRevoked:
            return AccessibleColors.error
        }
    }

    private func driftColor(_ status: BridgeImportDriftStatus) -> Color {
        switch status {
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

    private func changeKindColor(_ changeKind: BridgeImportChangeKind) -> Color {
        switch changeKind {
        case .added:
            return AccessibleColors.success
        case .updated:
            return AccessibleColors.warning
        case .deleted:
            return AccessibleColors.error
        }
    }

    private var applyBlockingReason: String? {
        guard let review = status.reviewSummaryDTO else {
            return "Load a signed bridge package from Files before operator review can apply anything."
        }
        if !status.blockingIssues.isEmpty {
            return "Apply stays disabled until all blocking validation issues are resolved."
        }
        switch review.package.signatureStatus {
        case .valid:
            return "Apply targets the authoritative sync runtime and requires explicit operator approval."
        case .notVerified:
            return "Apply stays disabled until the package signature is verified."
        case .invalid:
            return "Apply stays disabled because the package signature is invalid."
        case .signerUntrusted:
            return "Apply stays disabled because the package signer is not trusted on this install."
        }
    }
}
