import Foundation
import Testing

struct CryptoTrackingVocabularyContractTests {
    @Test("Retained crypto flow surfaces the public tracking vocabulary")
    func retainedCryptoFlowShowsExplicitTrackingStates() throws {
        let root = repositoryRoot()
        let balanceState = try readSource(root, "ios/CryptoSavingsTracker/Models/BalanceState.swift")
        let assetViewModel = try readSource(root, "ios/CryptoSavingsTracker/ViewModels/AssetViewModel.swift")
        let addAssetView = try readSource(root, "ios/CryptoSavingsTracker/Views/AddAssetView.swift")

        for label in ["Connecting", "Syncing", "Connected", "Stale", "Needs Attention"] {
            #expect(balanceState.contains("\"\(label)\""))
            #expect(addAssetView.contains(label))
        }

        #expect(assetViewModel.contains("publicCryptoTrackingStatus"))
        #expect(assetViewModel.contains("publicTrackingStatusDetail"))
        #expect(addAssetView.contains("last successful balance stays visible"))
        #expect(addAssetView.contains("Wallet addresses are optional"))
        #expect(addAssetView.contains("read-only"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readSource(_ root: URL, _ relativePath: String) throws -> String {
        let fileURL = root.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
