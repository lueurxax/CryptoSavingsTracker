import Foundation
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
    func settingsExcludesFamilyAccessAndLocalBridgeSync() throws {
        let root = repositoryRoot()
        let source = try readSource(root, "ios/CryptoSavingsTracker/Views/Settings/SettingsView.swift")

        let familyAccessRow = source.range(of: "settings.cloudkit.familyAccessRow")
        let localBridgeRow = source.range(of: "settings.cloudkit.localBridgeSyncRow")

        #expect(familyAccessRow == nil)
        #expect(localBridgeRow == nil)
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
}
