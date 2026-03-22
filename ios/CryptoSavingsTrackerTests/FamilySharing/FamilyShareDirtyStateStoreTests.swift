import XCTest
@testable import CryptoSavingsTracker

final class FamilyShareDirtyStateStoreTests: XCTestCase {

    var store: FamilyShareDirtyStateStore!

    override func setUp() {
        super.setUp()
        let testDefaults = UserDefaults(suiteName: "FamilyShareDirtyStateStoreTests")!
        testDefaults.removePersistentDomain(forName: "FamilyShareDirtyStateStoreTests")
        store = FamilyShareDirtyStateStore(defaults: testDefaults)
    }

    // MARK: - Persistence

    func testMarkDirty_persistsEntry() {
        store.markDirty(namespaceKey: "ns1", reason: .goalMutation(goalIDs: [UUID()]))
        let entries = store.dirtyNamespaces()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.namespaceKey, "ns1")
    }

    func testClearDirty_removesEntry() {
        store.markDirty(namespaceKey: "ns1", reason: .manualRefresh)
        store.clearDirty(namespaceKey: "ns1")
        let entries = store.dirtyNamespaces()
        XCTAssertTrue(entries.isEmpty)
    }

    func testClearAll_removesAllEntries() {
        store.markDirty(namespaceKey: "ns1", reason: .manualRefresh)
        store.markDirty(namespaceKey: "ns2", reason: .rateDrift(goalIDs: []))
        store.clearAll()
        XCTAssertTrue(store.dirtyNamespaces().isEmpty)
    }

    // MARK: - Update Existing

    func testMarkDirty_updatesExistingEntry() {
        store.markDirty(namespaceKey: "ns1", reason: .goalMutation(goalIDs: [UUID()]))
        store.markDirty(namespaceKey: "ns1", reason: .rateDrift(goalIDs: []))
        let entries = store.dirtyNamespaces()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.reasonType, "rateDrift")
    }

    // MARK: - Multiple Namespaces

    func testMultipleNamespaces_trackedIndependently() {
        store.markDirty(namespaceKey: "ns1", reason: .manualRefresh)
        store.markDirty(namespaceKey: "ns2", reason: .participantChange)
        let entries = store.dirtyNamespaces()
        XCTAssertEqual(entries.count, 2)
        store.clearDirty(namespaceKey: "ns1")
        XCTAssertEqual(store.dirtyNamespaces().count, 1)
        XCTAssertEqual(store.dirtyNamespaces().first?.namespaceKey, "ns2")
    }
}
