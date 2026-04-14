import Foundation

/// Persists dirty-pending flags per namespace to survive app termination,
/// kill, and LRU cache eviction.
///
/// Uses `UserDefaults` for lightweight persistence. On app launch, the
/// coordinator reads persisted dirty flags and re-enqueues trailing
/// republishes after the freshness pipeline initializes.
final class FamilyShareDirtyStateStore: @unchecked Sendable {

    private nonisolated static let storeKey = "com.cryptosavings.familyshare.dirtystate"

    private nonisolated(unsafe) let defaults: UserDefaults

    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Dirty State Entry

    struct DirtyEntry: Codable, Sendable {
        let namespaceKey: String
        let reasonType: String
        let dirtySince: Date
    }

    // MARK: - Read

    /// Returns all persisted dirty namespaces.
    nonisolated func dirtyNamespaces() -> [DirtyEntry] {
        guard let data = defaults.data(forKey: Self.storeKey) else { return [] }
        return (try? JSONDecoder().decode([DirtyEntry].self, from: data)) ?? []
    }

    // MARK: - Write

    /// Mark a namespace as dirty-pending.
    nonisolated func markDirty(namespaceKey: String, reason: FamilyShareProjectionDirtyReason) {
        var entries = dirtyNamespaces()
        // Update existing or add new
        if let index = entries.firstIndex(where: { $0.namespaceKey == namespaceKey }) {
            entries[index] = DirtyEntry(
                namespaceKey: namespaceKey,
                reasonType: reasonType(for: reason),
                dirtySince: Date()
            )
        } else {
            entries.append(DirtyEntry(
                namespaceKey: namespaceKey,
                reasonType: reasonType(for: reason),
                dirtySince: Date()
            ))
        }
        persist(entries)
    }

    /// Clear dirty flag for a specific namespace after successful publish.
    nonisolated func clearDirty(namespaceKey: String) {
        var entries = dirtyNamespaces()
        entries.removeAll { $0.namespaceKey == namespaceKey }
        persist(entries)
    }

    /// Clear all dirty flags (used during rollback).
    nonisolated func clearAll() {
        defaults.removeObject(forKey: Self.storeKey)
    }

    // MARK: - Private

    private nonisolated func persist(_ entries: [DirtyEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storeKey)
    }

    private nonisolated func reasonType(for reason: FamilyShareProjectionDirtyReason) -> String {
        switch reason {
        case .goalMutation: return "goalMutation"
        case .assetMutation: return "assetMutation"
        case .transactionMutation: return "transactionMutation"
        case .rateDrift: return "rateDrift"
        case .importOrRepair: return "importOrRepair"
        case .manualRefresh: return "manualRefresh"
        case .participantChange: return "participantChange"
        }
    }
}
