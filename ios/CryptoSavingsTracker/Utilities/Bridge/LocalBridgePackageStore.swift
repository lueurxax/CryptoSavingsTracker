import Foundation

enum LocalBridgePackageStoreError: LocalizedError {
    case appSupportUnavailable
    case noImportedPackage

    var errorDescription: String? {
        switch self {
        case .appSupportUnavailable:
            return "Application Support is unavailable for Local Bridge Sync artifacts."
        case .noImportedPackage:
            return "No signed import package has been loaded yet."
        }
    }
}

final class LocalBridgePackageStore {
    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LocalBridgePackageStoreError.appSupportUnavailable
        }
        self.rootURL = appSupportURL.appendingPathComponent("LocalBridgeSync", isDirectory: true)
        try ensureDirectories()
    }

    var outboundDirectoryURL: URL {
        rootURL.appendingPathComponent("Outbound", isDirectory: true)
    }

    var inboundDirectoryURL: URL {
        rootURL.appendingPathComponent("Inbound", isDirectory: true)
    }

    @discardableResult
    func writeSnapshot(_ snapshot: SnapshotEnvelope) throws -> URL {
        let fileURL = outboundDirectoryURL.appendingPathComponent("\(snapshot.manifest.snapshotID.uuidString).bridge-snapshot.json")
        try snapshot.canonicalEncodingData().write(to: fileURL, options: .atomic)
        return fileURL
    }

    @discardableResult
    func writePackage(_ package: SignedImportPackage) throws -> URL {
        let fileURL = inboundDirectoryURL.appendingPathComponent("\(package.packageID).bridge-import.json")
        try package.canonicalEncodingData().write(to: fileURL, options: .atomic)
        return fileURL
    }

    func loadPackage(from data: Data) throws -> SignedImportPackage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(SignedImportPackage.self, from: bridgeNormalizedCanonicalDecodingData(data))
    }

    func loadLatestImportedPackage() throws -> SignedImportPackage {
        let fileURL = try latestFile(in: inboundDirectoryURL, matching: ".bridge-import.json")
        let data = try Data(contentsOf: fileURL)
        return try loadPackage(from: data)
    }

    private func latestFile(in directoryURL: URL, matching suffix: String) throws -> URL {
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.lastPathComponent.hasSuffix(suffix) }

        guard let latest = try urls.max(by: { lhs, rhs in
            let lhsDate = try lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let rhsDate = try rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return lhsDate < rhsDate
        }) else {
            throw LocalBridgePackageStoreError.noImportedPackage
        }
        return latest
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: outboundDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: inboundDirectoryURL, withIntermediateDirectories: true)
    }
}
