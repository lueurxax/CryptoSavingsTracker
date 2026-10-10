import Foundation
import SwiftData
import Testing
@testable import CryptoSavingsTracker

@MainActor
struct AddTransactionViewSaveFailureTests {
    @Test("save failure keeps the sheet open and exposes retryable error")
    func saveFailureDoesNotDismissAndKeepsDraftValues() {
        let asset = Asset(currency: "USD")
        let service = FailingTransactionMutationService()
        let transactionDate = Date(timeIntervalSince1970: 1_776_014_400)

        let result = AddTransactionSaveCoordinator.save(
            asset: asset,
            amountText: "125.50",
            date: transactionDate,
            comment: "April deposit",
            autoAllocateGoalId: nil,
            service: service
        )

        #expect(service.receivedAsset === asset)
        #expect(service.receivedAmount == 125.50)
        #expect(service.receivedDate == transactionDate)
        #expect(service.receivedComment == "April deposit")
        #expect(result.shouldDismiss == false)
        #expect(result.error?.title == "Transaction Not Saved")
        #expect(result.error?.isRetryable == true)
        #expect((asset.transactions ?? []).isEmpty)
    }

    @Test("localized crypto amount is parsed before transaction persistence")
    func localizedCryptoAmountReachesMutationService() {
        let asset = Asset(currency: "BTC")
        let service = RecordingTransactionMutationService()

        let result = AddTransactionSaveCoordinator.save(
            asset: asset,
            amountText: "1,12345678",
            locale: Locale(identifier: "de_DE"),
            date: Date(timeIntervalSince1970: 1_776_014_400),
            comment: "",
            autoAllocateGoalId: nil,
            service: service
        )

        #expect(result.shouldDismiss == true)
        #expect(result.error == nil)
        #expect(service.receivedAmount == 1.12345678)
    }

    @Test("clean-context validation keeps its actionable save-or-discard guidance")
    func validationFailurePreservesMutationGuidance() {
        let result = AddTransactionSaveCoordinator.save(
            asset: Asset(currency: "USD"),
            amountText: "25",
            date: Date(timeIntervalSince1970: 1_776_014_400),
            comment: "",
            autoAllocateGoalId: nil,
            service: ValidationFailingTransactionMutationService()
        )

        #expect(result.shouldDismiss == false)
        #expect(result.error?.message == "Save or discard other edits before continuing.")
        #expect(
            result.error?.recoverySuggestion?.localizedCaseInsensitiveContains(
                "save or discard"
            ) == true
        )
    }

    @Test("add transaction view wires injectable service, retry alert, and no failure dismiss")
    func addTransactionViewFailureRecoveryContract() throws {
        let root = repositoryRoot()
        let source = try readSource(root, "ios/CryptoSavingsTracker/Views/AddTransactionView.swift")

        #expect(source.contains("transactionServiceFactory"))
        #expect(source.contains("@State private var transactionDate = Date()"))
        #expect(source.contains("DatePicker("))
        #expect(source.contains("date: transactionDate"))
        #expect(source.contains("AddTransactionSaveCoordinator.save"))
        #expect(source.contains("Button(\"Retry\")"))
        #expect(source.contains("if let error = result.error"))
        #expect(source.contains("return\n        }\n\n        if result.shouldDismiss"))
        #expect(!source.contains("TODO: Add error state display"))
        #expect(!source.contains("print("))
        #expect(!source.contains("EmptyView()"))
        #expect(!source.contains("amount = Self.formatAmount"))
        #expect(!source.contains("comment.removeAll()"))
    }

    @Test("goal forms map persistence validation errors without replacing their guidance")
    func goalFormValidationFailurePresentationContract() throws {
        let root = repositoryRoot()
        let addGoalSource = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/AddGoalView.swift"
        )
        let editGoalSource = try readSource(
            root,
            "ios/CryptoSavingsTracker/Views/EditGoalView.swift"
        )

        #expect(addGoalSource.contains("PersistenceMutationErrorPresentation.message"))
        #expect(editGoalSource.contains("PersistenceMutationErrorPresentation.message"))
    }

    @Test("asset transaction refresh preserves retained rows and exposes a retryable provider error")
    func assetTransactionRefreshPreservesRowsOnProviderFailure() async {
        let asset = Asset(currency: "SOL", address: "CaseSensitiveWallet", chainId: "SOL")
        let retained = TatumTransaction(
            hash: "retained-signature",
            timestamp: 1_750_000_000_000,
            chain: "SOL",
            address: "CaseSensitiveWallet",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let viewModel = AssetViewModel(
            asset: asset,
            tatumService: TransactionHistoryTatumService(
                result: .failure(TransactionHistoryFailure.provider)
            )
        )
        viewModel.onChainTransactions = [retained]

        await viewModel.fetchTransactions(forceRefresh: true)

        #expect(viewModel.onChainTransactions.map(\.hash) == ["retained-signature"])
        #expect(viewModel.transactionError != nil)
        #expect(viewModel.isLoadingTransactions == false)
    }

    @Test("asset transaction refresh quarantines cross-asset legacy history and publishes the canonical row")
    func assetTransactionRefreshQuarantinesCrossAssetLegacyHistory() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "USDT", address: trackedAddress, chainId: "ETH")
        let otherAsset = Asset(
            currency: "USDC",
            address: "0x00000000000000000000000000000000000000bb",
            chainId: "ETH"
        )
        let conflictingLegacy = Transaction(
            amount: 99,
            asset: otherAsset,
            source: .onChain,
            externalId: "cross-asset-import-hash"
        )
        context.insert(asset)
        context.insert(otherAsset)
        context.insert(conflictingLegacy)
        try context.save()

        let retained = TatumTransaction(
            hash: "retained-history",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 1,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "1",
            tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7"
        )
        let fetched = TatumTransaction(
            hash: "cross-asset-import-hash",
            timestamp: 1_750_000_100_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 2,
            transactionType: "fungible",
            transactionSubtype: "incoming",
            amount: "2",
            tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7"
        )
        let viewModel = AssetViewModel(
            asset: asset,
            tatumService: TransactionHistoryTatumService(result: .success([fetched])),
            modelContext: context
        )
        viewModel.onChainTransactions = [retained]

        await viewModel.fetchTransactions(forceRefresh: true)

        #expect(viewModel.onChainTransactions.map(\.hash) == ["cross-asset-import-hash"])
        #expect(viewModel.transactionError == nil)

        let durableRows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        #expect(durableRows.count == 2)
        #expect(
            durableRows.contains {
                $0.id == conflictingLegacy.id
                    && $0.asset?.id == otherAsset.id
                    && $0.externalId == "cross-asset-import-hash"
                    && $0.amount == 99
            }
        )
        #expect(
            durableRows.contains {
                $0.asset?.id == asset.id
                    && $0.id != conflictingLegacy.id
                    && $0.externalId?.contains("cross-asset-import-hash") == true
                    && $0.amount == 2
            }
        )
    }

    @Test("asset transaction refresh publishes only durable accepted history")
    func assetTransactionRefreshPublishesOnlyDurableAcceptedHistory() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "USDT", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        let fetched = mixedUSDTTransactionBatch(trackedAddress: trackedAddress)
        let viewModel = AssetViewModel(
            asset: asset,
            tatumService: TransactionHistoryTatumService(result: .success(fetched)),
            modelContext: context
        )

        await viewModel.fetchTransactions(forceRefresh: true)

        #expect(viewModel.onChainTransactions.map(\.hash) == ["canonical-hash"])
        #expect(viewModel.transactionError == nil)
        #expect(viewModel.isLoadingTransactions == false)

        let durableRows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        #expect(durableRows.count == 1)
        #expect(durableRows.first?.externalId?.contains("|canonical-hash|") == true)
    }

    @Test("asset row refresh publishes only durable accepted history")
    func assetRowRefreshPublishesOnlyDurableAcceptedHistory() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "USDT", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        let result = try await AssetRowTransactionRefreshCoordinator.fetchAndImport(
            asset: asset,
            address: trackedAddress,
            chainId: "ETH",
            forceRefresh: true,
            transactionService: TransactionHistoryTatumService(
                result: .success(mixedUSDTTransactionBatch(trackedAddress: trackedAddress))
            ),
            modelContext: context
        )

        #expect(result.acceptedTransactions.map(\.hash) == ["canonical-hash"])
        #expect(result.mutationCount == 1)

        let durableRows = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        #expect(durableRows.count == 1)
        #expect(durableRows.first?.externalId?.contains("|canonical-hash|") == true)
    }

    @Test("import result excludes a pending canonical twin without saving unrelated drafts")
    func importResultExcludesPendingCanonicalTwin() throws {
        let fixture = try pendingCanonicalPublicationFixture()
        var saveAttempts = 0
        let importer = OnChainTransactionImportService(
            modelContext: fixture.context,
            saveChanges: {
                saveAttempts += 1
                try fixture.context.save()
            }
        )

        let result = try importer.upsertWithResult(
            transactions: [fixture.durableMovement, fixture.pendingMovement],
            for: fixture.asset
        )

        #expect(result.acceptedTransactions.map(\.hash) == ["durable-movement"])
        #expect(result.mutationCount == 0)
        #expect(saveAttempts == 0)
        try assertPendingPublicationFixtureRemainsUnsaved(fixture)
    }

    @Test("asset transaction refresh does not publish a pending canonical twin")
    func assetTransactionRefreshExcludesPendingCanonicalTwin() async throws {
        let fixture = try pendingCanonicalPublicationFixture()
        let viewModel = AssetViewModel(
            asset: fixture.asset,
            tatumService: TransactionHistoryTatumService(
                result: .success([
                    fixture.durableMovement,
                    fixture.pendingMovement
                ])
            ),
            modelContext: fixture.context
        )

        await viewModel.fetchTransactions(forceRefresh: true)

        #expect(viewModel.onChainTransactions.map(\.hash) == ["durable-movement"])
        #expect(viewModel.transactionError == nil)
        #expect(viewModel.isLoadingTransactions == false)
        try assertPendingPublicationFixtureRemainsUnsaved(fixture)
    }

    @Test("asset row refresh does not publish a pending canonical twin")
    func assetRowRefreshExcludesPendingCanonicalTwin() async throws {
        let fixture = try pendingCanonicalPublicationFixture()

        let result = try await AssetRowTransactionRefreshCoordinator.fetchAndImport(
            asset: fixture.asset,
            address: fixture.trackedAddress,
            chainId: "ETH",
            forceRefresh: true,
            transactionService: TransactionHistoryTatumService(
                result: .success([
                    fixture.durableMovement,
                    fixture.pendingMovement
                ])
            ),
            modelContext: fixture.context
        )

        #expect(result.acceptedTransactions.map(\.hash) == ["durable-movement"])
        #expect(result.mutationCount == 0)
        try assertPendingPublicationFixtureRemainsUnsaved(fixture)
    }

    @Test("cross-asset canonical row cannot authorize pending target history")
    func crossAssetCanonicalRowDoesNotAuthorizeTargetPublication() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let targetAsset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        let otherAsset = Asset(
            currency: "ETH",
            address: "0x00000000000000000000000000000000000000bb",
            chainId: "ETH"
        )
        let movement = TatumTransaction(
            hash: "cross-asset-spoof",
            timestamp: 1_750_000_200_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 3,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "3.5"
        )
        let targetExternalID = try canonicalExternalID(
            for: movement,
            asset: targetAsset
        )
        let crossAssetRow = Transaction(
            amount: 99,
            asset: otherAsset,
            source: .onChain,
            externalId: targetExternalID
        )
        otherAsset.transactions = [crossAssetRow]
        context.insert(targetAsset)
        context.insert(otherAsset)
        context.insert(crossAssetRow)
        try context.saveWithRelationships()

        let pendingTargetTwin = Transaction(
            amount: 3.5,
            asset: targetAsset,
            date: movement.date,
            source: .onChain,
            externalId: targetExternalID
        )
        targetAsset.transactions = [pendingTargetTwin]
        context.insert(pendingTargetTwin)
        context.processPendingChanges()

        var saveAttempts = 0
        let result = try OnChainTransactionImportService(
            modelContext: context,
            saveChanges: {
                saveAttempts += 1
                try context.save()
            }
        ).upsertWithResult(
            transactions: [movement],
            for: targetAsset
        )

        #expect(result.acceptedTransactions.isEmpty)
        #expect(result.mutationCount == 0)
        #expect(saveAttempts == 0)
        #expect(
            context.insertedModelsArray.contains {
                $0.persistentModelID == pendingTargetTwin.persistentModelID
            }
        )

        let durableContext = ModelContext(container)
        let targetRows = try durableContext.fetch(FetchDescriptor<Transaction>())
            .filter { $0.asset?.id == targetAsset.id }
        #expect(targetRows.isEmpty)
        let durableCrossAssetRow = try #require(
            durableContext.fetch(FetchDescriptor<Transaction>()).first {
                $0.id == crossAssetRow.id
            }
        )
        #expect(durableCrossAssetRow.asset?.id == otherAsset.id)
        #expect(durableCrossAssetRow.externalId == targetExternalID)
    }

    @Test("rejected provider history is not cached before corrected normal refresh")
    func rejectedProviderBatchDoesNotPoisonTransactionCache() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()

        func movement(
            transactionIndex: Int?,
            logIndex: Int?
        ) -> TatumTransaction {
            TatumTransaction(
                hash: "correctable-provider-history",
                timestamp: 1_750_000_000_000,
                chain: "ethereum-mainnet",
                address: trackedAddress,
                transactionIndex: transactionIndex,
                logIndex: logIndex,
                transactionType: "native",
                transactionSubtype: "incoming",
                amount: "1"
            )
        }
        let service = SequencedTransactionHistoryService(
            batches: [
                [
                    movement(transactionIndex: 7, logIndex: nil),
                    movement(transactionIndex: nil, logIndex: 11)
                ],
                [movement(transactionIndex: 7, logIndex: 11)]
            ]
        )

        await #expect(throws: (any Error).self) {
            _ = try await AssetRowTransactionRefreshCoordinator.fetchAndImport(
                asset: asset,
                address: trackedAddress,
                chainId: "ETH",
                forceRefresh: true,
                transactionService: service,
                modelContext: context
            )
        }
        #expect(service.fetchCount == 1)
        #expect(service.committedBatches.isEmpty)
        #expect((asset.transactions ?? []).isEmpty)

        let result = try await AssetRowTransactionRefreshCoordinator.fetchAndImport(
            asset: asset,
            address: trackedAddress,
            chainId: "ETH",
            forceRefresh: false,
            transactionService: service,
            modelContext: context
        )
        #expect(service.fetchCount == 2)
        #expect(result.acceptedTransactions.count == 1)
        #expect(result.mutationCount == 1)
        #expect(service.committedBatches.count == 1)
        #expect(service.committedBatches.first?.map(\.hash) == [
            "correctable-provider-history"
        ])
    }

    @Test("durable lookup failure occurs before import mutation or save")
    func durableLookupFailurePrecedesMutationAndSave() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        context.insert(asset)
        try context.save()
        let movement = TatumTransaction(
            hash: "lookup-failure-movement",
            timestamp: 1_750_000_300_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 4,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "4.5"
        )
        var lookupAttempts = 0
        var saveAttempts = 0
        let importer = OnChainTransactionImportService(
            modelContext: context,
            saveChanges: {
                saveAttempts += 1
                try context.save()
            },
            durableCanonicalExternalIDLookup: { _, _, _ in
                lookupAttempts += 1
                throw DurableAcceptedHistoryLookupError.injected
            }
        )

        #expect(throws: DurableAcceptedHistoryLookupError.self) {
            _ = try importer.upsertWithResult(
                transactions: [movement],
                for: asset
            )
        }

        #expect(lookupAttempts == 1)
        #expect(saveAttempts == 0)
        #expect((asset.transactions ?? []).isEmpty)
        #expect(context.insertedModelsArray.isEmpty)
        #expect(context.changedModelsArray.isEmpty)
        #expect(context.deletedModelsArray.isEmpty)
        #expect(
            try ModelContext(container).fetch(FetchDescriptor<Transaction>()).isEmpty
        )
    }

    @Test("asset row exposes retained-history error copy and a retry action")
    func assetRowTransactionFailureRecoveryContract() throws {
        let root = repositoryRoot()
        let source = try readSource(root, "ios/CryptoSavingsTracker/Views/AssetRowView.swift")

        #expect(source.contains("@State private var transactionSyncError: String?"))
        #expect(source.contains("Transaction history could not be updated"))
        #expect(source.contains("Button(\"Retry\")"))
        #expect(source.contains("transactionSyncError = error.localizedDescription"))
        #expect(!source.contains("Silent failure - empty transaction list"))
        #expect(!source.contains("(try? importer.upsert"))
    }

    @Test("older provider history cannot publish after a newer route generation")
    func staleProviderHistoryCannotMutateDurableRowsOrCacheHandshake() async throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000ee"
        let asset = Asset(
            currency: "ETH",
            address: trackedAddress,
            chainId: "ETH"
        )
        context.insert(asset)
        try context.save()

        let gate = ProviderRefreshGenerationGate()
        let routeKey = "history-race-\(UUID().uuidString)"
        let olderToken = gate.begin(routeKey: routeKey)
        let newerToken = gate.begin(routeKey: routeKey)
        let older = TatumTransaction(
            hash: "older-late-response",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 1,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1"
        )
        let newer = TatumTransaction(
            hash: "newer-fast-response",
            timestamp: 1_750_000_100_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 2,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "2"
        )
        let service = TokenizedTransactionHistoryService(
            batches: [
                ProviderTransactionHistoryBatch(
                    transactions: [newer],
                    publicationToken: newerToken
                ),
                ProviderTransactionHistoryBatch(
                    transactions: [older],
                    publicationToken: olderToken
                )
            ]
        )

        let published = try await AssetRowTransactionRefreshCoordinator
            .fetchAndImport(
                asset: asset,
                address: trackedAddress,
                chainId: "ETH",
                forceRefresh: true,
                transactionService: service,
                modelContext: context
            )
        let superseded = try await AssetRowTransactionRefreshCoordinator
            .fetchAndImport(
                asset: asset,
                address: trackedAddress,
                chainId: "ETH",
                forceRefresh: true,
                transactionService: service,
                modelContext: context
            )

        #expect(published.wasPublished)
        #expect(published.acceptedTransactions.map(\.hash) == [newer.hash])
        #expect(superseded.wasPublished == false)
        #expect(superseded.mutationCount == 0)
        #expect(service.committedBatches.map { $0.map(\.hash) } == [[newer.hash]])
        let durable = try context.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        #expect(durable.count == 1)
        #expect(durable.first?.externalId?.contains("|newer-fast-response|") == true)
        #expect(
            durable.contains {
                $0.externalId?.contains("|older-late-response|") == true
            } == false
        )
    }

    @Test("older balance response resolves to the newer cached generation")
    func staleBalanceResponseCannotOverwriteNewerCache() throws {
        let gate = ProviderRefreshGenerationGate()
        let routeKey = "balance-race-\(UUID().uuidString)"
        let olderToken = gate.begin(routeKey: routeKey)
        let newerToken = gate.begin(routeKey: routeKey)

        let newerResult = BalanceService.publishFetchedBalance(
            25,
            cacheKey: routeKey,
            publicationToken: newerToken,
            refreshGenerationGate: gate
        )
        let olderResult = BalanceService.publishFetchedBalance(
            10,
            cacheKey: routeKey,
            publicationToken: olderToken,
            refreshGenerationGate: gate
        )

        #expect(newerResult == 25)
        #expect(olderResult == 25)
        #expect(BalanceCacheManager.shared.getCachedBalance(for: routeKey) == 25)
    }

    @Test("superseded balance does not return old cache while replacement is in flight")
    func supersededBalanceDoesNotMasqueradeAsInFlightGeneration() throws {
        let gate = ProviderRefreshGenerationGate()
        let routeKey = "balance-in-flight-race-\(UUID().uuidString)"
        let cachedToken = gate.begin(routeKey: routeKey)
        let cachedResult = BalanceService.publishFetchedBalance(
            5,
            cacheKey: routeKey,
            publicationToken: cachedToken,
            refreshGenerationGate: gate
        )
        let olderToken = gate.begin(routeKey: routeKey)
        _ = gate.begin(routeKey: routeKey)

        let olderResult = BalanceService.publishFetchedBalance(
            10,
            cacheKey: routeKey,
            publicationToken: olderToken,
            refreshGenerationGate: gate
        )

        #expect(cachedResult == 5)
        #expect(olderResult == nil)
        #expect(BalanceCacheManager.shared.getCachedBalance(for: routeKey) == 5)
    }

    private func mixedUSDTTransactionBatch(trackedAddress: String) -> [TatumTransaction] {
        [
            TatumTransaction(
                hash: "native-hash",
                chain: "ethereum-mainnet",
                address: trackedAddress,
                transactionType: "native",
                transactionSubtype: "incoming",
                amount: "5"
            ),
            TatumTransaction(
                hash: "counterfeit-hash",
                chain: "ethereum-mainnet",
                address: trackedAddress,
                transactionType: "fungible",
                transactionSubtype: "incoming",
                amount: "500",
                tokenAddress: "0x0000000000000000000000000000000000000bad"
            ),
            TatumTransaction(
                hash: "canonical-hash",
                chain: "ethereum-mainnet",
                address: trackedAddress,
                transactionType: "fungible",
                transactionSubtype: "incoming",
                amount: "2.5",
                tokenAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7"
            )
        ]
    }

    private struct PendingCanonicalPublicationFixture {
        let container: ModelContainer
        let context: ModelContext
        let trackedAddress: String
        let asset: Asset
        let durableMovement: TatumTransaction
        let pendingMovement: TatumTransaction
        let pendingCanonical: Transaction
        let dirtyGoal: Goal
        let durableGoalName: String
        let pendingUnrelatedAsset: Asset
        let deletedUnrelatedTransaction: Transaction
    }

    private func pendingCanonicalPublicationFixture() throws
        -> PendingCanonicalPublicationFixture {
        let container = try TestContainer.create()
        let context = ModelContext(container)
        let trackedAddress = "0x00000000000000000000000000000000000000aa"
        let asset = Asset(currency: "ETH", address: trackedAddress, chainId: "ETH")
        let durableMovement = TatumTransaction(
            hash: "durable-movement",
            timestamp: 1_750_000_000_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 1,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "1.25"
        )
        let pendingMovement = TatumTransaction(
            hash: "pending-movement",
            timestamp: 1_750_000_100_000,
            chain: "ethereum-mainnet",
            address: trackedAddress,
            transactionIndex: 2,
            transactionType: "native",
            transactionSubtype: "incoming",
            amount: "2.5"
        )
        let durableTransaction = Transaction(
            amount: 1.25,
            asset: asset,
            date: durableMovement.date,
            source: .onChain,
            externalId: try canonicalExternalID(for: durableMovement, asset: asset)
        )
        let durableGoalName = "Durable unrelated goal"
        let dirtyGoal = TestDataFactory.createSampleGoal(name: durableGoalName)
        let unrelatedDurableAsset = Asset(currency: "USD")
        let deletedUnrelatedTransaction = Transaction(
            amount: 50,
            asset: unrelatedDurableAsset,
            comment: "Durable unrelated transaction"
        )
        asset.transactions = [durableTransaction]
        unrelatedDurableAsset.transactions = [deletedUnrelatedTransaction]
        context.insert(asset)
        context.insert(durableTransaction)
        context.insert(dirtyGoal)
        context.insert(unrelatedDurableAsset)
        context.insert(deletedUnrelatedTransaction)
        try context.saveWithRelationships()

        dirtyGoal.name = "Unsaved unrelated goal"
        let pendingUnrelatedAsset = Asset(currency: "PENDING")
        context.insert(pendingUnrelatedAsset)
        context.delete(deletedUnrelatedTransaction)

        let pendingCanonical = Transaction(
            amount: 2.5,
            asset: asset,
            date: pendingMovement.date,
            source: .onChain,
            externalId: try canonicalExternalID(for: pendingMovement, asset: asset)
        )
        context.insert(pendingCanonical)
        asset.transactions = (asset.transactions ?? []) + [pendingCanonical]
        context.processPendingChanges()

        return PendingCanonicalPublicationFixture(
            container: container,
            context: context,
            trackedAddress: trackedAddress,
            asset: asset,
            durableMovement: durableMovement,
            pendingMovement: pendingMovement,
            pendingCanonical: pendingCanonical,
            dirtyGoal: dirtyGoal,
            durableGoalName: durableGoalName,
            pendingUnrelatedAsset: pendingUnrelatedAsset,
            deletedUnrelatedTransaction: deletedUnrelatedTransaction
        )
    }

    private func canonicalExternalID(
        for movement: TatumTransaction,
        asset: Asset
    ) throws -> String {
        let address = try #require(asset.address)
        let chainID = try #require(asset.chainId)
        let route = try BalanceRouteResolver.resolve(
            chainId: chainID,
            symbol: asset.currency,
            chainService: ChainService()
        )
        return [
            OnChainIdentifierPolicy.canonicalNamespace(for: route),
            chainID.lowercased(),
            OnChainIdentifierPolicy.normalizedAddress(address, for: route),
            asset.currency.lowercased(),
            asset.id.uuidString.lowercased(),
            movement.movementIdentity(for: route)
        ].joined(separator: "|")
    }

    private func assertPendingPublicationFixtureRemainsUnsaved(
        _ fixture: PendingCanonicalPublicationFixture
    ) throws {
        let sameContextRows = try fixture.context.fetch(FetchDescriptor<Transaction>())
        #expect(
            sameContextRows.contains {
                $0.persistentModelID == fixture.pendingCanonical.persistentModelID
            }
        )
        #expect(
            fixture.context.insertedModelsArray.contains {
                $0.persistentModelID == fixture.pendingCanonical.persistentModelID
            }
        )
        #expect(
            fixture.context.changedModelsArray.contains {
                $0.persistentModelID == fixture.dirtyGoal.persistentModelID
            }
        )
        #expect(
            fixture.context.insertedModelsArray.contains {
                $0.persistentModelID == fixture.pendingUnrelatedAsset.persistentModelID
            }
        )
        #expect(
            fixture.context.deletedModelsArray.contains {
                $0.persistentModelID
                    == fixture.deletedUnrelatedTransaction.persistentModelID
            }
        )

        let durableContext = ModelContext(fixture.container)
        durableContext.autosaveEnabled = false
        let durableOnChainRows = try durableContext.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain && $0.asset?.id == fixture.asset.id }
        #expect(durableOnChainRows.count == 1)
        #expect(durableOnChainRows.first?.externalId?.contains("|durable-movement|") == true)
        #expect(
            durableOnChainRows.contains {
                $0.externalId?.contains("|pending-movement|") == true
            } == false
        )
        let durableGoal = try #require(
            durableContext.fetch(FetchDescriptor<Goal>()).first {
                $0.id == fixture.dirtyGoal.id
            }
        )
        #expect(durableGoal.name == fixture.durableGoalName)
        let durableAssets = try durableContext.fetch(FetchDescriptor<Asset>())
        #expect(
            durableAssets.contains {
                $0.id == fixture.pendingUnrelatedAsset.id
            } == false
        )
        let durableTransactions = try durableContext.fetch(FetchDescriptor<Transaction>())
        #expect(
            durableTransactions.contains {
                $0.id == fixture.deletedUnrelatedTransaction.id
            }
        )
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

private enum TransactionHistoryFailure: LocalizedError {
    case provider

    var errorDescription: String? {
        "Provider history is unavailable."
    }
}

private enum DurableAcceptedHistoryLookupError: Error {
    case injected
}

private struct TransactionHistoryTatumService: TatumServiceProtocol, TransactionServiceProtocol {
    let result: Result<[TatumTransaction], Error>

    var supportedChains: [TatumChain] { [] }

    func predictChain(for symbol: String) -> TatumChain? {
        nil
    }

    func fetchBalance(
        chainId: String,
        address: String,
        symbol: String,
        forceRefresh: Bool
    ) async throws -> Double {
        0
    }

    func fetchTransactionHistory(
        chainId: String,
        address: String,
        currency: String?,
        limit: Int,
        forceRefresh: Bool
    ) async throws -> [TatumTransaction] {
        try result.get()
    }

    func fetchTransactionHistoryBatch(
        chainId: String,
        address: String,
        currency: String?,
        limit: Int,
        forceRefresh: Bool
    ) async throws -> ProviderTransactionHistoryBatch {
        ProviderTransactionHistoryBatch(
            transactions: try result.get()
        )
    }

    func commitImportedTransactionHistory(
        _ transactions: [TatumTransaction],
        chainId: String,
        address: String,
        currency: String?
    ) {}

    func hasValidConfiguration() -> Bool {
        true
    }

    func setOfflineMode(_ offline: Bool) {}
}

private final class SequencedTransactionHistoryService: TransactionServiceProtocol {
    private var batches: [[TatumTransaction]]
    private(set) var fetchCount = 0
    private(set) var committedBatches: [[TatumTransaction]] = []

    init(batches: [[TatumTransaction]]) {
        self.batches = batches
    }

    func fetchTransactionHistory(
        chainId: String,
        address: String,
        currency: String?,
        limit: Int,
        forceRefresh: Bool
    ) async throws -> [TatumTransaction] {
        fetchCount += 1
        guard !batches.isEmpty else {
            throw TransactionHistoryFailure.provider
        }
        return batches.removeFirst()
    }

    func commitImportedTransactionHistory(
        _ transactions: [TatumTransaction],
        chainId: String,
        address: String,
        currency: String?
    ) {
        committedBatches.append(transactions)
    }
}

private final class TokenizedTransactionHistoryService:
    TransactionServiceProtocol {
    private var batches: [ProviderTransactionHistoryBatch]
    private(set) var committedBatches: [[TatumTransaction]] = []

    init(batches: [ProviderTransactionHistoryBatch]) {
        self.batches = batches
    }

    func fetchTransactionHistory(
        chainId: String,
        address: String,
        currency: String?,
        limit: Int,
        forceRefresh: Bool
    ) async throws -> [TatumTransaction] {
        let batch = try await fetchTransactionHistoryBatch(
            chainId: chainId,
            address: address,
            currency: currency,
            limit: limit,
            forceRefresh: forceRefresh
        )
        return batch.transactions
    }

    func fetchTransactionHistoryBatch(
        chainId: String,
        address: String,
        currency: String?,
        limit: Int,
        forceRefresh: Bool
    ) async throws -> ProviderTransactionHistoryBatch {
        guard !batches.isEmpty else {
            throw TransactionHistoryFailure.provider
        }
        return batches.removeFirst()
    }

    func commitImportedTransactionHistory(
        _ transactions: [TatumTransaction],
        chainId: String,
        address: String,
        currency: String?
    ) {
        committedBatches.append(transactions)
    }
}

@MainActor
private final class RecordingTransactionMutationService: TransactionMutationServiceProtocol {
    private(set) var receivedAmount: Double?

    func createTransaction(
        for asset: Asset,
        amount: Double,
        date: Date,
        comment: String?,
        autoAllocateGoalId: UUID?
    ) throws -> Transaction {
        receivedAmount = amount
        return Transaction(amount: amount, asset: asset, date: date, comment: comment)
    }

    func deleteTransaction(_ transaction: Transaction) throws {}
}

@MainActor
private final class FailingTransactionMutationService: TransactionMutationServiceProtocol {
    enum Failure: Error {
        case forced
    }

    private(set) var receivedAsset: Asset?
    private(set) var receivedAmount: Double?
    private(set) var receivedDate: Date?
    private(set) var receivedComment: String?

    func createTransaction(
        for asset: Asset,
        amount: Double,
        date: Date,
        comment: String?,
        autoAllocateGoalId: UUID?
    ) throws -> Transaction {
        receivedAsset = asset
        receivedAmount = amount
        receivedDate = date
        receivedComment = comment
        throw Failure.forced
    }

    func deleteTransaction(_ transaction: Transaction) throws {}
}

@MainActor
private final class ValidationFailingTransactionMutationService: TransactionMutationServiceProtocol {
    func createTransaction(
        for asset: Asset,
        amount: Double,
        date: Date,
        comment: String?,
        autoAllocateGoalId: UUID?
    ) throws -> Transaction {
        throw PersistenceMutationError.validationFailed(
            "Save or discard other edits before continuing."
        )
    }

    func deleteTransaction(_ transaction: Transaction) throws {}
}
