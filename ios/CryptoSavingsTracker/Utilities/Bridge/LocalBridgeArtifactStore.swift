import Foundation

struct LocalBridgeSnapshotArtifact: Equatable, Sendable {
    let snapshotID: UUID
    let exportedAt: Date
    let fileURL: URL
    let fileSizeBytes: Int64
    let entityCounts: [BridgeEntityCount]

    var displayName: String {
        fileURL.lastPathComponent
    }
}

struct LocalBridgeImportPackageArtifact: Equatable, Sendable {
    let packageID: String
    let snapshotID: UUID
    let signedAt: Date
    let fileURL: URL
    let fileSizeBytes: Int64
    let sourceDeviceName: String?

    var displayName: String {
        fileURL.lastPathComponent
    }
}

enum LocalBridgeArtifactStoreError: LocalizedError {
    case invalidSnapshotArtifact
    case invalidImportPackageArtifact

    var errorDescription: String? {
        switch self {
        case .invalidSnapshotArtifact:
            return "The selected bridge snapshot artifact could not be decoded."
        case .invalidImportPackageArtifact:
            return "The selected bridge import package could not be decoded."
        }
    }
}

final class LocalBridgeArtifactStore {
    private let fileManager: FileManager
    private let appSupportURL: URL

    init(
        fileManager: FileManager = .default,
        appSupportURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.appSupportURL = appSupportURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    func persist(snapshot: SnapshotEnvelope) throws -> LocalBridgeSnapshotArtifact {
        try ensureDirectoryExists(exportsDirectoryURL)

        let fileURL = exportsDirectoryURL.appendingPathComponent(snapshotFileName(for: snapshot) + ".json")
        try snapshot.canonicalEncodingData().write(to: fileURL, options: .atomic)
        return try snapshotArtifact(for: snapshot, at: fileURL)
    }

    func importPackage(from externalURL: URL) throws -> (artifact: LocalBridgeImportPackageArtifact, package: SignedImportPackage) {
        let hasSecurityScope = externalURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                externalURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: externalURL)
        let package = try decodePackage(from: data)

        try ensureDirectoryExists(importsDirectoryURL)

        let fileURL = importsDirectoryURL.appendingPathComponent(importPackageFileName(for: package) + ".json")
        try package.canonicalEncodingData().write(to: fileURL, options: .atomic)
        return (try importArtifact(for: package, at: fileURL), package)
    }

    func latestSnapshotArtifact() -> LocalBridgeSnapshotArtifact? {
        latestArtifact(in: exportsDirectoryURL) { url in
            let data = try Data(contentsOf: url)
            let snapshot = try decodeSnapshot(from: data)
            return try snapshotArtifact(for: snapshot, at: url)
        }
    }

    func latestImportPackageArtifact() -> (artifact: LocalBridgeImportPackageArtifact, package: SignedImportPackage)? {
        latestArtifact(in: importsDirectoryURL) { url in
            let data = try Data(contentsOf: url)
            let package = try decodePackage(from: data)
            return (try importArtifact(for: package, at: url), package)
        }
    }

    private var baseDirectoryURL: URL {
        appSupportURL.appendingPathComponent("LocalBridgeArtifacts", isDirectory: true)
    }

    private var exportsDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("Exports", isDirectory: true)
    }

    private var importsDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("Imports", isDirectory: true)
    }

    private func snapshotFileName(for snapshot: SnapshotEnvelope) -> String {
        "bridge-snapshot-\(timestampLabel(for: snapshot.manifest.exportedAt))-\(snapshot.manifest.snapshotID.uuidString)"
    }

    private func importPackageFileName(for package: SignedImportPackage) -> String {
        let digestPrefix = String(package.packageID.prefix(12))
        return "bridge-import-\(timestampLabel(for: package.signedAt))-\(digestPrefix)"
    }

    private func timestampLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private func ensureDirectoryExists(_ directoryURL: URL) throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private func decodeSnapshot(from data: Data) throws -> SnapshotEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            return try decoder.decode(SnapshotEnvelope.self, from: data)
        } catch {
            throw LocalBridgeArtifactStoreError.invalidSnapshotArtifact
        }
    }

    private func decodePackage(from data: Data) throws -> SignedImportPackage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            return try decoder.decode(SignedImportPackage.self, from: data)
        } catch {
            throw LocalBridgeArtifactStoreError.invalidImportPackageArtifact
        }
    }

    private func snapshotArtifact(for snapshot: SnapshotEnvelope, at fileURL: URL) throws -> LocalBridgeSnapshotArtifact {
        LocalBridgeSnapshotArtifact(
            snapshotID: snapshot.manifest.snapshotID,
            exportedAt: snapshot.manifest.exportedAt,
            fileURL: fileURL,
            fileSizeBytes: try fileSize(for: fileURL),
            entityCounts: snapshot.entityCounts
        )
    }

    private func importArtifact(for package: SignedImportPackage, at fileURL: URL) throws -> LocalBridgeImportPackageArtifact {
        LocalBridgeImportPackageArtifact(
            packageID: package.packageID,
            snapshotID: package.snapshotID,
            signedAt: package.signedAt,
            fileURL: fileURL,
            fileSizeBytes: try fileSize(for: fileURL),
            sourceDeviceName: nil
        )
    }

    private func fileSize(for fileURL: URL) throws -> Int64 {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func latestArtifact<T>(
        in directoryURL: URL,
        load: (URL) throws -> T
    ) -> T? {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return nil
        }

        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let latestURL = urls.max { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }

        guard let latestURL else {
            return nil
        }

        return try? load(latestURL)
    }
}
