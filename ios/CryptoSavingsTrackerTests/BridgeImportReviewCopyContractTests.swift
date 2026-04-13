import Testing
@testable import CryptoSavingsTracker

struct BridgeImportReviewCopyContractTests {
    @Test("bridge import review copy uses sync language")
    func bridgeImportReviewUsesSyncLanguage() throws {
        let root = repositoryRoot()
        let source = try readSource(root, "ios/CryptoSavingsTracker/Views/Settings/BridgeImportReviewView.swift")

        #expect(source.contains("Approve & Apply to Sync Runtime"))
        #expect(source.contains("sync runtime only after explicit approval"))
        #expect(!source.contains("CloudKit-backed"))
        #expect(!source.contains("Apply targets the CloudKit"))
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
