//
//  FamilyShareScopePreviewSheet.swift
//  CryptoSavingsTracker
//

import SwiftUI

struct FamilyShareScopePreviewSheet: View {
    let model: FamilyShareScopePreviewModel
    let onContinue: () -> Void
    let onCancel: () -> Void

    @State private var expandedSections: Set<FamilyShareScopeDisclosureSection.Kind> = []
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCard
                    disclosureSections
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Share with Family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
        }
    }

    private var summaryCard: some View {
        FamilySharingCard(
            title: model.ownerName,
            systemImage: "person.2.fill",
            tint: AccessibleColors.primaryInteractive
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Read-only family sharing will include all current goals and future goals created while access remains active.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(model.summaryPoints.enumerated()), id: \.offset) { _, point in
                        Label(point, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var disclosureSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(model.sections) { section in
                DisclosureGroup(
                    isExpanded: binding(for: section.kind),
                    content: {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(section.rows, id: \.self) { row in
                                Label(row, systemImage: "circle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 10)
                    },
                    label: {
                        HStack {
                            Text(section.title)
                                .font(.headline)
                            Spacer(minLength: 0)
                        }
                    }
                )
                .tint(AccessibleColors.primaryInteractive)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: VisualComponentTokens.dashboardCardCornerRadius)
                        .fill(VisualComponentTokens.dashboardCardPrimaryFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: VisualComponentTokens.dashboardCardCornerRadius)
                        .stroke(VisualComponentTokens.dashboardCardStroke, lineWidth: 1)
                )
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            Divider()
            if UITestFlags.isEnabled {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 1)
                    .accessibilityIdentifier("familyShareScopePreviewActionBar")
            }
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, 8)
            .background(actionBarBackground)
        }
        .accessibilityElement(children: .contain)
    }

    private var actionBarBackground: some View {
        Color(.secondarySystemBackground)
            .overlay(alignment: .top) {
                Divider()
            }
    }

    private func binding(for kind: FamilyShareScopeDisclosureSection.Kind) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(kind) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(kind)
                } else {
                    expandedSections.remove(kind)
                }
            }
        )
    }
}
