import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct PersistenceMutationServicesTests {
    private enum ForcedSaveError: Error {
        case failed
    }

    private final class NotificationCaptureBox: @unchecked Sendable {
        var userInfo: [AnyHashable: Any]?
    }

    private final class NotificationFlagBox: @unchecked Sendable {
        var wasPosted = false
    }

    @MainActor
    private final class SpyNotificationManager: NotificationManager {
        var cancelledGoalIDs: [UUID] = []

        init() {
            super.init(runtimeMode: .publicMVP, isUITestRunProvider: { false })
        }

        override func cancelNotifications(for goal: Goal) async {
            cancelledGoalIDs.append(goal.id)
        }
    }

    @Test("GoalMutationService inserts and saves detached goal")
    func goalMutationServicePersistsDetachedGoal() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = GoalMutationService(modelContext: context, accessGuard: AllowAllFamilyShareAccessGuard())
        let goal = TestDataFactory.createSampleGoal(name: "Cutover Goal")

        try await service.createGoal(goal)

        let goals = try context.fetch(FetchDescriptor<Goal>())
        #expect(goals.count == 1)
        #expect(goals.first?.name == "Cutover Goal")
        #expect(goal.modelContext != nil)
    }

    @Test("GoalMutationService clears reminder fields during create and save")
    func goalMutationServiceClearsReminderFields() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = GoalMutationService(modelContext: context, accessGuard: AllowAllFamilyShareAccessGuard())
        let goal = TestDataFactory.createSampleGoal(name: "Reminder Cleanup Goal")
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
        goal.firstReminderDate = Date().addingTimeInterval(3600)

        try await service.createGoal(goal)

        #expect(goal.reminderFrequency == nil)
        #expect(goal.reminderTime == nil)
        #expect(goal.firstReminderDate == nil)

        goal.reminderFrequency = ReminderFrequency.monthly.rawValue
        goal.reminderTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())
        goal.firstReminderDate = Date().addingTimeInterval(7200)

        try await service.saveGoal(goal)

        #expect(goal.reminderFrequency == nil)
        #expect(goal.reminderTime == nil)
        #expect(goal.firstReminderDate == nil)
    }

    @Test("GoalMutationService clears reminder fields during restore")
    func goalMutationServiceClearsReminderFieldsOnRestore() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = GoalMutationService(modelContext: context, accessGuard: AllowAllFamilyShareAccessGuard())
        let goal = TestDataFactory.createSampleGoal(name: "Archived Goal")
        goal.archive()
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
        goal.firstReminderDate = Date().addingTimeInterval(3600)
        context.insert(goal)
        try context.save()

        try await service.restoreGoal(goal)

        #expect(goal.isArchived == false)
        #expect(goal.reminderFrequency == nil)
        #expect(goal.reminderTime == nil)
        #expect(goal.firstReminderDate == nil)
    }

    @Test("Goal restore preserves the complete pre-mutation goal state when persistence fails")
    func goalRestorePreservesCompleteGoalStateOnSaveFailure() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Archived Goal")
        goal.archive()
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = Date(timeIntervalSince1970: 1_000)
        goal.firstReminderDate = Date(timeIntervalSince1970: 2_000)
        context.insert(goal)
        try context.save()

        let unsavedDeadline = Date(timeIntervalSince1970: 5_000)
        let unsavedStartDate = Date(timeIntervalSince1970: 4_000)
        goal.name = "Unsaved renamed goal"
        goal.currency = "EUR"
        goal.targetAmount = 4_321
        goal.deadline = unsavedDeadline
        goal.startDate = unsavedStartDate
        goal.emoji = "🧪"
        goal.goalDescription = "Unsaved description"
        goal.link = "https://example.test/unsaved"

        let originalStatusChangedAt = goal.lifecycleStatusChangedAt
        let originalLastModifiedDate = goal.lastModifiedDate
        let notificationManager = SpyNotificationManager()
        let sharedGoalSignal = NotificationFlagBox()
        let token = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { _ in
            sharedGoalSignal.wasPosted = true
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let service = GoalMutationService(
            modelContext: context,
            notificationManager: notificationManager,
            accessGuard: AllowAllFamilyShareAccessGuard(),
            saveChanges: {
                throw ForcedSaveError.failed
            }
        )

        await #expect(throws: PersistenceMutationError.self) {
            try await service.restoreGoal(goal)
        }

        #expect(goal.isArchived)
        #expect(goal.lifecycleStatusChangedAt == originalStatusChangedAt)
        #expect(goal.lastModifiedDate == originalLastModifiedDate)
        #expect(goal.reminderFrequency == ReminderFrequency.weekly.rawValue)
        #expect(goal.reminderTime == Date(timeIntervalSince1970: 1_000))
        #expect(goal.firstReminderDate == Date(timeIntervalSince1970: 2_000))
        #expect(goal.name == "Unsaved renamed goal")
        #expect(goal.currency == "EUR")
        #expect(goal.targetAmount == 4_321)
        #expect(goal.deadline == unsavedDeadline)
        #expect(goal.startDate == unsavedStartDate)
        #expect(goal.emoji == "🧪")
        #expect(goal.goalDescription == "Unsaved description")
        #expect(goal.link == "https://example.test/unsaved")
        #expect(notificationManager.cancelledGoalIDs.isEmpty)
        #expect(sharedGoalSignal.wasPosted == false)
    }

    @Test("Goal restore preserves unrelated unsaved model edits when persistence fails")
    func goalRestorePreservesUnrelatedUnsavedEditsOnSaveFailure() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let archivedGoal = TestDataFactory.createSampleGoal(name: "Archived Goal")
        archivedGoal.archive()
        let unrelatedGoal = TestDataFactory.createSampleGoal(
            name: "Unrelated Goal",
            targetAmount: 1_000
        )
        context.insert(archivedGoal)
        context.insert(unrelatedGoal)
        try context.save()

        unrelatedGoal.name = "Unsaved unrelated rename"
        unrelatedGoal.targetAmount = 9_999

        let service = GoalMutationService(
            modelContext: context,
            notificationManager: SpyNotificationManager(),
            accessGuard: AllowAllFamilyShareAccessGuard(),
            saveChanges: {
                throw ForcedSaveError.failed
            }
        )

        await #expect(throws: PersistenceMutationError.self) {
            try await service.restoreGoal(archivedGoal)
        }

        #expect(unrelatedGoal.name == "Unsaved unrelated rename")
        #expect(unrelatedGoal.targetAmount == 9_999)
    }

    @Test("GoalMutationService clears reminder fields during archive")
    func goalMutationServiceClearsReminderFieldsOnArchive() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = GoalMutationService(modelContext: context, accessGuard: AllowAllFamilyShareAccessGuard())
        let goal = TestDataFactory.createSampleGoal(name: "Archive Reminder Cleanup Goal")
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
        goal.firstReminderDate = Date().addingTimeInterval(3600)
        context.insert(goal)
        try context.save()

        try await service.archiveGoal(goal)

        #expect(goal.isArchived == true)
        #expect(goal.reminderFrequency == nil)
        #expect(goal.reminderTime == nil)
        #expect(goal.firstReminderDate == nil)
    }

    @Test("Archiving frees reserved funds and removes only mutable execution tracking")
    func goalMutationServiceArchiveUsesAtomicDeleteSemantics() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Archive Lifecycle Goal")
        let asset = Asset(currency: "USD")
        let openingBalance = Transaction(amount: 100, asset: asset)
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 40)
        asset.transactions = [openingBalance]
        asset.allocations = [allocation]
        goal.allocations = [allocation]

        let activeRecord = MonthlyExecutionRecord(monthLabel: "2026-07", goalIds: [goal.id])
        activeRecord.startTracking()
        let closedRecord = MonthlyExecutionRecord(monthLabel: "2026-06", goalIds: [goal.id])
        closedRecord.status = .closed
        let completedEvidence = CompletedExecution(
            monthLabel: "2026-06",
            completedAt: Date(timeIntervalSince1970: 1_750_000_000),
            exchangeRatesSnapshot: ["USD": 1],
            goalSnapshots: [],
            contributionSnapshots: []
        )
        closedRecord.completedExecution = completedEvidence
        completedEvidence.executionRecord = closedRecord

        context.insert(goal)
        context.insert(asset)
        context.insert(openingBalance)
        context.insert(allocation)
        context.insert(activeRecord)
        context.insert(closedRecord)
        context.insert(completedEvidence)
        try context.saveWithRelationships()

        let service = GoalMutationService(
            modelContext: context,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )
        try await service.archiveGoal(goal)

        context.processPendingChanges()
        #expect(goal.isArchived)
        #expect(try context.fetch(FetchDescriptor<AssetAllocation>()).isEmpty)
        #expect(asset.totalAllocatedAmount == 0)
        #expect(asset.unallocatedAmount == 100)
        #expect(activeRecord.goalIds.isEmpty)
        #expect(closedRecord.goalIds == [goal.id])
        #expect(closedRecord.completedExecution?.id == completedEvidence.id)
        #expect(closedRecord.completedExecution?.exchangeRatesSnapshot == ["USD": 1])
    }

    @Test("GoalMutationService clears reminder fields during resume")
    func goalMutationServiceClearsReminderFieldsOnResume() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = GoalMutationService(modelContext: context, accessGuard: AllowAllFamilyShareAccessGuard())
        let goal = TestDataFactory.createSampleGoal(name: "Resume Reminder Cleanup Goal")
        goal.archive()
        goal.reminderFrequency = ReminderFrequency.weekly.rawValue
        goal.reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
        goal.firstReminderDate = Date().addingTimeInterval(3600)
        context.insert(goal)
        try context.save()

        try await service.resumeGoal(goal)

        #expect(goal.isArchived == false)
        #expect(goal.reminderFrequency == nil)
        #expect(goal.reminderTime == nil)
        #expect(goal.firstReminderDate == nil)
    }

    @Test("AssetMutationService creates asset with initial allocation history")
    func assetMutationServiceCreatesInitialAllocationHistory() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = AssetMutationService(modelContext: context, accessGuard: AllowAllFamilyShareAccessGuard())
        let goal = TestDataFactory.createSampleGoal(name: "Asset Goal")
        context.insert(goal)
        try context.save()

        let asset = try await service.createAsset(
            currency: "BTC",
            address: "bc1qexamplewalletaddress000000000000000000",
            chainId: "BTC",
            goal: goal
        )

        let allocations = try context.fetch(FetchDescriptor<AssetAllocation>())
        let histories = try context.fetch(FetchDescriptor<AllocationHistory>())
        #expect((asset.allocations ?? []).count == 1)
        #expect(allocations.count == 1)
        #expect(histories.count == 1)
        #expect(histories.first?.goalId == goal.id)
    }

    @Test("First manual contribution grows a newly created dedicated allocation")
    func manualContributionGrowsInitialDedicatedAllocation() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let accessGuard = AllowAllFamilyShareAccessGuard()
        let assetService = AssetMutationService(modelContext: context, accessGuard: accessGuard)
        let transactionService = TransactionMutationService(modelContext: context, accessGuard: accessGuard)
        let goal = TestDataFactory.createSampleGoal(name: "Progress Goal")
        goal.currency = "USD"
        goal.targetAmount = 1_000
        context.insert(goal)
        try context.save()

        let asset = try await assetService.createAsset(
            currency: "USD",
            address: nil,
            chainId: nil,
            goal: goal
        )
        let allocation = try #require(asset.allocations?.first)
        #expect(allocation.amountValue == 0)

        _ = try transactionService.createTransaction(
            for: asset,
            amount: 250,
            date: Date(),
            comment: nil,
            autoAllocateGoalId: nil
        )
        context.processPendingChanges()

        #expect(asset.manualBalance == 250)
        #expect(allocation.amountValue == 250)
        #expect(goal.manualTotal == 250)
        #expect(goal.manualProgress == 0.25)
    }

    @Test("AssetMutationService rejects unsupported automatic-tracking routes before persistence")
    func assetMutationServiceRejectsUnsupportedTrackingRoute() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = AssetMutationService(
            modelContext: context,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )
        let goal = TestDataFactory.createSampleGoal(name: "Unsupported Route")
        context.insert(goal)
        try context.save()

        do {
            _ = try await service.createAsset(
                currency: "USDC",
                address: "0x00000000000000000000000000000000000000aa",
                chainId: "MATIC",
                goal: goal
            )
            Issue.record("Unsupported USDC/Polygon automatic tracking must be rejected")
        } catch {
            #expect(error.localizedDescription.contains("USDC"))
            #expect(error.localizedDescription.contains("Polygon"))
            #expect(error.localizedDescription.contains("manual"))
        }

        #expect(try context.fetch(FetchDescriptor<Asset>()).isEmpty)
    }

    @Test("AssetMutationService keeps manual assets independent of on-chain route support")
    func assetMutationServiceAllowsUnsupportedManualAsset() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = AssetMutationService(
            modelContext: context,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )
        let goal = TestDataFactory.createSampleGoal(name: "Manual Asset")
        context.insert(goal)
        try context.save()

        let asset = try await service.createAsset(
            currency: "UNLISTED",
            address: nil,
            chainId: nil,
            goal: goal
        )

        #expect(asset.currency == "UNLISTED")
        #expect(asset.address == nil)
        #expect(asset.chainId == nil)
    }

    @Test("AssetMutationService rejects a canonical Bitcoin Bech32 wallet alias")
    func assetMutationServiceRejectsCanonicalBitcoinWalletAlias() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Canonical wallet")
        let existing = Asset(
            currency: "BTC",
            address: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080",
            chainId: "BTC"
        )
        context.insert(goal)
        context.insert(existing)
        try context.save()

        let service = AssetMutationService(
            modelContext: context,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )

        await #expect(throws: PersistenceMutationError.self) {
            try await service.createAsset(
                currency: "btc",
                address: "BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KYGT080",
                chainId: "btc",
                goal: goal
            )
        }
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 1)
    }

    @Test("AssetMutationService treats legacy MATIC and POL as one Polygon native wallet")
    func assetMutationServiceRejectsPolygonNativeCurrencyAlias() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Polygon native wallet")
        let existing = Asset(
            currency: "MATIC",
            address: "0x00000000000000000000000000000000000000AA",
            chainId: "MATIC"
        )
        context.insert(goal)
        context.insert(existing)
        try context.save()

        let service = AssetMutationService(
            modelContext: context,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )

        await #expect(throws: PersistenceMutationError.self) {
            try await service.createAsset(
                currency: "POL",
                address: "0x00000000000000000000000000000000000000aa",
                chainId: "polygon-mainnet",
                goal: goal
            )
        }
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 1)
    }

    @Test("Addressed asset identity canonicalizes BTC, LTC, and BCH aliases only where the chain permits")
    func addressedAssetIdentityIsChainAware() throws {
        let btcLower = try #require(AssetPersistenceIdentityPolicy.addressedIdentity(
            currency: "BTC",
            address: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080",
            chainId: "BTC"
        ))
        let btcUpper = try #require(AssetPersistenceIdentityPolicy.addressedIdentity(
            currency: "btc",
            address: "BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KYGT080",
            chainId: "bitcoin-mainnet"
        ))
        let ltcLower = try #require(AssetPersistenceIdentityPolicy.addressedIdentity(
            currency: "LTC",
            address: "ltc1qexamplewallet000000000000000000000000000",
            chainId: "LTC"
        ))
        let ltcUpper = try #require(AssetPersistenceIdentityPolicy.addressedIdentity(
            currency: "ltc",
            address: "LTC1QEXAMPLEWALLET000000000000000000000000000",
            chainId: "litecoin-mainnet"
        ))
        let bchPrefixed = try #require(AssetPersistenceIdentityPolicy.addressedIdentity(
            currency: "BCH",
            address: "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a",
            chainId: "BCH"
        ))
        let bchUnprefixed = try #require(AssetPersistenceIdentityPolicy.addressedIdentity(
            currency: "bch",
            address: "QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A",
            chainId: "bitcoin-cash-mainnet"
        ))
        let solanaUpper = try #require(AssetPersistenceIdentityPolicy.addressedIdentity(
            currency: "SOL",
            address: "AbcDefGhijkLmnoPqrstUvwxyz123456789",
            chainId: "SOL"
        ))
        let solanaLower = try #require(AssetPersistenceIdentityPolicy.addressedIdentity(
            currency: "SOL",
            address: "abcDefGhijkLmnoPqrstUvwxyz123456789",
            chainId: "solana-mainnet"
        ))

        #expect(btcLower == btcUpper)
        #expect(ltcLower == ltcUpper)
        #expect(bchPrefixed == bchUnprefixed)
        #expect(solanaUpper != solanaLower)
    }

    @Test("AssetMutationService permits independent addressless accounts in one currency")
    func assetMutationServicePermitsAddresslessSameCurrencyAccounts() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Two cash accounts")
        context.insert(goal)
        try context.save()
        let service = AssetMutationService(
            modelContext: context,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )

        _ = try await service.createAsset(currency: "USD", address: nil, chainId: nil, goal: goal)
        _ = try await service.createAsset(currency: "usd", address: nil, chainId: nil, goal: goal)

        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 2)
    }

    @Test("AssetMutationService preserves case-sensitive Solana wallet identities")
    func assetMutationServicePreservesSolanaAddressCase() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Solana wallets")
        context.insert(goal)
        try context.save()
        let service = AssetMutationService(
            modelContext: context,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )

        _ = try await service.createAsset(
            currency: "SOL",
            address: "AbcDefGhijkLmnoPqrstUvwxyz123456789",
            chainId: "SOL",
            goal: goal
        )
        _ = try await service.createAsset(
            currency: "SOL",
            address: "abcDefGhijkLmnoPqrstUvwxyz123456789",
            chainId: "sol",
            goal: goal
        )

        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 2)
    }

    @Test("Asset deletion is rejected while an execution still depends on its allocation")
    func assetDeletionRejectsExecutingEvidence() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Executing goal")
        let asset = Asset(currency: "USD")
        let allocation = AssetAllocation(asset: asset, goal: goal, amount: 20)
        let record = MonthlyExecutionRecord(monthLabel: "2026-07", goalIds: [goal.id])
        record.status = .executing
        record.startedAt = Date()
        record.canUndoUntil = Date().addingTimeInterval(3_600)
        goal.allocations = [allocation]
        asset.allocations = [allocation]
        context.insert(goal)
        context.insert(asset)
        context.insert(allocation)
        context.insert(record)
        try context.save()

        let service = AssetMutationService(
            modelContext: context,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )

        #expect(throws: PersistenceMutationError.self) {
            try service.deleteAsset(asset)
        }
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AssetAllocation>()) == 1)
    }

    @Test("Asset deletion is rejected while a closed execution contribution remains undoable")
    func assetDeletionRejectsUndoableClosedContributionEvidence() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Undoable goal")
        let asset = Asset(currency: "USD")
        let record = MonthlyExecutionRecord(monthLabel: "2026-07", goalIds: [goal.id])
        record.status = .closed
        record.completedAt = Date()
        record.canUndoUntil = Date().addingTimeInterval(3_600)
        let completion = CompletedExecution(
            monthLabel: record.monthLabel,
            completedAt: record.completedAt!,
            exchangeRatesSnapshot: [:],
            goalSnapshots: [],
            contributionSnapshots: [
                CompletedExecutionContributionSnapshot(
                    timestamp: Date(),
                    source: .manualDeposit,
                    assetId: asset.id,
                    assetCurrency: "USD",
                    goalId: goal.id,
                    goalCurrency: "USD",
                    assetAmount: 10,
                    amountInGoalCurrency: 10,
                    exchangeRateUsed: 1
                )
            ]
        )
        record.completedExecution = completion
        completion.executionRecord = record
        context.insert(goal)
        context.insert(asset)
        context.insert(record)
        context.insert(completion)
        try context.save()

        let service = AssetMutationService(
            modelContext: context,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )

        #expect(throws: PersistenceMutationError.self) {
            try service.deleteAsset(asset)
        }
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 1)
        #expect(record.completedExecution?.contributionSnapshots.count == 1)
    }

    @Test("Asset deletion is allowed after closed execution undo evidence expires")
    func assetDeletionAllowsExpiredClosedEvidence() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Immutable history goal")
        let asset = Asset(currency: "USD")
        let record = MonthlyExecutionRecord(monthLabel: "2026-06", goalIds: [goal.id])
        record.status = .closed
        record.completedAt = Date().addingTimeInterval(-7_200)
        record.canUndoUntil = Date().addingTimeInterval(-3_600)
        let completion = CompletedExecution(
            monthLabel: record.monthLabel,
            completedAt: record.completedAt!,
            exchangeRatesSnapshot: [:],
            goalSnapshots: [],
            contributionSnapshots: [
                CompletedExecutionContributionSnapshot(
                    timestamp: record.completedAt!,
                    source: .manualDeposit,
                    assetId: asset.id,
                    assetCurrency: "USD",
                    goalId: goal.id,
                    goalCurrency: "USD",
                    assetAmount: 10,
                    amountInGoalCurrency: 10,
                    exchangeRateUsed: 1
                )
            ]
        )
        record.completedExecution = completion
        completion.executionRecord = record
        context.insert(goal)
        context.insert(asset)
        context.insert(record)
        context.insert(completion)
        try context.save()

        let service = AssetMutationService(
            modelContext: context,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )
        try service.deleteAsset(asset)

        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 0)
        #expect(record.completedExecution?.contributionSnapshots.first?.assetId == asset.id)
    }

    @Test("PlanningMutationService prepares plans for execution")
    func planningMutationServicePreparesPlansForExecution() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let exchangeRates = MockExchangeRateService()
        let service = PlanningMutationService(
            modelContext: context,
            exchangeRateService: exchangeRates,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )

        let draftGoal = TestDataFactory.createSampleGoal(name: "Draft Goal")
        let executedGoal = TestDataFactory.createSampleGoal(name: "Executed Goal")
        context.insert(draftGoal)
        context.insert(executedGoal)

        let zeroPlan = MonthlyPlan(
            goalId: draftGoal.id,
            monthLabel: "2026-03",
            requiredMonthly: 0,
            remainingAmount: 0,
            monthsRemaining: 1,
            currency: "USD",
            state: .draft
        )
        let executedPlan = MonthlyPlan(
            goalId: executedGoal.id,
            monthLabel: "2026-03",
            requiredMonthly: 150,
            remainingAmount: 500,
            monthsRemaining: 4,
            currency: "USD",
            state: .executing
        )
        context.insert(zeroPlan)
        context.insert(executedPlan)
        try context.save()

        try service.preparePlansForExecution([zeroPlan, executedPlan])

        #expect(zeroPlan.state == .draft)
        #expect(zeroPlan.isSkipped == true)
        #expect(executedPlan.state == .draft)
        #expect(executedPlan.isSkipped == false)
    }

    @Test("GoalMutationService rejects writes for shared goals")
    func goalMutationServiceRejectsSharedGoalMutation() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Shared Goal")
        let service = GoalMutationService(
            modelContext: context,
            accessGuard: DenyingFamilyShareAccessGuard(sharedGoalIDs: [goal.id])
        )

        await #expect(throws: FamilyShareReadOnlyAccessError.self) {
            try await service.saveGoal(goal)
        }
    }

    @Test("AssetMutationService rejects asset creation for shared goals")
    func assetMutationServiceRejectsSharedGoalMutation() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Shared Asset Goal")
        context.insert(goal)
        try context.save()
        let service = AssetMutationService(
            modelContext: context,
            accessGuard: DenyingFamilyShareAccessGuard(sharedGoalIDs: [goal.id])
        )

        await #expect(throws: FamilyShareReadOnlyAccessError.self) {
            _ = try await service.createAsset(
                currency: "BTC",
                address: "0x1234567890123456789012345678901234567890",
                chainId: "ethereum-mainnet",
                goal: goal
            )
        }
    }

    @Test("TransactionMutationService rejects writes for shared assets")
    func transactionMutationServiceRejectsSharedGoalMutation() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "Shared Goal")
        let asset = TestDataFactory.createSampleAsset(currency: "BTC", goal: goal)
        context.insert(goal)
        context.insert(asset)
        try context.save()
        let service = TransactionMutationService(
            modelContext: context,
            accessGuard: DenyingFamilyShareAccessGuard(sharedGoalIDs: [goal.id])
        )

        #expect(throws: FamilyShareReadOnlyAccessError.self) {
            _ = try service.createTransaction(
                for: asset,
                amount: 100,
                date: Date(),
                comment: "Blocked",
                autoAllocateGoalId: nil
            )
        }
    }

    @Test("TransactionMutationService posts retained goal updates without retired planning notifications")
    func transactionMutationServiceOmitsRetiredPlanningNotification() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let goal = TestDataFactory.createSampleGoal(name: "MVP Goal")
        let asset = TestDataFactory.createSampleAsset(currency: "BTC", goal: goal)
        context.insert(goal)
        context.insert(asset)
        try context.save()

        let service = TransactionMutationService(
            modelContext: context,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )

        let planningSignal = NotificationFlagBox()
        let sharedGoalSignal = NotificationCaptureBox()

        let planningToken = NotificationCenter.default.addObserver(
            forName: .monthlyPlanningAssetUpdated,
            object: nil,
            queue: nil
        ) { _ in
            planningSignal.wasPosted = true
        }

        let sharedGoalToken = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { notification in
            sharedGoalSignal.userInfo = notification.userInfo
        }

        defer {
            NotificationCenter.default.removeObserver(planningToken)
            NotificationCenter.default.removeObserver(sharedGoalToken)
        }

        _ = try service.createTransaction(
            for: asset,
            amount: 125,
            date: Date(),
            comment: "MVP contribution",
            autoAllocateGoalId: nil
        )

        let affectedGoalIDs = sharedGoalSignal.userInfo?["affectedGoalIDs"] as? [UUID]
        #expect(planningSignal.wasPosted == false)
        #expect(sharedGoalSignal.userInfo?["reason"] as? String == "transactionMutation")
        #expect(affectedGoalIDs == [goal.id])
    }

    @Test("PlanningMutationService rejects updates for shared plans")
    func planningMutationServiceRejectsSharedGoalMutation() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let exchangeRates = MockExchangeRateService()
        let goal = TestDataFactory.createSampleGoal(name: "Shared Planning Goal")
        let plan = MonthlyPlan(
            goalId: goal.id,
            monthLabel: "2026-03",
            requiredMonthly: 150,
            remainingAmount: 500,
            monthsRemaining: 4,
            currency: "USD",
            state: .draft
        )
        context.insert(goal)
        context.insert(plan)
        try context.save()
        let service = PlanningMutationService(
            modelContext: context,
            exchangeRateService: exchangeRates,
            accessGuard: DenyingFamilyShareAccessGuard(sharedGoalIDs: [goal.id])
        )

        #expect(throws: FamilyShareReadOnlyAccessError.self) {
            try service.markPlanCompleted(plan)
        }
    }

    @Test("PlanningMutationService posts shared-goal change when feasibility updates goal semantics")
    func planningMutationServicePostsSharedGoalChangeForFeasibilityUpdates() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let exchangeRates = MockExchangeRateService()
        let goal = TestDataFactory.createSampleGoal(name: "Feasibility Goal")
        context.insert(goal)
        try context.save()

        let service = PlanningMutationService(
            modelContext: context,
            exchangeRateService: exchangeRates,
            accessGuard: AllowAllFamilyShareAccessGuard()
        )

        let capture = NotificationCaptureBox()
        let token = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { notification in
            capture.userInfo = notification.userInfo
        }
        defer { NotificationCenter.default.removeObserver(token) }

        _ = try service.applyFeasibilitySuggestion(
            .reduceTarget(goalId: goal.id, goalName: goal.name, to: 3500, currency: goal.currency),
            goals: [goal]
        )

        let affectedGoalIDs = capture.userInfo?["affectedGoalIDs"] as? [UUID]
        #expect(capture.userInfo?["reason"] as? String == "goalMutation")
        #expect(affectedGoalIDs == [goal.id])
    }

    @Test("OnboardingMutationService posts shared-goal change after template goal creation")
    func onboardingMutationServicePostsSharedGoalChange() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let service = OnboardingMutationService(modelContext: context)

        let capture = NotificationCaptureBox()
        let token = NotificationCenter.default.addObserver(
            forName: .sharedGoalDataDidChange,
            object: nil,
            queue: nil
        ) { notification in
            capture.userInfo = notification.userInfo
        }
        defer { NotificationCenter.default.removeObserver(token) }

        try await service.createGoalFromTemplate(.allTemplates[0], userProfile: UserProfile())

        let goals = try context.fetch(FetchDescriptor<Goal>())
        let affectedGoalIDs = capture.userInfo?["affectedGoalIDs"] as? [UUID]
        #expect(goals.count == 1)
        #expect(capture.userInfo?["reason"] as? String == "goalMutation")
        #expect(affectedGoalIDs == [goals[0].id])
        #expect(goals[0].reminderFrequency == nil)
        #expect(goals[0].reminderTime == nil)
        #expect(goals[0].firstReminderDate == nil)
    }
}

@MainActor
private final class AllowAllFamilyShareAccessGuard: FamilyShareAccessChecking {
    func isSharedGoalID(_ goalID: UUID) -> Bool { false }
    func assertOwnerWritable(goalID: UUID) throws {}
    func assertOwnerWritable(goal: Goal) throws {}
    func assertOwnerWritable(asset: Asset) throws {}
    func assertOwnerWritable(transaction: Transaction) throws {}
    func assertOwnerWritable(plan: MonthlyPlan) throws {}
    func assertOwnerWritable(plans: [MonthlyPlan]) throws {}
    func assertOwnerWritable(goals: [Goal]) throws {}
}

@MainActor
private final class DenyingFamilyShareAccessGuard: FamilyShareAccessChecking {
    private let sharedGoalIDs: Set<UUID>

    init(sharedGoalIDs: Set<UUID>) {
        self.sharedGoalIDs = sharedGoalIDs
    }

    convenience init(sharedGoalIDs: [UUID]) {
        self.init(sharedGoalIDs: Set(sharedGoalIDs))
    }

    func isSharedGoalID(_ goalID: UUID) -> Bool {
        sharedGoalIDs.contains(goalID)
    }

    func assertOwnerWritable(goalID: UUID) throws {
        if isSharedGoalID(goalID) {
            throw FamilyShareReadOnlyAccessError.sharedGoalReadOnly
        }
    }

    func assertOwnerWritable(goal: Goal) throws {
        try assertOwnerWritable(goalID: goal.id)
    }

    func assertOwnerWritable(asset: Asset) throws {
        for allocation in asset.allocations ?? [] {
            if let goal = allocation.goal {
                try assertOwnerWritable(goal: goal)
                return
            }
        }
    }

    func assertOwnerWritable(transaction: Transaction) throws {
        if let asset = transaction.asset {
            try assertOwnerWritable(asset: asset)
        }
    }

    func assertOwnerWritable(plan: MonthlyPlan) throws {
        try assertOwnerWritable(goalID: plan.goalId)
    }

    func assertOwnerWritable(plans: [MonthlyPlan]) throws {
        for plan in plans {
            try assertOwnerWritable(plan: plan)
        }
    }

    func assertOwnerWritable(goals: [Goal]) throws {
        for goal in goals {
            try assertOwnerWritable(goal: goal)
        }
    }
}
