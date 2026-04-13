//
//  CommitDock.swift
//  CryptoSavingsTracker
//
//  Commit dock that collapses into a trailing FAB pill on scroll.
//  Uses a discrete DockPhase enum to prevent render churn.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Public types (accessible to tests & analytics)

/// Discrete dock display phase — expanded full dock or collapsed FAB pill.
enum DockPhase: Equatable {
    case expanded
    case collapsed
}

/// Origin of the scroll event driving phase changes.
enum ScrollOrigin: Equatable {
    case userScroll
    case programmaticReset(ProgrammaticResetReason)
}

/// Reason for a programmatic scroll reset.
enum ProgrammaticResetReason: Equatable {
    case sheetDismiss
    case tabSwitch
    case planReload
}

/// Focus targets within the dock subtree for deterministic VoiceOver transfer.
enum DockFocusTarget: Hashable {
    case expandedButton
    case fab
}

// MARK: - Pure reducer

/// Pure, testable phase reducer with hysteresis.
///
/// - `userScroll`: enter collapsed at 0.60, exit at 0.45, gap preserves current.
/// - `sheetDismiss`: preserve current phase (no jarring jump).
/// - `tabSwitch` / `planReload`: force expanded.
func reduceDockPhase(current: DockPhase, progress: CGFloat, origin: ScrollOrigin) -> DockPhase {
    switch origin {
    case .programmaticReset(let reason):
        switch reason {
        case .sheetDismiss:
            return current
        case .tabSwitch, .planReload:
            return .expanded
        }
    case .userScroll:
        let enterThreshold: CGFloat = 0.60
        let exitThreshold: CGFloat = 0.45

        switch current {
        case .expanded:
            return progress >= enterThreshold ? .collapsed : .expanded
        case .collapsed:
            return progress <= exitThreshold ? .expanded : .collapsed
        }
    }
}

/// Pure, testable size-class gating for effective phase.
/// Collapse only applies on iOS compact; all other contexts remain expanded.
func resolveEffectivePhase(phase: DockPhase, isCompact: Bool) -> DockPhase {
    guard isCompact else { return .expanded }
    return phase
}

/// Pure, testable focus transfer logic for VoiceOver focus ownership contract (§9.1.1).
/// Returns the new focus target only if the dock subtree currently owns focus.
func resolveFocusTransfer(newPhase: DockPhase, dockHasFocus: Bool) -> DockFocusTarget? {
    guard dockHasFocus else { return nil }
    switch newPhase {
    case .collapsed: return .fab
    case .expanded:  return .expandedButton
    }
}

// MARK: - CommitDock View

struct CommitDock: View {
    let phase: DockPhase
    @Binding var showConfirmation: Bool
    let planningMonthLabel: String

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var analyticsTracker = CommitDockAnalyticsTracker()
    @AccessibilityFocusState private var focusTarget: DockFocusTarget?

    /// Whether the dock subtree currently owns VoiceOver focus.
    private var dockHasFocus: Bool {
        focusTarget != nil
    }

    private var effectivePhase: DockPhase {
        #if os(iOS)
        guard sizeClass == .compact else { return .expanded }
        return phase
        #else
        return .expanded
        #endif
    }

    private var baselineStroke: Color {
        #if os(iOS)
        Color(UIColor.separator).opacity(0.55)
        #else
        Color.primary.opacity(0.12)
        #endif
    }

    private var fabShadowColor: Color {
        colorScheme == .dark
            ? Color.primary.opacity(0.20)
            : Color.primary.opacity(0.12)
    }

    private var undoCopy: String {
        MonthlyPlanningSettings.shared.undoWindowString
    }

    private var monthFull: String {
        formatMonth(planningMonthLabel, pattern: "MMMM yyyy")
    }

    private var monthCompact: String {
        formatMonth(planningMonthLabel, pattern: "MMM yyyy")
    }

    private var startLabelFull: String {
        "Start Tracking \(monthFull)"
    }

    private var startLabelCompact: String {
        "Start \(monthFull)"
    }

    private var startLabelTight: String {
        "Start \(monthCompact)"
    }

    var body: some View {
        Group {
            switch effectivePhase {
            case .expanded:
                expandedContent
            case .collapsed:
                collapsedContent
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: effectivePhase)
        .onAppear {
            analyticsTracker.reset()
            CommitDockAnalytics.log(.impression, properties: [
                "mode": effectivePhase == .expanded ? "expanded" : "collapsed"
            ])
        }
        .onChange(of: effectivePhase) { _, newPhase in
            analyticsTracker.logPhaseChange(to: newPhase)
            // Focus ownership contract §9.1.1: transfer focus only if dock subtree owns it.
            if let target = resolveFocusTransfer(newPhase: newPhase, dockHasFocus: dockHasFocus) {
                focusTarget = target
            }
        }
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        VStack(spacing: 8) {
            Divider()

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AccessibleColors.success)
                    .font(.title3)

                Text("Ready to start \(monthFull)?")
                    .font(.headline)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .accessibilityHidden(true)

            Text("This starts contribution tracking for \(monthFull). You can undo within \(undoCopy).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .minimumScaleFactor(0.9)
                .accessibilityHidden(true)

            Button {
                showConfirmation = true
                CommitDockAnalytics.log(.fullButtonTap)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                    ViewThatFits(in: .horizontal) {
                        Text(startLabelFull)
                        Text(startLabelCompact)
                        Text(startLabelTight)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityIdentifier("startTrackingButton")
            .accessibilityLabel(startLabelFull)
            .accessibilityHint("Double tap to start tracking contributions for \(monthFull). You can undo within \(undoCopy).")
            .accessibilityFocused($focusTarget, equals: .expandedButton)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(baselineStroke)
                .frame(height: 1)
        }
    }

    // MARK: - Collapsed content (FAB pill)

    private var collapsedContent: some View {
        HStack {
            Spacer()

            Button {
                showConfirmation = true
                CommitDockAnalytics.log(.fabTap)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                    ViewThatFits(in: .horizontal) {
                        Text(startLabelCompact)
                        Text(startLabelTight)
                        Text("Start")
                    }
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(baselineStroke, lineWidth: 1)
            )
            .shadow(color: fabShadowColor, radius: 4, x: 0, y: 2)
            .frame(minHeight: 44)
            .accessibilityIdentifier("startTrackingButton")
            .accessibilityLabel(startLabelFull)
            .accessibilityHint("Double tap to start tracking contributions for \(monthFull). You can undo within \(undoCopy).")
            .accessibilityFocused($focusTarget, equals: .fab)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(baselineStroke)
                .frame(height: 1)
        }
    }

    private func formatMonth(_ label: String, pattern: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.timeZone = TimeZone(identifier: "UTC")
        inputFormatter.dateFormat = "yyyy-MM"
        guard let date = inputFormatter.date(from: label) else { return label }

        let outputFormatter = DateFormatter()
        outputFormatter.locale = Locale.current
        outputFormatter.timeZone = TimeZone(identifier: "UTC")
        outputFormatter.dateFormat = pattern
        return outputFormatter.string(from: date)
    }
}

// MARK: - Previews
