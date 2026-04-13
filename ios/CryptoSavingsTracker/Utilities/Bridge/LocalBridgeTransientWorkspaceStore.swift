import Foundation

enum LocalBridgeTransientWorkspaceStoreError: LocalizedError {
    case invalidWorkspace
    case missingWorkspace

    var errorDescription: String? {
        switch self {
        case .invalidWorkspace:
            return "The transient bridge workspace could not be decoded."
        case .missingWorkspace:
            return "No transient bridge workspace is currently loaded."
        }
    }
}

final class LocalBridgeTransientWorkspaceStore {
    private let fileManager: FileManager
    private let appSupportURL: URL

    init(
        fileManager: FileManager = .default,
        appSupportURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.appSupportURL = appSupportURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    func save(_ snapshot: SnapshotEnvelope, workspaceID: UUID? = nil, createdAt: Date? = nil) throws -> LocalBridgeTransientWorkspaceArtifact {
        try ensureDirectoryExists(workspaceDirectoryURL)
        let id = workspaceID ?? UUID()
        let fileURL = workspaceDirectoryURL.appendingPathComponent("bridge-workspace-\(id.uuidString).json")
        try snapshot.canonicalEncodingData().write(to: fileURL, options: .atomic)
        return LocalBridgeTransientWorkspaceArtifact(
            workspaceID: id,
            createdAt: createdAt ?? Date(),
            fileURL: fileURL
        )
    }

    func load() throws -> (artifact: LocalBridgeTransientWorkspaceArtifact, snapshot: SnapshotEnvelope) {
        let latestURL = try latestWorkspaceURL()
        let data = try Data(contentsOf: latestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let snapshot = try? decoder.decode(SnapshotEnvelope.self, from: bridgeNormalizedCanonicalDecodingData(data)) else {
            throw LocalBridgeTransientWorkspaceStoreError.invalidWorkspace
        }

        let values = try latestURL.resourceValues(forKeys: [.creationDateKey])
        let createdAt = values.creationDate ?? Date()
        let workspaceID = UUID(uuidString: latestURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "bridge-workspace-", with: "")) ?? UUID()

        return (
            LocalBridgeTransientWorkspaceArtifact(
                workspaceID: workspaceID,
                createdAt: createdAt,
                fileURL: latestURL
            ),
            snapshot
        )
    }

    func clear() {
        guard fileManager.fileExists(atPath: workspaceDirectoryURL.path) else { return }
        let urls = (try? fileManager.contentsOfDirectory(at: workspaceDirectoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for url in urls {
            try? fileManager.removeItem(at: url)
        }
    }

    private var workspaceDirectoryURL: URL {
        appSupportURL.appendingPathComponent("LocalBridgeWorkspace", isDirectory: true)
    }

    private func ensureDirectoryExists(_ directoryURL: URL) throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private func latestWorkspaceURL() throws -> URL {
        guard fileManager.fileExists(atPath: workspaceDirectoryURL.path) else {
            throw LocalBridgeTransientWorkspaceStoreError.missingWorkspace
        }

        let urls = try fileManager.contentsOfDirectory(
            at: workspaceDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        guard let latestURL = urls.max(by: { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }) else {
            throw LocalBridgeTransientWorkspaceStoreError.missingWorkspace
        }

        return latestURL
    }
}
