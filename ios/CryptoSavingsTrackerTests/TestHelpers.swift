//
//  TestHelpers.swift
//  CryptoSavingsTrackerTests
//
//  Created by user on 27/07/2025.
//

import CryptoKit
import Foundation
import SwiftData
@testable import CryptoSavingsTracker

// MARK: - SwiftData Relationship Helpers

extension ModelContext {
    /// Helper to properly establish relationships and save in tests
    func saveWithRelationships() throws {
        self.processPendingChanges()
        try self.save()
        self.processPendingChanges()
    }
}

// MARK: - Test Data Factory

struct TestDataFactory {
    
    static func createSampleGoal(
        name: String = "Sample Goal",
        currency: String = "USD",
        targetAmount: Double = 1000,
        daysFromNow: Int = 30,
        frequency: ReminderFrequency = .weekly
    ) -> Goal {
        let deadline = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        return Goal(
            name: name,
            currency: currency,
            targetAmount: targetAmount,
            deadline: deadline,
            frequency: frequency
        )
    }
    
    static func createSampleAsset(
        currency: String = "BTC",
        goal: Goal? = nil,
        amount: Double = 0
    ) -> Asset {
        let asset = Asset(currency: currency)
        if let goal {
            let allocation = AssetAllocation(asset: asset, goal: goal, amount: amount)
            goal.allocations = (goal.allocations ?? []) + [allocation]
            asset.allocations = (asset.allocations ?? []) + [allocation]
        }
        return asset
    }
    
    static func createSampleTransaction(
        amount: Double = 100,
        asset: Asset
    ) -> Transaction {
        return Transaction(amount: amount, asset: asset)
    }
    
    static func createCompleteTestData(in context: ModelContext) throws -> (Goal, [Asset], [Transaction]) {
        let goal = createSampleGoal(name: "Complete Test Goal", targetAmount: 5000)
        
        let btcAsset = createSampleAsset(currency: "BTC", goal: goal)
        let ethAsset = createSampleAsset(currency: "ETH", goal: goal)
        let usdAsset = createSampleAsset(currency: "USD", goal: goal)
        
        context.insert(goal)
        context.insert(btcAsset)
        context.insert(ethAsset)
        context.insert(usdAsset)
        
        let btcTransaction1 = createSampleTransaction(amount: 0.1, asset: btcAsset)
        let btcTransaction2 = createSampleTransaction(amount: 0.05, asset: btcAsset)
        let ethTransaction = createSampleTransaction(amount: 2.0, asset: ethAsset)
        let usdTransaction1 = createSampleTransaction(amount: 1000, asset: usdAsset)
        let usdTransaction2 = createSampleTransaction(amount: 500, asset: usdAsset)
        
        let transactions = [btcTransaction1, btcTransaction2, ethTransaction, usdTransaction1, usdTransaction2]
        
        for transaction in transactions {
            context.insert(transaction)
        }
        
        try context.save()
        
        return (goal, [btcAsset, ethAsset, usdAsset], transactions)
    }
    /// Creates test data covering all 10 persisted entity types for integration tests.
    static func createFullCutoverTestData(in context: ModelContext) throws -> [String: Int] {
        // 1. Goal
        let goal = createSampleGoal(name: "Integration Goal", targetAmount: 5000)
        context.insert(goal)

        // 2. Asset (createSampleAsset with goal creates an AssetAllocation automatically)
        let asset = createSampleAsset(currency: "BTC", goal: goal)
        context.insert(asset)

        // 3. Transaction
        let tx = createSampleTransaction(amount: 0.5, asset: asset)
        context.insert(tx)

        // 4. AssetAllocation — already created by createSampleAsset via goal link

        // 5. AllocationHistory
        let history = AllocationHistory(asset: asset, goal: goal, amount: 0.5, timestamp: Date())
        history.assetId = asset.id
        history.goalId = goal.id
        history.monthLabel = "2026-03"
        context.insert(history)

        // 6. MonthlyExecutionRecord
        let execRecord = MonthlyExecutionRecord(monthLabel: "2026-03", goalIds: [goal.id])
        context.insert(execRecord)

        // 7. MonthlyPlan
        let plan = MonthlyPlan(
            goalId: goal.id, monthLabel: "2026-03",
            requiredMonthly: 100, remainingAmount: 4500, monthsRemaining: 12,
            currency: "USD", status: .onTrack, state: .draft
        )
        plan.executionRecord = execRecord
        context.insert(plan)

        // 8. CompletedExecution
        let completedExec = CompletedExecution(
            monthLabel: "2026-03", completedAt: Date(),
            exchangeRatesSnapshot: [:], goalSnapshots: [], contributionSnapshots: []
        )
        completedExec.executionRecord = execRecord
        execRecord.completedExecution = completedExec
        context.insert(completedExec)

        // 9. ExecutionSnapshot
        let snapshot = ExecutionSnapshot(
            id: UUID(), capturedAt: Date(), totalPlanned: 100, snapshotData: Data()
        )
        snapshot.executionRecord = execRecord
        execRecord.snapshot = snapshot
        context.insert(snapshot)

        // 10. CompletionEvent
        let event = CompletionEvent(
            executionRecord: execRecord,
            sequence: 1,
            sourceDiscriminator: "test",
            completedAt: Date(),
            completionSnapshot: completedExec
        )
        context.insert(event)

        try context.save()

        return [
            "Goal": 1, "Asset": 1, "Transaction": 1,
            "AssetAllocation": 1, "AllocationHistory": 1,
            "MonthlyExecutionRecord": 1, "MonthlyPlan": 1,
            "CompletedExecution": 1, "ExecutionSnapshot": 1,
            "CompletionEvent": 1
        ]
    }
}

// MARK: - Test Container Helper

struct TestContainer {
    /// Creates an in-memory ModelContainer with the full app schema.
    /// Use this for all SwiftData tests to ensure relationship consistency.
    /// Each call creates a unique store to avoid conflicts in parallel test execution.
    static func create() throws -> ModelContainer {
        let schema = Schema([
            Goal.self,
            Asset.self,
            Transaction.self,
            MonthlyPlan.self,
            AssetAllocation.self,
            AllocationHistory.self,
            MonthlyExecutionRecord.self,
            CompletedExecution.self,
            CompletionEvent.self,
            ExecutionSnapshot.self
        ])
        // Use UUID to ensure unique store name for parallel test execution
        let storeName = "testStore-\(UUID().uuidString)"
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func createWithSampleData() throws -> (ModelContainer, ModelContext) {
        let container = try create()
        let context = ModelContext(container)

        // Create some sample data
        let _ = try TestDataFactory.createCompleteTestData(in: context)

        return (container, context)
    }
}

// MARK: - Shared Mock Exchange Rate Service

class MockExchangeRateService: ExchangeRateServiceProtocol {
    private var rates: [String: Double] = [:]
    var shouldFail = false

    func setRate(from: String, to: String, rate: Double) {
        rates["\(from)-\(to)"] = rate
    }

    func fetchRate(from: String, to: String) async throws -> Double {
        if shouldFail { throw ExchangeRateError.networkError }
        if from == to { return 1.0 }
        return rates["\(from)-\(to)"] ?? 1.0
    }

    func hasValidConfiguration() -> Bool { true }
    func setOfflineMode(_ offline: Bool) {}
    func refreshRatesIfStale() async {}
}

// MARK: - Phase 2 Bridge Test Support

@MainActor
final class Phase2BridgeStorageModeRegistry: StorageModeRegistry {
    var currentMode: AppStorageMode
    var lastUpdatedAt: Date?

    init(currentMode: AppStorageMode = .cloudKitPrimary, lastUpdatedAt: Date? = nil) {
        self.currentMode = currentMode
        self.lastUpdatedAt = lastUpdatedAt
    }

    func setMode(_ mode: AppStorageMode) {
        currentMode = mode
        lastUpdatedAt = Date()
    }
}

@MainActor
final class Phase2BridgeSigningService: BridgePackageSigning {
    private var privateKeys: [String: P256.Signing.PrivateKey] = [:]

    func makeTrustedDevice(displayName: String) -> TrustedBridgeDevice {
        let keyID = UUID().uuidString
        let privateKey = P256.Signing.PrivateKey()
        privateKeys[keyID] = privateKey
        let publicKeyData = privateKey.publicKey.x963Representation

        return TrustedBridgeDevice(
            id: UUID(),
            displayName: displayName,
            fingerprint: LocalBridgeIdentityStore.fingerprint(publicKeyData: publicKeyData),
            signingKeyID: keyID,
            publicKeyRepresentation: publicKeyData.base64EncodedString(),
            signingAlgorithm: "P256.Signing.ECDSA.SHA256",
            addedAt: .now,
            lastSuccessfulSyncAt: nil,
            trustState: .active
        )
    }

    func identity(for signingKeyID: String) throws -> BridgeSigningIdentitySnapshot {
        let privateKey = privateKeys[signingKeyID] ?? {
            let privateKey = P256.Signing.PrivateKey()
            privateKeys[signingKeyID] = privateKey
            return privateKey
        }()
        let publicKeyData = privateKey.publicKey.x963Representation
        return BridgeSigningIdentitySnapshot(
            signingKeyID: signingKeyID,
            algorithm: "P256.Signing.ECDSA.SHA256",
            publicKeyRepresentation: publicKeyData.base64EncodedString(),
            fingerprint: LocalBridgeIdentityStore.fingerprint(publicKeyData: publicKeyData)
        )
    }

    func sign(_ data: Data, keyID: String) throws -> String {
        let privateKey = privateKeys[keyID] ?? {
            let privateKey = P256.Signing.PrivateKey()
            privateKeys[keyID] = privateKey
            return privateKey
        }()
        return try privateKey.signature(for: data).derRepresentation.base64EncodedString()
    }

    func verify(signature: String, payload: Data, publicKeyRepresentation: String) throws {
        guard let publicKeyData = Data(base64Encoded: publicKeyRepresentation) else {
            throw LocalBridgeIdentityStoreError.invalidPublicKey
        }
        guard let signatureData = Data(base64Encoded: signature) else {
            throw LocalBridgeIdentityStoreError.invalidSignatureEncoding
        }
        let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
        let signatureValue = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        guard publicKey.isValidSignature(signatureValue, for: payload) else {
            throw LocalBridgeIdentityStoreError.invalidSignature
        }
    }
}

@MainActor
final class Phase2BridgeTrustStore: BridgeTrustStoring {
    private var devices: [TrustedBridgeDevice]

    init(devices: [TrustedBridgeDevice] = []) {
        self.devices = devices
    }

    func loadTrustedDevices() -> [TrustedBridgeDevice] {
        devices
    }

    func upsert(_ device: TrustedBridgeDevice) throws {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
    }

    func revoke(deviceID: UUID) throws {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return }
        devices[index].trustState = .revoked
    }

    func remove(deviceID: UUID) throws {
        devices.removeAll { $0.id == deviceID }
    }

    func removeAll() throws {
        devices.removeAll()
    }
}

@MainActor
func makePhase2BridgeRuntimeController(
) throws -> PersistenceController {
    let registry = Phase2BridgeStorageModeRegistry()
    let stackFactory = PersistenceStackFactory(environment: .preview)
    let controller = PersistenceController(storageModeRegistry: registry, stackFactory: stackFactory)
    return controller
}

@MainActor
func makePhase2BridgeEditedSnapshot(from baseSnapshot: SnapshotEnvelope) throws -> SnapshotEnvelope {
    let newAssetID = UUID()
    let newAsset = BridgeAssetSnapshot(
        id: newAssetID,
        recordState: .active,
        currency: "ETH",
        address: "0xbridge000000000000000000000000000000000001",
        chainId: "eth"
    )
    let newTransaction = BridgeTransactionSnapshot(
        id: UUID(),
        recordState: .active,
        assetId: newAssetID,
        amount: 1.25,
        date: Date(timeIntervalSince1970: 1_700_000_000),
        sourceRawValue: TransactionSource.manual.rawValue,
        externalId: "bridge-import-transaction",
        counterparty: "Bridge Import",
        comment: "Applied from signed bridge package"
    )

    let assets = (baseSnapshot.assets + [newAsset]).sorted { $0.id.uuidString < $1.id.uuidString }
    let transactions = (baseSnapshot.transactions + [newTransaction]).sorted { $0.id.uuidString < $1.id.uuidString }
    let manifest = SnapshotManifest(
        snapshotID: baseSnapshot.manifest.snapshotID,
        canonicalEncodingVersion: baseSnapshot.manifest.canonicalEncodingVersion,
        snapshotSchemaVersion: baseSnapshot.manifest.snapshotSchemaVersion,
        exportedAt: baseSnapshot.manifest.exportedAt,
        appModelSchemaVersion: baseSnapshot.manifest.appModelSchemaVersion,
        entityCounts: [
            BridgeEntityCount(name: "Goal", count: baseSnapshot.goals.count),
            BridgeEntityCount(name: "Asset", count: assets.count),
            BridgeEntityCount(name: "Transaction", count: transactions.count),
            BridgeEntityCount(name: "AssetAllocation", count: baseSnapshot.assetAllocations.count),
            BridgeEntityCount(name: "AllocationHistory", count: baseSnapshot.allocationHistories.count),
            BridgeEntityCount(name: "MonthlyPlan", count: baseSnapshot.monthlyPlans.count),
            BridgeEntityCount(name: "MonthlyExecutionRecord", count: baseSnapshot.monthlyExecutionRecords.count),
            BridgeEntityCount(name: "CompletedExecution", count: baseSnapshot.completedExecutions.count),
            BridgeEntityCount(name: "ExecutionSnapshot", count: baseSnapshot.executionSnapshots.count),
            BridgeEntityCount(name: "CompletionEvent", count: baseSnapshot.completionEvents.count)
        ],
        baseDatasetFingerprint: ""
    )

    return try SnapshotEnvelope(
        manifest: manifest,
        goals: baseSnapshot.goals,
        assets: assets,
        transactions: transactions,
        assetAllocations: baseSnapshot.assetAllocations,
        allocationHistories: baseSnapshot.allocationHistories,
        monthlyPlans: baseSnapshot.monthlyPlans,
        monthlyExecutionRecords: baseSnapshot.monthlyExecutionRecords,
        completedExecutions: baseSnapshot.completedExecutions,
        executionSnapshots: baseSnapshot.executionSnapshots,
        completionEvents: baseSnapshot.completionEvents
    ).withComputedFingerprint()
}

@MainActor
func makePhase2BridgeSignedPackage(
    from snapshot: SnapshotEnvelope,
    baseDatasetFingerprint: String,
    trustedDevice: TrustedBridgeDevice,
    signingService: Phase2BridgeSigningService
) throws -> SignedImportPackage {
    guard
        let signingKeyID = trustedDevice.signingKeyID,
        let publicKeyRepresentation = trustedDevice.publicKeyRepresentation,
        let signingAlgorithm = trustedDevice.signingAlgorithm
    else {
        throw NSError(domain: "Phase2BridgeTestSupport", code: 1)
    }

    let unsignedPackage = SignedImportPackage(
        packageID: "",
        snapshotID: snapshot.manifest.snapshotID,
        canonicalEncodingVersion: snapshot.manifest.canonicalEncodingVersion,
        baseDatasetFingerprint: baseDatasetFingerprint,
        editedDatasetFingerprint: snapshot.manifest.baseDatasetFingerprint,
        snapshotEnvelope: snapshot,
        signingKeyID: signingKeyID,
        signingAlgorithm: signingAlgorithm,
        signerPublicKeyRepresentation: publicKeyRepresentation,
        signedAt: Date(timeIntervalSince1970: 1_700_000_500),
        signature: ""
    )
    let packageID = BudgetSnapshotIdentity.sha256(String(decoding: try unsignedPackage.canonicalPackageBodyData(), as: UTF8.self))
    let bodyPackage = SignedImportPackage(
        packageID: packageID,
        snapshotID: unsignedPackage.snapshotID,
        canonicalEncodingVersion: unsignedPackage.canonicalEncodingVersion,
        baseDatasetFingerprint: unsignedPackage.baseDatasetFingerprint,
        editedDatasetFingerprint: unsignedPackage.editedDatasetFingerprint,
        snapshotEnvelope: unsignedPackage.snapshotEnvelope,
        signingKeyID: unsignedPackage.signingKeyID,
        signingAlgorithm: unsignedPackage.signingAlgorithm,
        signerPublicKeyRepresentation: unsignedPackage.signerPublicKeyRepresentation,
        signedAt: unsignedPackage.signedAt,
        signature: ""
    )
    let signature = try signingService.sign(bodyPackage.signingPayloadData(), keyID: signingKeyID)

    return SignedImportPackage(
        packageID: packageID,
        snapshotID: bodyPackage.snapshotID,
        canonicalEncodingVersion: bodyPackage.canonicalEncodingVersion,
        baseDatasetFingerprint: bodyPackage.baseDatasetFingerprint,
        editedDatasetFingerprint: bodyPackage.editedDatasetFingerprint,
        snapshotEnvelope: bodyPackage.snapshotEnvelope,
        signingKeyID: bodyPackage.signingKeyID,
        signingAlgorithm: bodyPackage.signingAlgorithm,
        signerPublicKeyRepresentation: bodyPackage.signerPublicKeyRepresentation,
        signedAt: bodyPackage.signedAt,
        signature: signature
    )
}

// MARK: - Lightweight Goal/Asset helpers for tests

struct TestHelpers {
    static func createGoal(
        name: String,
        currency: String,
        targetAmount: Double,
        currentTotal: Double,
        deadline: Date
    ) -> Goal {
        let goal = Goal(
            name: name,
            currency: currency,
            targetAmount: targetAmount,
            deadline: deadline
        )
        if currentTotal != 0 {
            let asset = Asset(currency: currency)
            // Add transaction to give the asset a balance
            let tx = Transaction(amount: currentTotal, asset: asset)
            asset.transactions = (asset.transactions ?? []) + [tx]
            // Create allocation that references the asset balance
            let allocation = AssetAllocation(asset: asset, goal: goal, amount: abs(currentTotal))
            goal.allocations = (goal.allocations ?? []) + [allocation]
            asset.allocations = (asset.allocations ?? []) + [allocation]
        }
        return goal
    }

    static func createGoalWithAsset(
        name: String,
        currency: String,
        target: Double,
        current: Double,
        months: Int,
        context: ModelContext
    ) -> Goal {
        let deadline = Calendar.current.date(byAdding: .month, value: months, to: Date())!
        let goal = Goal(name: name, currency: currency, targetAmount: target, deadline: deadline)
        let asset = Asset(currency: currency)
        // Add transaction to give the asset a balance
        if current != 0 {
            let tx = Transaction(amount: current, asset: asset)
            asset.transactions = (asset.transactions ?? []) + [tx]
            context.insert(tx)
        }
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: abs(current))
        goal.allocations = (goal.allocations ?? []) + [allocation]
        asset.allocations = (asset.allocations ?? []) + [allocation]
        context.insert(goal)
        context.insert(asset)
        context.insert(allocation)
        return goal
    }

    static func createAsset(currency: String, currentAmount: Double) -> Asset {
        let asset = Asset(currency: currency)
        if currentAmount != 0 {
            let tx = Transaction(amount: currentAmount, asset: asset)
            asset.transactions = (asset.transactions ?? []) + [tx]
        }
        return asset
    }
}

// MARK: - Test-only compatibility helpers for legacy tests

extension Goal {
    /// Computed helper to mimic legacy goal.assets access in tests.
    var assets: [Asset] {
        get { (allocations ?? []).compactMap { $0.asset } }
        set {
            allocations = []
            for asset in newValue {
                let allocation = AssetAllocation(asset: asset, goal: self, amount: asset.currentAmount)
                allocations = (allocations ?? []) + [allocation]
                asset.allocations = (asset.allocations ?? []) + [allocation]
            }
        }
    }
}

extension Asset {
    /// Convenience init for tests to attach an asset to a goal with an optional starting balance.
    convenience init(currency: String, goal: Goal, address: String? = nil, chainId: String? = nil, balance: Double = 0) {
        self.init(currency: currency, address: address, chainId: chainId)
        let allocation = AssetAllocation(asset: self, goal: goal, amount: balance)
        goal.allocations = (goal.allocations ?? []) + [allocation]
        allocations = (allocations ?? []) + [allocation]
        if balance != 0 {
            let tx = Transaction(amount: balance, asset: self)
            transactions = (transactions ?? []) + [tx]
        }
    }
}

extension MonthlyPlan {
    /// Convenience init for tests defaulting monthLabel to current month.
    convenience init(
        goalId: UUID,
        requiredMonthly: Double,
        remainingAmount: Double,
        monthsRemaining: Int,
        currency: String,
        status: RequirementStatus = .onTrack,
        flexState: FlexState = .flexible,
        state: PlanState = .draft
    ) {
        let monthLabel = MonthlyExecutionRecord.monthLabel(from: Date())
        self.init(
            goalId: goalId,
            monthLabel: monthLabel,
            requiredMonthly: requiredMonthly,
            remainingAmount: remainingAmount,
            monthsRemaining: monthsRemaining,
            currency: currency,
            status: status,
            flexState: flexState,
            state: state
        )
    }
}

// MARK: - Assertion Helpers

struct TestAssertions {
    
    static func assertGoalIsValid(_ goal: Goal) {
        assert(!goal.name.isEmpty, "Goal name should not be empty")
        assert(goal.targetAmount > 0, "Target amount should be positive")
        assert(goal.deadline > Date().addingTimeInterval(-86400), "Deadline should not be in the past by more than a day")
        assert(!goal.currency.isEmpty, "Currency should not be empty")
    }
    
    static func assertAssetIsValid(_ asset: Asset) {
        assert(!asset.currency.isEmpty, "Asset currency should not be empty")
        assert(asset.currentAmount >= 0, "Asset amount should not be negative (unless withdrawals are supported)")
    }
    
    static func assertTransactionIsValid(_ transaction: Transaction) {
        assert(transaction.amount != 0, "Transaction amount should not be zero")
        assert(transaction.date <= Date().addingTimeInterval(60), "Transaction date should not be in the future")
    }
    
    static func assertProgressIsValid(_ progress: Double) {
        assert(progress >= 0, "Progress should not be negative")
        assert(progress <= 1.0, "Progress should not exceed 100%")
    }
}

// MARK: - Test Configuration

struct TestConfiguration {
    static var isUITesting: Bool {
        return ProcessInfo.processInfo.arguments.contains("--uitesting")
    }
    
    static var shouldUseMockServices: Bool {
        return ProcessInfo.processInfo.arguments.contains("--mock-services")
    }
    
    static func configureForTesting() {
        if isUITesting {
            // Clear any existing user defaults or persistent data
            // This would be called from the app delegate when running UI tests
        }
    }
}

// MARK: - Performance Testing Helpers

struct PerformanceTestHelper {
    
    static func measureTime<T>(_ operation: () throws -> T) rethrows -> (result: T, time: TimeInterval) {
        let startTime = Date()
        let result = try operation()
        let endTime = Date()
        return (result, endTime.timeIntervalSince(startTime))
    }
    
    static func measureAsyncTime<T>(_ operation: () async throws -> T) async rethrows -> (result: T, time: TimeInterval) {
        let startTime = Date()
        let result = try await operation()
        let endTime = Date()
        return (result, endTime.timeIntervalSince(startTime))
    }
    
    static func createLargeDataSet(goalCount: Int = 10, assetsPerGoal: Int = 5, transactionsPerAsset: Int = 10) throws -> ModelContainer {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        
        for goalIndex in 0..<goalCount {
            let goal = TestDataFactory.createSampleGoal(
                name: "Performance Goal \(goalIndex)",
                targetAmount: Double(1000 * (goalIndex + 1))
            )
            context.insert(goal)
            
            for assetIndex in 0..<assetsPerGoal {
                let asset = TestDataFactory.createSampleAsset(
                    currency: "ASSET\(goalIndex)_\(assetIndex)",
                    goal: goal
                )
                context.insert(asset)
                
                for transactionIndex in 0..<transactionsPerAsset {
                    let transaction = TestDataFactory.createSampleTransaction(
                        amount: Double(transactionIndex + 1) * 10.0,
                        asset: asset
                    )
                    context.insert(transaction)
                }
            }
        }
        
        try context.save()
        return container
    }
}
