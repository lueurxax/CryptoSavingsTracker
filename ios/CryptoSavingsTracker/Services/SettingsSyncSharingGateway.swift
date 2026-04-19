//
//  SettingsSyncSharingGateway.swift
//  CryptoSavingsTracker
//

import SwiftUI

enum SettingsSyncSharingDestination: String, Sendable {
    case familyAccess
    case localBridgeSync
}

struct SettingsSyncSharingRow: Identifiable, Equatable, Sendable {
    let destination: SettingsSyncSharingDestination
    let title: String
    let detail: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let systemImage: String

    var id: String { accessibilityIdentifier }

    static let familyAccess = SettingsSyncSharingRow(
        destination: .familyAccess,
        title: "Family Access",
        detail: "Share goals with family.",
        accessibilityLabel: "Family Access",
        accessibilityIdentifier: "settings.cloudkit.familyAccessRow",
        systemImage: "person.2.fill"
    )

    static let localBridgeSync = SettingsSyncSharingRow(
        destination: .localBridgeSync,
        title: "Local Bridge Sync",
        detail: "Review local sync handoffs.",
        accessibilityLabel: "Local Bridge Sync",
        accessibilityIdentifier: "settings.cloudkit.localBridgeSyncRow",
        systemImage: "arrow.triangle.2.circlepath"
    )
}

@MainActor
protocol SettingsSyncSharingGateway: AnyObject {
    var isSyncSharingSectionEnabled: Bool { get }
    var rows: [SettingsSyncSharingRow] { get }

    func makeDestination(for row: SettingsSyncSharingRow, activeGoals: [Goal]) -> AnyView
}

@MainActor
final class RuntimeSettingsSyncSharingGateway: SettingsSyncSharingGateway {
    private let runtimeModeProvider: () -> HiddenRuntimeMode
    private let familyAccessDestinationFactory: ([Goal]) -> AnyView
    private let localBridgeDestinationFactory: () -> AnyView

    init(
        runtimeMode: HiddenRuntimeMode? = nil,
        runtimeModeProvider: (() -> HiddenRuntimeMode)? = nil,
        familyAccessDestinationFactory: (([Goal]) -> AnyView)? = nil,
        localBridgeDestinationFactory: (() -> AnyView)? = nil
    ) {
        if let runtimeMode {
            self.runtimeModeProvider = { runtimeMode }
        } else {
            self.runtimeModeProvider = runtimeModeProvider ?? { HiddenRuntimeMode.current }
        }
        self.familyAccessDestinationFactory = familyAccessDestinationFactory ?? Self.makeFamilyAccessDestination
        self.localBridgeDestinationFactory = localBridgeDestinationFactory ?? Self.makeLocalBridgeDestination
    }

    private var runtimeMode: HiddenRuntimeMode {
        runtimeModeProvider()
    }

    var isSyncSharingSectionEnabled: Bool {
        runtimeMode.allowsFamilySharing
    }

    var rows: [SettingsSyncSharingRow] {
        guard isSyncSharingSectionEnabled else { return [] }
        return [.familyAccess, .localBridgeSync]
    }

    func makeDestination(for row: SettingsSyncSharingRow, activeGoals: [Goal]) -> AnyView {
        guard isSyncSharingSectionEnabled else {
            return AnyView(EmptyView())
        }

        switch row.destination {
        case .familyAccess:
            return familyAccessDestinationFactory(activeGoals)
        case .localBridgeSync:
            return localBridgeDestinationFactory()
        }
    }

    private static func makeFamilyAccessDestination(activeGoals: [Goal]) -> AnyView {
        let coordinator = DIContainer.shared.familyShareAcceptanceCoordinator
        return AnyView(
            FamilyAccessView(
                model: coordinator.makeFamilyAccessModel(currentGoals: activeGoals),
                onShareWithFamily: {
                    Task { await coordinator.shareAllGoals(activeGoals) }
                },
                onRefresh: {
                    Task { await coordinator.refreshFamilyAccessOwnerData(currentGoals: activeGoals) }
                },
                onShowScopePreview: {},
                onShowParticipants: {
                    Task { await coordinator.manageParticipants() }
                }
            )
            .environmentObject(coordinator)
            .navigationTitle(SettingsSyncSharingRow.familyAccess.title)
        )
    }

    private static func makeLocalBridgeDestination() -> AnyView {
        AnyView(
            LocalBridgeSyncView(persistenceSnapshot: PersistenceController.shared.snapshot)
                .navigationTitle(SettingsSyncSharingRow.localBridgeSync.title)
        )
    }
}
