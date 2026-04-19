import Foundation
import SwiftUI
import Testing
@testable import CryptoSavingsTracker

struct FamilySharingCopyContractTests {
    @Test("family-sharing supporting copy stays user-facing on invite and retry states")
    func familySharingSupportingCopyStaysUserFacing() {
        #expect(
            FamilyShareSurfaceState.invitePendingAcceptance.supportingCopy
                == "Waiting for your family invitation to be accepted."
        )
        #expect(
            FamilyShareSurfaceState.temporarilyUnavailable.supportingCopy
                == "Shared goals aren't available right now."
        )
        #expect(
            FamilyShareOwnerIdentityResolver.canonicalSectionSummary(lifecycleState: .invitePendingAcceptance)
                == "Waiting for your family invitation to be accepted."
        )
        #expect(
            FamilyShareOwnerIdentityResolver.canonicalSectionSummary(lifecycleState: .temporarilyUnavailable)
                == "Shared goals aren't available right now."
        )
    }

    @Test("settings sync footer uses sync language instead of internal storage terminology")
    func settingsFooterUsesSyncLanguage() {
        #expect(
            SettingsView.syncSectionFooterCopy
                == "Sync keeps your latest savings data up to date, while local storage only supports cached helper data."
        )
    }

    @Test("public mvp settings excludes family access and local bridge sync rows")
    @MainActor
    func settingsExcludesFamilyAccessAndLocalBridgeSync() throws {
        let root = repositoryRoot()
        let source = try readSource(root, "ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift")
        let gatewaySource = try readSource(root, "ios/CryptoSavingsTracker/Services/SettingsSyncSharingGateway.swift")
        var familyDestinationBuilt = false
        var bridgeDestinationBuilt = false
        let gateway = RuntimeSettingsSyncSharingGateway(
            runtimeMode: .publicMVP,
            familyAccessDestinationFactory: { _ in
                familyDestinationBuilt = true
                return AnyView(Text("Family Access"))
            },
            localBridgeDestinationFactory: {
                bridgeDestinationBuilt = true
                return AnyView(Text("Local Bridge Sync"))
            }
        )

        let familyAccessRow = source.range(of: "settings.cloudkit.familyAccessRow")
        let localBridgeRow = source.range(of: "settings.cloudkit.localBridgeSyncRow")

        #expect(familyAccessRow == nil)
        #expect(localBridgeRow == nil)
        #expect(!source.contains("DIContainer.shared.familyShareAcceptanceCoordinator"))
        #expect(!source.contains("PersistenceController.shared.snapshot"))
        #expect(gatewaySource.contains("guard isSyncSharingSectionEnabled else"))
        #expect(gateway.isSyncSharingSectionEnabled == false)
        #expect(gateway.rows.isEmpty)

        _ = gateway.makeDestination(for: .familyAccess, activeGoals: [makeGoal()])
        _ = gateway.makeDestination(for: .localBridgeSync, activeGoals: [makeGoal()])
        #expect(familyDestinationBuilt == false)
        #expect(bridgeDestinationBuilt == false)
    }

    @Test("debug internal settings exposes family access before local bridge sync")
    @MainActor
    func debugInternalSettingsExposesFamilyAccessBeforeLocalBridgeSync() {
        var builtDestinations: [SettingsSyncSharingDestination] = []
        let gateway = RuntimeSettingsSyncSharingGateway(
            runtimeMode: .debugInternal,
            familyAccessDestinationFactory: { _ in
                builtDestinations.append(.familyAccess)
                return AnyView(Text("Family Access"))
            },
            localBridgeDestinationFactory: {
                builtDestinations.append(.localBridgeSync)
                return AnyView(Text("Local Bridge Sync"))
            }
        )

        #expect(gateway.isSyncSharingSectionEnabled)
        #expect(gateway.rows.map(\.destination) == [.familyAccess, .localBridgeSync])
        #expect(gateway.rows.map(\.accessibilityIdentifier) == [
            "settings.cloudkit.familyAccessRow",
            "settings.cloudkit.localBridgeSyncRow"
        ])
        #expect(gateway.rows.map(\.title) == ["Family Access", "Local Bridge Sync"])
        #expect(gateway.rows.map(\.accessibilityLabel) == ["Family Access", "Local Bridge Sync"])

        _ = gateway.makeDestination(for: .familyAccess, activeGoals: [makeGoal()])
        _ = gateway.makeDestination(for: .localBridgeSync, activeGoals: [makeGoal()])
        #expect(builtDestinations == [.familyAccess, .localBridgeSync])
    }

    @Test("enabled family access destination receives active goals")
    @MainActor
    func enabledFamilyAccessDestinationReceivesActiveGoals() {
        let activeGoal = makeGoal()
        var receivedGoals: [Goal] = []
        let gateway = RuntimeSettingsSyncSharingGateway(
            runtimeMode: .debugInternal,
            familyAccessDestinationFactory: { goals in
                receivedGoals = goals
                return AnyView(Text("Family Access"))
            }
        )

        _ = gateway.makeDestination(for: .familyAccess, activeGoals: [activeGoal])

        #expect(receivedGoals.count == 1)
        #expect(receivedGoals.first === activeGoal)
    }

    @Test("test-run family share CloudKit store construction does not resolve CKContainer")
    func testRunFamilyShareCloudKitStoreConstructionDoesNotResolveContainer() throws {
        let root = repositoryRoot()
        let source = try readSource(root, "ios/CryptoSavingsTracker/Utilities/DIContainer.swift")
        let store = DefaultFamilyShareCloudKitStore(environment: .preview)

        #expect(store.lastPublishServerTimestamp == nil)
        #expect(source.contains("familyShareCloudSyncForRuntime"))
        #expect(source.contains("FamilyShareCacheStoreEnvironment.current().isTestRun ? nil : familyShareCloudKitStore"))
    }

    @Test("w4 release gate inventory matches required command matrix")
    func w4ReleaseGateInventoryMatchesRequiredCommandMatrix() throws {
        let root = repositoryRoot()
        let fileManager = FileManager.default
        let unitTestPaths = [
            "ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareAcceptanceCoordinatorTests.swift",
            "ios/CryptoSavingsTrackerTests/PersistenceMutationServicesTests.swift",
            "ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessLabelTests.swift",
            "ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareFreshnessPolicyTests.swift",
            "ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareForegroundRateRefreshDriverTests.swift",
            "ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareInviteeRefreshSchedulerTests.swift",
            "ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareRateDriftEvaluatorTests.swift",
            "ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareReconciliationBarrierTests.swift",
            "ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareProjectionAutoRepublishCoordinatorTests.swift",
            "ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareInviteeOrderingTests.swift",
            "ios/CryptoSavingsTrackerTests/FamilySharing/FamilyShareMaterialityPolicyTests.swift",
            "ios/CryptoSavingsTrackerTests/FamilySharing/GoalProgressCalculatorTests.swift"
        ]
        let uiTestMethods = [
            "testSettingsShowsFamilyAccessBeforeLocalBridgeSync",
            "testInviteeScenarioShowsSharedWithYouAndReadOnlyDetail",
            "testInviteeScenarioShowsMultiOwnerGroupingAndStickyOwnerHeaders",
            "testInviteeScenarioShowsNonActiveStateBannerAndPrimaryAction",
            "testInviteeScenarioSuppressesBlockedDeviceOwnerLabels",
            "testInviteeScenarioUsesLockedOwnershipLineAndSuppressesHealthyLifecycleChip",
            "testScopePreviewKeepsPersistentCTAVisibleAtAccessibilitySize",
            "testInviteeEmptyNamespaceShowsFreshnessHeaderButNoRows",
            "testInviteeUnavailableNamespaceShowsRetryWithoutRows",
            "testInviteeDetailFreshnessCardCollapsesExactTimestampAtAccessibilitySize"
        ]
        let evidenceOwner = "iOS Release Captain"
        let missingTestEscalationThreshold = 1
        let familySharingUITests = try readSource(
            root,
            "ios/CryptoSavingsTrackerUITests/FamilySharing/FamilySharingUITests.swift"
        )
        let uiTestBootstrap = try readSource(root, "ios/CryptoSavingsTracker/Views/Shared/UITestBootstrapView.swift")
        let contentView = try readSource(root, "ios/CryptoSavingsTracker/Views/ContentView.swift")
        let goalsListContainer = try readSource(root, "ios/CryptoSavingsTracker/Views/Goals/GoalsListContainer.swift")
        let sharedGoalsSectionView = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/FamilySharing/SharedGoalsSectionView.swift"
        )
        let missingUnitTests = unitTestPaths.filter {
            !fileManager.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        let missingUITestMethods = uiTestMethods.filter {
            !familySharingUITests.contains("func \($0)(")
        }
        let missingTestCount = missingUnitTests.count + missingUITestMethods.count

        #expect(unitTestPaths.count == 12)
        #expect(missingUnitTests.isEmpty)
        #expect(uiTestMethods.count == 10)
        #expect(missingUITestMethods.isEmpty)
        #expect(evidenceOwner == "iOS Release Captain")
        #expect(missingTestEscalationThreshold == 1)
        #expect(missingTestCount < missingTestEscalationThreshold)
        #expect(familySharingUITests.contains("app.launchEnvironment[\"CST_RUNTIME_MODE\"] = \"debug_internal\""))
        #expect(uiTestBootstrap.contains("UITestFlags.familyShareScenario"))
        #expect(uiTestBootstrap.contains("seedUITestScenario(familyShareScenario)"))
        #expect(contentView.contains("UITestFlags.familyShareScenario"))
        #expect(contentView.contains("return .goals"))
        #expect(goalsListContainer.contains("HiddenRuntimeMode.current.allowsFamilySharing"))
        #expect(goalsListContainer.contains("SharedGoalsSectionView("))
        #expect(goalsListContainer.contains("SharedGoalDetailView(goal: goal)"))
        #expect(goalsListContainer.contains(".accessibilityIdentifier(\"sharedGoalsSection\")"))
        #expect(sharedGoalsSectionView.contains("sharedGoalsOwnerSection-\\(section.uiTestIdentifier)"))
    }

    @Test("family-sharing state copy is user-facing in revoked/unavailable states")
    func familySharingLifecycleCopyRemainsUserFacing() {
        #expect(FamilyShareSurfaceState.revoked.supportingCopy == "The owner removed access to the shared dataset.")
        #expect(FamilyShareSurfaceState.temporarilyUnavailable.supportingCopy == "Shared goals aren't available right now.")
        #expect(FamilyShareSurfaceState.removedOrNoLongerShared.supportingCopy == "The shared dataset is no longer available for this invitee.")

        #expect(!FamilyShareSurfaceState.revoked.supportingCopy.localizedCaseInsensitiveContains("CloudKit"))
        #expect(!FamilyShareSurfaceState.temporarilyUnavailable.supportingCopy.localizedCaseInsensitiveContains("CloudKit"))
        #expect(!FamilyShareSurfaceState.removedOrNoLongerShared.supportingCopy.localizedCaseInsensitiveContains("CloudKit"))

        #expect(FamilyShareOwnerIdentityResolver.canonicalSectionSummary(lifecycleState: .revoked)
            == "The owner removed access to the shared dataset.")
        #expect(FamilyShareOwnerIdentityResolver.canonicalSectionSummary(lifecycleState: .removedOrNoLongerShared)
            == "The shared dataset is no longer available for this invitee.")
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readSource(_ root: URL, _ relativePath: String) throws -> String {
        let fileURL = root.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func makeGoal() -> Goal {
        Goal(
            name: "Family Goal",
            currency: "USD",
            targetAmount: 1_000,
            deadline: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}
