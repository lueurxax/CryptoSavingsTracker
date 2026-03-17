import SwiftUI

struct BridgeImportReviewView: View {
    let status: BridgeImportReviewStatus
    let onApprove: () -> Void
    let onReject: () -> Void
    let onResetPending: () -> Void

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
            }

            if let review = status.reviewSummaryDTO {
                Section("Signed Package") {
                    LabeledContent("Package ID") {
                        Text(review.package.packageID.uuidString)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .accessibilityIdentifier("localBridge.importReview.packageID")

                    LabeledContent("Source Device") {
                        Text(review.package.sourceDeviceName)
                    }
                    .accessibilityIdentifier("localBridge.importReview.sourceDevice")

                    LabeledContent("Canonical Encoding") {
                        Text(review.package.canonicalEncodingVersion)
                    }
                    .accessibilityIdentifier("localBridge.importReview.encoding")

                    LabeledContent("Signature") {
                        Text(review.package.signatureStatus.displayTitle)
                            .foregroundStyle(signatureColor(review.package.signatureStatus))
                    }
                    .accessibilityIdentifier("localBridge.importReview.signature")
                }

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
                                .foregroundStyle(.orange)
                        }
                    }

                    if !review.blockingIssues.isEmpty {
                        ForEach(review.blockingIssues, id: \.self) { issue in
                            Text("• \(issue)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
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
                Section("Signed Package") {
                    Text("No signed package is currently loaded for review.")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("localBridge.importReview.noPackage")
            }

            Section("Operator Actions") {
                Button("Approve (No Apply)") {
                    onApprove()
                }
                .disabled(status.reviewSummaryDTO == nil)
                .accessibilityIdentifier("localBridge.importReview.approve")

                Button("Reject") {
                    onReject()
                }
                .disabled(status.reviewSummaryDTO == nil)
                .accessibilityIdentifier("localBridge.importReview.reject")

                Button("Reset to Pending") {
                    onResetPending()
                }
                .disabled(status.reviewSummaryDTO == nil)
                .accessibilityIdentifier("localBridge.importReview.resetPending")
            }

            Section("Phase 2A Scope") {
                Text("This operator surface now reflects the bridge snapshot/package contract and structural validation results. Signature verification, transport I/O, and import apply are intentionally not implemented.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("localBridge.importReview.scope")
            }
        }
        .navigationTitle("Import Review")
    }

    private var operatorDecisionColor: Color {
        switch status.operatorDecision {
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

    private func signatureColor(_ status: BridgeImportSignatureStatus) -> Color {
        switch status {
        case .notVerified:
            return .orange
        case .valid:
            return .green
        case .invalid, .signerUntrusted:
            return .red
        }
    }

    private func validationColor(_ status: BridgeImportValidationStatus) -> Color {
        switch status {
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

    private func driftColor(_ status: BridgeImportDriftStatus) -> Color {
        switch status {
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
}
