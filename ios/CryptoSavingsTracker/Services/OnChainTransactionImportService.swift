//
//  OnChainTransactionImportService.swift
//  CryptoSavingsTracker
//
//  Persists fetched on-chain transactions as `Transaction` rows (source: .onChain)
//  so execution tracking can remain timestamp-based without relying on network at calculation time.
//

import Foundation
import SwiftData

enum OnChainTransactionImportError: LocalizedError {
    case ambiguousLegacyMovement(hash: String)
    case ambiguousAutoAllocationHistory(transactionID: UUID)
    case invalidProviderMovement(hash: String)
    case persistenceUnavailable

    var errorDescription: String? {
        switch self {
        case .ambiguousLegacyMovement(let hash):
            return "Cannot safely reconcile legacy on-chain transaction \(hash)."
        case .ambiguousAutoAllocationHistory(let transactionID):
            return "Cannot safely reconcile auto-allocation history for transaction \(transactionID.uuidString)."
        case .invalidProviderMovement(let hash):
            return "Provider returned an invalid on-chain transaction \(hash)."
        case .persistenceUnavailable:
            return "Transaction history cannot be published without durable storage."
        }
    }
}

struct OnChainTransactionImportResult {
    let acceptedTransactions: [TatumTransaction]
    let mutationCount: Int
    let wasPublished: Bool

    init(
        acceptedTransactions: [TatumTransaction],
        mutationCount: Int,
        wasPublished: Bool = true
    ) {
        self.acceptedTransactions = acceptedTransactions
        self.mutationCount = mutationCount
        self.wasPublished = wasPublished
    }

    static var superseded: OnChainTransactionImportResult {
        OnChainTransactionImportResult(
            acceptedTransactions: [],
            mutationCount: 0,
            wasPublished: false
        )
    }
}

private struct LinkedAutoAllocationHistoryUpdate {
    let history: AllocationHistory
    let amount: Double
    let timestamp: Date
    let sourcePreviousAmount: Double
}

private struct LinkedAutoAllocationCorrectionPlan {
    let allocation: AssetAllocation
    let updates: [LinkedAutoAllocationHistoryUpdate]
    let finalAllocationAmount: Double

    func apply() {
        for update in updates {
            update.history.amount = update.amount
            update.history.timestamp = update.timestamp
            update.history.sourcePreviousAmount = update.sourcePreviousAmount
            update.history.monthLabel = MonthlyExecutionRecord.monthLabel(
                from: update.timestamp
            )
        }
        allocation.updateAmount(finalAllocationAmount)
    }
}

@MainActor
final class OnChainTransactionImportService {
    private let modelContext: ModelContext
    private let saveChanges: () throws -> Void
    private let durableCanonicalExternalIDLookup:
        (ModelContext, [String], UUID) throws -> Set<String>

    init(
        modelContext: ModelContext,
        saveChanges: (() throws -> Void)? = nil,
        durableCanonicalExternalIDLookup: ((
            ModelContext,
            [String],
            UUID
        ) throws -> Set<String>)? = nil
    ) {
        self.modelContext = modelContext
        self.saveChanges = saveChanges ?? {
            try modelContext.save()
        }
        self.durableCanonicalExternalIDLookup =
            durableCanonicalExternalIDLookup ?? { context, externalIDs, assetID in
                let onChainSource = TransactionSource.onChain.rawValue
                var durableExternalIDs = Set<String>()
                for externalID in externalIDs {
                    let candidateExternalID = externalID
                    let descriptor = FetchDescriptor<Transaction>(
                        predicate: #Predicate<Transaction> { transaction in
                            transaction.externalId == candidateExternalID
                                && transaction.sourceRawValue == onChainSource
                        }
                    )
                    if try context.fetch(descriptor).contains(where: {
                        $0.asset?.id == assetID
                    }) {
                        durableExternalIDs.insert(candidateExternalID)
                    }
                }
                return durableExternalIDs
            }
    }

    /// Upserts fetched on-chain transactions into SwiftData as `Transaction` rows.
    /// - Returns: number of inserted or safely reconciled transactions.
    func upsert(transactions: [TatumTransaction], for asset: Asset) throws -> Int {
        try upsertWithResult(transactions: transactions, for: asset).mutationCount
    }

    /// Upserts fetched movements and returns the exact provider rows accepted by
    /// the same canonical route validation that governs durable persistence.
    func upsertWithResult(
        transactions: [TatumTransaction],
        for asset: Asset
    ) throws -> OnChainTransactionImportResult {
        guard let address = asset.address,
              let chainId = asset.chainId,
              !address.isEmpty,
              !chainId.isEmpty
        else {
            return OnChainTransactionImportResult(
                acceptedTransactions: [],
                mutationCount: 0
            )
        }

        let route = try BalanceRouteResolver.resolve(
            chainId: chainId,
            symbol: asset.currency,
            chainService: ChainService()
        )
        let normalizedAddress = OnChainIdentifierPolicy.normalizedAddress(
            address,
            for: route
        )
        let scope = OnChainImportScope(
            asset: asset,
            chainId: chainId,
            address: address,
            route: route
        )
        if let invalidMovement = transactions.first(where: {
            !$0.hasValidProviderIdentifiers(for: route)
                || !$0.hasValidProviderEventIndexes
        }) {
            throw OnChainTransactionImportError.invalidProviderMovement(
                hash: invalidMovement.hash
            )
        }
        // Hash-only QUICK rows predate contract filtering, so the hash cannot
        // prove whether the row used old QUICK or current QUICK units.
        let canUpgradeHashOnlyLegacy = !(
            chainId.caseInsensitiveCompare("MATIC") == .orderedSame
                && asset.currency.caseInsensitiveCompare("QUICK") == .orderedSame
        )
        let fetchedOnChain = try modelContext.fetch(FetchDescriptor<Transaction>())
            .filter { $0.source == .onChain }
        let pendingScopedOnChain = modelContext.insertedModelsArray.compactMap {
            model -> Transaction? in
            guard let transaction = model as? Transaction,
                  transaction.source == .onChain,
                  let externalID = transaction.externalId,
                  scope.providerRecordDescriptor(
                      fromCanonicalExternalID: externalID
                  ) != nil
            else {
                return nil
            }
            return transaction
        }
        let allExistingOnChain = Dictionary(
            (
                fetchedOnChain
                    + (asset.transactions ?? []).filter { $0.source == .onChain }
                    + pendingScopedOnChain
            )
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        ).values
        let relationshipTransactionIDs = Set(
            (asset.transactions ?? [])
                .filter { $0.source == .onChain }
                .map(\.id)
        )
        let pendingScopedTransactionIDs = Set(pendingScopedOnChain.map(\.id))
        let existingOnChain = allExistingOnChain.filter { transaction in
            if pendingScopedTransactionIDs.contains(transaction.id) {
                // A pending row is not durable publication evidence, but its
                // scoped provider identity must still suppress a duplicate
                // insert. The external ID scope is authoritative here because
                // SwiftData may expose a transient or stale inverse owner.
                return true
            }
            if transaction.asset?.id == asset.id {
                return true
            }
            // SwiftData can temporarily leave the inverse relationship unset
            // for an inserted transaction even though it is already present
            // in `asset.transactions`. Keep that pending row in the
            // de-duplication index, but never let a row explicitly owned by a
            // different asset enter this import scope.
            return transaction.asset == nil
                && relationshipTransactionIDs.contains(transaction.id)
        }
        let durableExistingOnChain = existingOnChain.filter {
            !pendingScopedTransactionIDs.contains($0.id)
        }
        let existingByExternalIDGroups = Dictionary(
            grouping: durableExistingOnChain.compactMap {
                transaction -> (String, Transaction)? in
                transaction.externalId.map { ($0, transaction) }
            },
            by: \.0
        ).mapValues { $0.map(\.1) }
        var existingByExternalID = existingByExternalIDGroups.compactMapValues(\.first)
        let parsedDurableProviderRecords = durableExistingOnChain.compactMap {
            transaction -> (Transaction, InstalledProviderRecordDescriptor)? in
            guard let externalID = transaction.externalId,
                  let descriptor = scope.providerRecordDescriptor(
                    fromCanonicalExternalID: externalID
                  )
            else {
                return nil
            }
            return (transaction, descriptor)
        }
        let installedProviderRecords = parsedDurableProviderRecords.filter {
            $0.1.eventIndex.hasValidSemanticIndexes
        }
        let invalidInstalledProviderRecords = parsedDurableProviderRecords.filter {
            !$0.1.eventIndex.hasValidSemanticIndexes
        }
        let pendingProviderRecords = pendingScopedOnChain.compactMap {
            transaction -> (Transaction, InstalledProviderRecordDescriptor)? in
            guard let externalID = transaction.externalId,
                  let descriptor = scope.providerRecordDescriptor(
                    fromCanonicalExternalID: externalID
                  ),
                  descriptor.eventIndex.hasValidSemanticIndexes
            else {
                return nil
            }
            return (transaction, descriptor)
        }
        let installedProviderDescriptorByTransactionID = Dictionary(
            installedProviderRecords.map { ($0.0.id, $0.1) },
            uniquingKeysWith: { first, _ in first }
        )
        var existingByProviderRecordKey = Dictionary(
            grouping: installedProviderRecords.flatMap { transaction, descriptor in
                descriptor.keys.map { ($0, transaction) }
            },
            by: \.0
        ).mapValues { entries in
            Dictionary(
                entries.map { ($0.1.id, $0.1) },
                uniquingKeysWith: { first, _ in first }
            ).values.map { $0 }
        }
        var existingByProviderRecordBaseKey = Dictionary(
            grouping: installedProviderRecords.flatMap { transaction, descriptor in
                descriptor.baseKeys.map {
                    ($0, transaction, descriptor.eventIndex)
                }
            },
            by: \.0
        ).mapValues { entries in
            Dictionary(
                entries.map { ($0.1.id, ($0.1, $0.2)) },
                uniquingKeysWith: { first, _ in first }
            ).values.map { $0 }
        }
        let invalidExistingByProviderRecordBaseKey = Dictionary(
            grouping: invalidInstalledProviderRecords.flatMap {
                transaction, descriptor in
                descriptor.baseKeys.map { ($0, transaction) }
            },
            by: \.0
        ).mapValues { entries in
            Dictionary(
                entries.map { ($0.1.id, $0.1) },
                uniquingKeysWith: { first, _ in first }
            ).values.map { $0 }
        }
        let pendingByProviderRecordKey = Dictionary(
            grouping: pendingProviderRecords.flatMap { transaction, descriptor in
                descriptor.keys.map { ($0, transaction) }
            },
            by: \.0
        ).mapValues { entries in
            Dictionary(
                entries.map { ($0.1.id, $0.1) },
                uniquingKeysWith: { first, _ in first }
            ).values.map { $0 }
        }
        let pendingByProviderRecordBaseKey = Dictionary(
            grouping: pendingProviderRecords.flatMap {
                transaction, descriptor in
                descriptor.baseKeys.map {
                    ($0, transaction, descriptor.eventIndex)
                }
            },
            by: \.0
        ).mapValues { entries in
            Dictionary(
                entries.map { ($0.1.id, ($0.1, $0.2)) },
                uniquingKeysWith: { first, _ in first }
            ).values.map { $0 }
        }
        func indexProviderRecord(
            _ storedTransaction: Transaction,
            from providerTransaction: TatumTransaction
        ) {
            for providerKey in scope.providerRecordKeys(for: providerTransaction) {
                var rows = existingByProviderRecordKey[providerKey] ?? []
                if !rows.contains(where: { $0.id == storedTransaction.id }) {
                    rows.append(storedTransaction)
                }
                existingByProviderRecordKey[providerKey] = rows
            }
            let eventIndex = ProviderEventIndex(transaction: providerTransaction)
            for baseKey in scope.providerRecordBaseKeys(for: providerTransaction) {
                var rows = existingByProviderRecordBaseKey[baseKey] ?? []
                if let existingIndex = rows.firstIndex(where: {
                    $0.0.id == storedTransaction.id
                }) {
                    rows[existingIndex] = (storedTransaction, eventIndex)
                } else {
                    rows.append((storedTransaction, eventIndex))
                }
                existingByProviderRecordBaseKey[baseKey] = rows
            }
        }
        var legacyByNormalizedHash = Dictionary(
            grouping: allExistingOnChain.compactMap { transaction -> (String, Transaction)? in
                guard let externalID = transaction.externalId,
                      !externalID.lowercased().hasPrefix("onchain_")
                else {
                    return nil
                }
                return (
                    OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                        externalID,
                        for: route
                    ),
                    transaction
                )
            },
            by: \.0
        ).mapValues { $0.map(\.1) }

        var inserted = 0
        var reconciled = 0
        var mutatedDurableExternalIDs = Set<String>()
        var insertedModels: [Transaction] = []
        insertedModels.reserveCapacity(transactions.count)
        let epsilon = 0.0000000001

        let candidateMovements = transactions.compactMap {
            transaction -> (TatumTransaction, Double)? in
            guard let signedAmount = transaction.signedAmount(
                for: route,
                trackedAddress: normalizedAddress,
                expectedChainId: chainId
            ), abs(signedAmount) > epsilon else {
                return nil
            }
            return (transaction, signedAmount)
        }
        let validMovements = try reconcileIncomingIndexEnrichment(
            candidateMovements,
            scope: scope
        )
        let incomingByCanonicalProviderRecord = Dictionary(
            grouping: validMovements,
            by: { scope.externalID(for: $0.0) }
        )
        if let conflictingProviderRecord = incomingByCanonicalProviderRecord.values.first(
            where: { movements in
                guard let first = movements.first?.0 else { return false }
                return movements.dropFirst().contains {
                    !first.isCanonicalProviderEquivalent(to: $0.0)
                }
            }
        )?.first?.0 {
            throw OnChainTransactionImportError.ambiguousLegacyMovement(
                hash: conflictingProviderRecord.hash
            )
        }

        let canonicalIdentitiesByProviderKey = Dictionary(
            grouping: validMovements.flatMap { transaction, _ in
                scope.providerRecordKeys(for: transaction).map {
                    ($0, scope.externalID(for: transaction))
                }
            },
            by: \.0
        ).mapValues { movements in
            Set(movements.map(\.1))
        }
        if let ambiguousProviderKey = canonicalIdentitiesByProviderKey.keys
            .sorted()
            .first(where: { providerKey in
                guard let existingRows = existingByProviderRecordKey[providerKey],
                      !existingRows.isEmpty
                else {
                    return false
                }
                // Installed multiplicity is classified by the exact/alias
                // collapse preflight below. Reject only when the incoming
                // batch itself assigns this provider key to multiple durable
                // identities.
                return canonicalIdentitiesByProviderKey[providerKey]?.count != 1
            }),
           let movement = validMovements.first(where: {
               scope.providerRecordKeys(for: $0.0).contains(ambiguousProviderKey)
           })?.0 {
            throw OnChainTransactionImportError.ambiguousLegacyMovement(
                hash: movement.hash
            )
        }

        let incomingProviderRecordsByBaseKey = Dictionary(
            grouping: validMovements.flatMap { transaction, _ in
                scope.providerRecordBaseKeys(for: transaction).map {
                    (
                        $0,
                        IncomingProviderRecordDescriptor(
                            externalID: scope.externalID(for: transaction),
                            eventIndex: ProviderEventIndex(transaction: transaction)
                        )
                    )
                }
            },
            by: \.0
        ).mapValues { entries in
            Set(entries.map(\.1))
        }

        var existingProviderRowByCanonicalExternalID: [String: Transaction] = [:]
        var pendingProviderRowByCanonicalExternalID: [String: Transaction] = [:]
        var installedDuplicateCollapsePlanByCanonicalExternalID: [
            String: InstalledProviderDuplicateCollapsePlan
        ] = [:]
        for (transaction, _) in validMovements {
            let canonicalExternalID = scope.externalID(for: transaction)
            let strongMatches = Array(Dictionary(
                scope.providerRecordKeys(for: transaction)
                    .flatMap { existingByProviderRecordKey[$0] ?? [] }
                    .map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values)
            let baseEntries = Array(Dictionary(
                scope.providerRecordBaseKeys(for: transaction)
                    .flatMap { existingByProviderRecordBaseKey[$0] ?? [] }
                    .map { ($0.0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values)
            let incomingEventIndex = ProviderEventIndex(transaction: transaction)
            var matches: [Transaction]
            if strongMatches.count == 1, let strongMatch = strongMatches.first {
                guard !baseEntries.contains(where: { entry in
                    entry.0.id != strongMatch.id
                        && !entry.1.conflicts(with: incomingEventIndex)
                }) else {
                    throw OnChainTransactionImportError.ambiguousLegacyMovement(
                        hash: transaction.hash
                    )
                }
                matches = [strongMatch]
            } else if !strongMatches.isEmpty {
                let incomingCanonicalHash =
                    OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                        transaction.hash,
                        for: route
                    )
                let incomingAliasHashes = scope.normalizedProviderHashes(
                    for: transaction
                ).subtracting([incomingCanonicalHash])
                let installedMatches = strongMatches.compactMap {
                    storedTransaction
                    -> (Transaction, InstalledProviderRecordDescriptor)? in
                    guard let descriptor =
                            installedProviderDescriptorByTransactionID[
                                storedTransaction.id
                            ] else {
                        return nil
                    }
                    return (storedTransaction, descriptor)
                }
                let exactMatches = installedMatches.filter {
                    $0.1.canonicalProviderHash == incomingCanonicalHash
                        && $0.1.eventIndex == incomingEventIndex
                }
                let explicitAliasMatches = installedMatches.filter {
                    incomingAliasHashes.contains($0.1.canonicalProviderHash)
                        && $0.1.eventIndex == incomingEventIndex
                }
                guard scope.isUTXO,
                      strongMatches.count == 2,
                      installedMatches.count == 2,
                      exactMatches.count == 1,
                      explicitAliasMatches.count == 1,
                      let survivor = exactMatches.first?.0,
                      let removed = explicitAliasMatches.first?.0,
                      survivor.id != removed.id
                else {
                    throw OnChainTransactionImportError.ambiguousLegacyMovement(
                        hash: transaction.hash
                    )
                }
                installedDuplicateCollapsePlanByCanonicalExternalID[
                    canonicalExternalID
                ] = InstalledProviderDuplicateCollapsePlan(
                    survivor: survivor,
                    removed: [removed]
                )
                matches = [survivor]
            } else {
                let compatibleEntries = baseEntries.filter {
                    $0.1.isSubset(of: incomingEventIndex)
                }
                if let compatibleEntry = compatibleEntries.first {
                    let competingInstalledEnrichment = baseEntries.contains { entry in
                        entry.0.id != compatibleEntry.0.id
                            && compatibleEntry.1.isStrictSubset(of: entry.1)
                    }
                    let compatibleIncomingIDs = scope.providerRecordBaseKeys(
                        for: transaction
                    ).reduce(into: Set<String>()) { identities, baseKey in
                        let compatibleRecords = (
                            incomingProviderRecordsByBaseKey[baseKey] ?? []
                        ).filter {
                            compatibleEntry.1.isSubset(of: $0.eventIndex)
                        }
                        identities.formUnion(
                            compatibleRecords.map(\.externalID)
                        )
                    }
                    guard compatibleEntries.count == 1,
                          !competingInstalledEnrichment,
                          compatibleIncomingIDs.count == 1
                    else {
                        throw OnChainTransactionImportError.ambiguousLegacyMovement(
                            hash: transaction.hash
                        )
                    }
                    matches = [compatibleEntry.0]
                } else if baseEntries.contains(where: {
                    !$0.1.conflicts(with: incomingEventIndex)
                }) {
                    throw OnChainTransactionImportError.ambiguousLegacyMovement(
                        hash: transaction.hash
                    )
                } else {
                    matches = []
                }
            }

            let invalidMatches = Array(Dictionary(
                scope.providerRecordBaseKeys(for: transaction)
                    .flatMap {
                        invalidExistingByProviderRecordBaseKey[$0] ?? []
                    }
                    .map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values)
            if !invalidMatches.isEmpty {
                let compatibleIncomingIDs = scope.providerRecordBaseKeys(
                    for: transaction
                ).reduce(into: Set<String>()) { identities, baseKey in
                    identities.formUnion(
                        (incomingProviderRecordsByBaseKey[baseKey] ?? [])
                            .map(\.externalID)
                    )
                }
                guard compatibleIncomingIDs == [canonicalExternalID] else {
                    throw OnChainTransactionImportError.ambiguousLegacyMovement(
                        hash: transaction.hash
                    )
                }

                let existingPlan =
                    installedDuplicateCollapsePlanByCanonicalExternalID[
                        canonicalExternalID
                    ]
                let survivor: Transaction
                var removed = existingPlan?.removed ?? []
                if let existingPlan {
                    survivor = existingPlan.survivor
                } else if let existing = matches.first {
                    survivor = existing
                } else {
                    let orderedInvalidMatches = invalidMatches.sorted {
                        $0.id.uuidString < $1.id.uuidString
                    }
                    guard let first = orderedInvalidMatches.first else {
                        throw OnChainTransactionImportError.ambiguousLegacyMovement(
                            hash: transaction.hash
                        )
                    }
                    survivor = first
                    matches = [first]
                    removed.append(contentsOf: orderedInvalidMatches.dropFirst())
                }
                removed.append(
                    contentsOf: invalidMatches.filter { $0.id != survivor.id }
                )
                removed = Array(Dictionary(
                    removed.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                ).values)
                installedDuplicateCollapsePlanByCanonicalExternalID[
                    canonicalExternalID
                ] = InstalledProviderDuplicateCollapsePlan(
                    survivor: survivor,
                    removed: removed
                )
            }

            guard matches.count <= 1 else {
                throw OnChainTransactionImportError.ambiguousLegacyMovement(
                    hash: transaction.hash
                )
            }
            if let existing = matches.first {
                existingProviderRowByCanonicalExternalID[
                    canonicalExternalID
                ] = existing
            } else {
                let pendingStrongMatches = scope.providerRecordKeys(
                    for: transaction
                ).flatMap { pendingByProviderRecordKey[$0] ?? [] }
                let pendingCompatibleBaseMatches = scope.providerRecordBaseKeys(
                    for: transaction
                ).flatMap { baseKey in
                    (pendingByProviderRecordBaseKey[baseKey] ?? [])
                        .filter { $0.1.isSubset(of: incomingEventIndex) }
                        .map(\.0)
                }
                let pendingMatches = Array(Dictionary(
                    (pendingStrongMatches + pendingCompatibleBaseMatches)
                        .map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                ).values)
                guard pendingMatches.count <= 1 else {
                    throw OnChainTransactionImportError.ambiguousLegacyMovement(
                        hash: transaction.hash
                    )
                }
                if let pending = pendingMatches.first {
                    pendingProviderRowByCanonicalExternalID[
                        canonicalExternalID
                    ] = pending
                }
            }
        }
        let canonicalExternalIDsByProviderHash = Dictionary(
            grouping: validMovements.flatMap { transaction, _ in
                scope.normalizedProviderHashes(for: transaction).map {
                    ($0, scope.externalID(for: transaction))
                }
            },
            by: \.0
        ).mapValues { entries in
            Set(entries.map(\.1))
        }
        if scope.isUTXO,
           let ambiguousProviderHash = canonicalExternalIDsByProviderHash.keys
               .sorted()
               .first(where: {
                   (canonicalExternalIDsByProviderHash[$0]?.count ?? 0) > 1
               }),
           let movement = validMovements.first(where: {
               scope.normalizedProviderHashes(for: $0.0)
                   .contains(ambiguousProviderHash)
           })?.0 {
            throw OnChainTransactionImportError.ambiguousLegacyMovement(
                hash: movement.hash
            )
        }

        for (transaction, _) in validMovements {
            let normalizedHash =
                OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                    transaction.hash,
                    for: route
                )
            let normalizedProviderHashes = scope.normalizedProviderHashes(
                for: transaction
            )
            let aliasHashes = normalizedProviderHashes.subtracting([
                normalizedHash
            ])
            guard !aliasHashes.isEmpty else { continue }

            let matchingCanonicalExternalIDs = normalizedProviderHashes.reduce(
                into: Set<String>()
            ) { identities, providerHash in
                identities.formUnion(
                    canonicalExternalIDsByProviderHash[providerHash] ?? []
                )
            }
            let currentAssetLegacyRows = Array(Dictionary(
                normalizedProviderHashes
                    .flatMap { legacyByNormalizedHash[$0] ?? [] }
                    .filter { $0.asset?.id == asset.id }
                    .map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values)
            let currentAssetAliasRows = Array(Dictionary(
                aliasHashes
                    .flatMap { legacyByNormalizedHash[$0] ?? [] }
                    .filter { $0.asset?.id == asset.id }
                    .map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values)
            if !currentAssetAliasRows.isEmpty,
               (!canUpgradeHashOnlyLegacy
                    || matchingCanonicalExternalIDs.count != 1
                    || currentAssetLegacyRows.count != 1) {
                throw OnChainTransactionImportError.ambiguousLegacyMovement(
                    hash: transaction.hash
                )
            }
        }

        let canonicalIdentitiesByLegacyExternalID = Dictionary(
            grouping: validMovements,
            by: { scope.legacyExternalID(for: $0.0) }
        ).mapValues { movements in
            Set(movements.map { scope.externalID(for: $0.0) })
        }
        if let ambiguousLegacyCanonical = canonicalIdentitiesByLegacyExternalID.keys.sorted().first(where: { externalID in
            guard let existingRows = existingByExternalIDGroups[externalID], !existingRows.isEmpty else {
                return false
            }
            return existingRows.count != 1
                || canonicalIdentitiesByLegacyExternalID[externalID]?.count != 1
        }) {
            throw OnChainTransactionImportError.ambiguousLegacyMovement(hash: ambiguousLegacyCanonical)
        }

        if let duplicateCanonical = validMovements.first(where: { movement in
            let externalID = scope.externalID(for: movement.0)
            return (existingByExternalIDGroups[externalID]?.count ?? 0) > 1
        }) {
            throw OnChainTransactionImportError.ambiguousLegacyMovement(hash: duplicateCanonical.0.hash)
        }

        let resolvedExternalIDPairs = try validMovements.map {
            movement, signedAmount in
                let canonicalExternalID = scope.externalID(for: movement)
                let existingProviderRecord =
                    existingByExternalID[canonicalExternalID]
                    ?? existingProviderRowByCanonicalExternalID[
                        canonicalExternalID
                    ]
                if existingProviderRecord == nil,
                   let pendingExternalID =
                        pendingProviderRowByCanonicalExternalID[
                            canonicalExternalID
                        ]?.externalId {
                    return (canonicalExternalID, pendingExternalID)
                }
                if let existingProviderRecord,
                   existingProviderRecord.amount == signedAmount,
                   existingProviderRecord.date == movement.date,
                   let existingExternalID = existingProviderRecord.externalId,
                   scope.canPreserveStableNonUTXOExternalID(
                       existingExternalID,
                       for: movement
                   ) {
                    // Preserve only an exact unchanged durable refresh. Any
                    // provider correction, index enrichment, or case-sensitive
                    // identity upgrade falls through to canonical record_v1.
                    return (canonicalExternalID, existingExternalID)
                }
                return (
                    canonicalExternalID,
                    try scope.reconciledExternalID(
                        for: movement,
                        existingExternalID: existingProviderRecord?.externalId
                    )
                )
            }
        let canonicalExternalIDsByResolvedExternalID = Dictionary(
            grouping: resolvedExternalIDPairs,
            by: \.1
        ).mapValues { Set($0.map(\.0)) }
        if let ambiguousResolvedExternalID =
                canonicalExternalIDsByResolvedExternalID.keys.sorted().first(
                    where: {
                        (canonicalExternalIDsByResolvedExternalID[$0]?.count ?? 0)
                            > 1
                    }
                ),
           let movement = validMovements.first(where: {
               let canonicalExternalID = scope.externalID(for: $0.0)
               return canonicalExternalIDsByResolvedExternalID[
                   ambiguousResolvedExternalID
               ]?.contains(canonicalExternalID) == true
           })?.0 {
            throw OnChainTransactionImportError.ambiguousLegacyMovement(
                hash: movement.hash
            )
        }
        let resolvedExternalIDByCanonicalExternalID = Dictionary(
            resolvedExternalIDPairs,
            uniquingKeysWith: { first, second in
                first == second ? first : second
            }
        )
        let candidateExternalIDs = Set(
            resolvedExternalIDByCanonicalExternalID.values
        )
        let preexistingDurableExternalIDs: Set<String>
        if candidateExternalIDs.isEmpty {
            preexistingDurableExternalIDs = []
        } else {
            let durableReadContext = ModelContext(modelContext.container)
            durableReadContext.autosaveEnabled = false
            preexistingDurableExternalIDs = try durableCanonicalExternalIDLookup(
                durableReadContext,
                Array(candidateExternalIDs),
                asset.id
            ).intersection(candidateExternalIDs)
        }

        let ownedAllocations = Array(asset.allocations ?? [])
        let ownedAllocationHistories = try modelContext
            .fetch(FetchDescriptor<AllocationHistory>())
            .filter { $0.assetId == asset.id }
        var ownedModels: [any PersistentModel] = [asset]
        ownedModels.append(
            contentsOf: durableExistingOnChain.map { $0 as any PersistentModel }
        )
        ownedModels.append(
            contentsOf: ownedAllocations.map { $0 as any PersistentModel }
        )
        ownedModels.append(
            contentsOf: ownedAllocations.compactMap(\.goal).map {
                $0 as any PersistentModel
            }
        )
        ownedModels.append(
            contentsOf: ownedAllocationHistories.map {
                $0 as any PersistentModel
            }
        )

        let previousUndoManager = modelContext.undoManager
        var mutationSnapshot: OnChainImportMutationSnapshot?
        var operationUndoManager: UndoManager?
        defer {
            modelContext.undoManager = previousUndoManager
        }

        func beginMutationIfNeeded() throws {
            guard operationUndoManager == nil else { return }

            try PersistenceOperationTransaction.assertNoUnrelatedPendingChanges(
                in: modelContext,
                allowing: ownedModels
            )
            mutationSnapshot = OnChainImportMutationSnapshot(
                asset: asset,
                existingTransactions: durableExistingOnChain,
                existingHistories: ownedAllocationHistories
            )
            let undoManager = UndoManager()
            operationUndoManager = undoManager
            modelContext.undoManager = undoManager
        }

        func rollbackMutationIfNeeded() {
            guard let operationUndoManager else { return }

            modelContext.processPendingChanges()
            while operationUndoManager.canUndo {
                operationUndoManager.undo()
            }
            modelContext.undoManager = nil
            mutationSnapshot?.restore(in: modelContext)
        }

        func hasLinkedAutoAllocationHistory(
            for transaction: Transaction
        ) -> Bool {
            ownedAllocationHistories.contains {
                $0.sourceTransactionId == transaction.id
            }
        }

        func assertNoLinkedAutoAllocationHistory(
            for transactions: [Transaction]
        ) throws {
            if let linked = transactions.first(where: {
                hasLinkedAutoAllocationHistory(for: $0)
            }) {
                throw OnChainTransactionImportError
                    .ambiguousAutoAllocationHistory(
                        transactionID: linked.id
                    )
            }
        }

        func removeLegacyHashIndex(
            for transaction: Transaction,
            normalizedProviderHashes: Set<String>
        ) {
            for providerHash in normalizedProviderHashes {
                guard var rows = legacyByNormalizedHash[providerHash] else {
                    continue
                }
                rows.removeAll { $0.id == transaction.id }
                if rows.isEmpty {
                    legacyByNormalizedHash.removeValue(forKey: providerHash)
                } else {
                    legacyByNormalizedHash[providerHash] = rows
                }
            }
        }

        func removeProviderRecordIndex(for transaction: Transaction) {
            for providerKey in Array(existingByProviderRecordKey.keys) {
                guard var rows = existingByProviderRecordKey[providerKey] else {
                    continue
                }
                rows.removeAll { $0.id == transaction.id }
                if rows.isEmpty {
                    existingByProviderRecordKey.removeValue(forKey: providerKey)
                } else {
                    existingByProviderRecordKey[providerKey] = rows
                }
            }
            for baseKey in Array(existingByProviderRecordBaseKey.keys) {
                guard var rows = existingByProviderRecordBaseKey[baseKey] else {
                    continue
                }
                rows.removeAll { $0.0.id == transaction.id }
                if rows.isEmpty {
                    existingByProviderRecordBaseKey.removeValue(forKey: baseKey)
                } else {
                    existingByProviderRecordBaseKey[baseKey] = rows
                }
            }
        }

        func reconciledMetadata(
            survivor: Transaction,
            removed: [Transaction],
            providerTransaction: TatumTransaction
        ) throws -> (counterparty: String?, comment: String?) {
            func userComment(_ value: String?) -> String? {
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      trimmed.caseInsensitiveCompare("On-chain") != .orderedSame
                else {
                    return nil
                }
                return trimmed
            }

            func userCounterparty(
                _ value: String?,
                providerCounterparty: String?
            ) -> String? {
                guard let value,
                      !value.trimmingCharacters(
                          in: .whitespacesAndNewlines
                      ).isEmpty
                else {
                    return nil
                }
                if let providerCounterparty,
                   OnChainIdentifierPolicy.addressesEqual(
                       value,
                       providerCounterparty,
                       for: route
                   ) {
                    return nil
                }
                return value
            }

            let rows = [survivor] + removed
            let userCommentRows = rows.compactMap {
                row -> (Transaction, String)? in
                userComment(row.comment).map { (row, $0) }
            }
            if Set(userCommentRows.map(\.1)).count > 1 {
                throw OnChainTransactionImportError.ambiguousLegacyMovement(
                    hash: providerTransaction.hash
                )
            }

            let providerCounterparty =
                providerTransaction.counterAddress
                ?? providerTransaction.from
                ?? providerTransaction.to
            let userCounterpartyRows = rows.compactMap {
                row -> (Transaction, String)? in
                userCounterparty(
                    row.counterparty,
                    providerCounterparty: providerCounterparty
                ).map { (row, $0) }
            }
            if let firstUserCounterparty = userCounterpartyRows.first?.1 {
                for (_, candidate) in userCounterpartyRows.dropFirst() {
                    if !OnChainIdentifierPolicy.addressesEqual(
                        firstUserCounterparty,
                        candidate,
                        for: route
                    ) {
                        throw OnChainTransactionImportError.ambiguousLegacyMovement(
                            hash: providerTransaction.hash
                        )
                    }
                }
            }

            return (
                counterparty: userCounterpartyRows.first?.0.counterparty
                    ?? rows.compactMap(\.counterparty).first
                    ?? providerCounterparty,
                comment: userCommentRows.first?.0.comment
                    ?? rows.compactMap(\.comment).first
            )
        }

        do {
        for (tx, signedAmount) in validMovements {
            let normalizedHash = OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                tx.hash,
                for: route
            )
            let normalizedProviderHashes = scope.normalizedProviderHashes(for: tx)
            let matchingCanonicalExternalIDs = normalizedProviderHashes.reduce(
                into: Set<String>()
            ) { identities, providerHash in
                identities.formUnion(
                    canonicalExternalIDsByProviderHash[providerHash] ?? []
                )
            }
            let currentAssetLegacyRows = Array(Dictionary(
                normalizedProviderHashes
                    .flatMap { legacyByNormalizedHash[$0] ?? [] }
                    .filter { $0.asset?.id == asset.id }
                    .map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values)
            let aliasHashes = normalizedProviderHashes.subtracting([normalizedHash])
            let currentAssetAliasRows = Array(Dictionary(
                aliasHashes
                    .flatMap { legacyByNormalizedHash[$0] ?? [] }
                    .filter { $0.asset?.id == asset.id }
                    .map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values)
            let canonicalExternalID = scope.externalID(for: tx)
            let scopedExternalID =
                resolvedExternalIDByCanonicalExternalID[canonicalExternalID]
                ?? canonicalExternalID
            let legacyCanonicalExternalID = scope.legacyExternalID(for: tx)
            let uniquelyOwnedHashOnlyLegacy: Transaction?
            if canUpgradeHashOnlyLegacy,
               matchingCanonicalExternalIDs.count == 1,
               currentAssetLegacyRows.count == 1 {
                uniquelyOwnedHashOnlyLegacy = currentAssetLegacyRows[0]
            } else {
                if !currentAssetAliasRows.isEmpty {
                    throw OnChainTransactionImportError.ambiguousLegacyMovement(
                        hash: tx.hash
                    )
                }
                uniquelyOwnedHashOnlyLegacy = nil
            }

            let existingProviderRecord = existingByExternalID[scopedExternalID]
                ?? existingByExternalID[canonicalExternalID]
                ?? existingProviderRowByCanonicalExternalID[canonicalExternalID]

            if existingProviderRecord == nil,
               pendingProviderRowByCanonicalExternalID[canonicalExternalID] != nil {
                // Pending scoped rows suppress duplicate publication only. They
                // are neither operation-owned nor durable acceptance evidence.
                continue
            }

            if let collapsePlan =
                    installedDuplicateCollapsePlanByCanonicalExternalID[
                        canonicalExternalID
                    ] {
                let survivor = collapsePlan.survivor
                var removed = collapsePlan.removed
                if let legacy = uniquelyOwnedHashOnlyLegacy,
                   legacy.id != survivor.id,
                   !removed.contains(where: { $0.id == legacy.id }) {
                    removed.append(legacy)
                }
                let metadata = try reconciledMetadata(
                    survivor: survivor,
                    removed: removed,
                    providerTransaction: tx
                )
                try assertNoLinkedAutoAllocationHistory(for: removed)
                let allocationCorrectionPlan =
                    try linkedAutoAllocationCorrectionPlan(
                        for: survivor,
                        correctedAmount: signedAmount,
                        correctedDate: tx.date,
                        asset: asset
                    )

                try beginMutationIfNeeded()
                let survivorExternalID = survivor.externalId
                survivor.amount = signedAmount
                survivor.date = tx.date
                survivor.externalId = scopedExternalID
                survivor.counterparty = metadata.counterparty
                survivor.comment = metadata.comment
                let removedIDs = Set(removed.map(\.id))
                asset.transactions = (asset.transactions ?? []).filter {
                    !removedIDs.contains($0.id)
                }
                for removedTransaction in removed {
                    modelContext.delete(removedTransaction)
                }

                if let survivorExternalID {
                    existingByExternalID.removeValue(forKey: survivorExternalID)
                }
                for removedTransaction in removed {
                    if let removedExternalID = removedTransaction.externalId {
                        existingByExternalID.removeValue(
                            forKey: removedExternalID
                        )
                    }
                    removeProviderRecordIndex(for: removedTransaction)
                    removeLegacyHashIndex(
                        for: removedTransaction,
                        normalizedProviderHashes: normalizedProviderHashes
                    )
                }
                existingByExternalID[scopedExternalID] = survivor
                indexProviderRecord(survivor, from: tx)
                allocationCorrectionPlan?.apply()
                reconciled += 1
                mutatedDurableExternalIDs.insert(scopedExternalID)
                continue
            }

            if let existingCanonical = existingProviderRecord,
               let legacy = uniquelyOwnedHashOnlyLegacy {
                let metadata = try reconciledMetadata(
                    survivor: legacy,
                    removed: [existingCanonical],
                    providerTransaction: tx
                )
                try assertNoLinkedAutoAllocationHistory(
                    for: [existingCanonical]
                )
                let allocationCorrectionPlan =
                    try linkedAutoAllocationCorrectionPlan(
                        for: legacy,
                        correctedAmount: signedAmount,
                        correctedDate: tx.date,
                        asset: asset
                    )
                try beginMutationIfNeeded()
                let legacyExternalID = legacy.externalId
                let existingCanonicalExternalID = existingCanonical.externalId
                legacy.amount = signedAmount
                legacy.date = tx.date
                legacy.externalId = scopedExternalID
                legacy.counterparty = metadata.counterparty
                legacy.comment = metadata.comment

                asset.transactions = (asset.transactions ?? []).filter { $0.id != existingCanonical.id }
                modelContext.delete(existingCanonical)
                if let legacyExternalID {
                    existingByExternalID.removeValue(forKey: legacyExternalID)
                }
                if let existingCanonicalExternalID {
                    existingByExternalID.removeValue(forKey: existingCanonicalExternalID)
                }
                existingByExternalID[scopedExternalID] = legacy
                indexProviderRecord(legacy, from: tx)
                removeLegacyHashIndex(
                    for: legacy,
                    normalizedProviderHashes: normalizedProviderHashes
                )
                allocationCorrectionPlan?.apply()
                reconciled += 1
                mutatedDurableExternalIDs.insert(scopedExternalID)
                continue
            }

            if let existingProviderRecord {
                guard existingProviderRecord.externalId != scopedExternalID
                        || existingProviderRecord.amount != signedAmount
                        || existingProviderRecord.date != tx.date
                else {
                    continue
                }

                let allocationCorrectionPlan =
                    try linkedAutoAllocationCorrectionPlan(
                        for: existingProviderRecord,
                        correctedAmount: signedAmount,
                        correctedDate: tx.date,
                        asset: asset
                    )
                try beginMutationIfNeeded()
                let previousExternalID = existingProviderRecord.externalId
                existingProviderRecord.amount = signedAmount
                existingProviderRecord.date = tx.date
                existingProviderRecord.externalId = scopedExternalID
                if existingProviderRecord.counterparty == nil {
                    existingProviderRecord.counterparty = tx.counterAddress ?? tx.from ?? tx.to
                }
                if let previousExternalID {
                    existingByExternalID.removeValue(forKey: previousExternalID)
                }
                existingByExternalID[scopedExternalID] = existingProviderRecord
                indexProviderRecord(existingProviderRecord, from: tx)
                allocationCorrectionPlan?.apply()
                reconciled += 1
                mutatedDurableExternalIDs.insert(scopedExternalID)
                continue
            }

            if legacyCanonicalExternalID != scopedExternalID,
               let oldCanonical = existingByExternalID[legacyCanonicalExternalID] {
                let existingCanonical = existingByExternalID[scopedExternalID]
                    .flatMap { $0.id == oldCanonical.id ? nil : $0 }
                let collapsedMetadata: (counterparty: String?, comment: String?)?
                if let existingCanonical {
                    collapsedMetadata = try reconciledMetadata(
                        survivor: oldCanonical,
                        removed: [existingCanonical],
                        providerTransaction: tx
                    )
                } else {
                    collapsedMetadata = nil
                }
                if let existingCanonical {
                    try assertNoLinkedAutoAllocationHistory(
                        for: [existingCanonical]
                    )
                }
                let oldCanonicalHadLinkedHistory =
                    hasLinkedAutoAllocationHistory(for: oldCanonical)
                let allocationCorrectionPlan =
                    try linkedAutoAllocationCorrectionPlan(
                        for: oldCanonical,
                        correctedAmount: signedAmount,
                        correctedDate: tx.date,
                        asset: asset
                    )

                try beginMutationIfNeeded()
                if let existingCanonical, let collapsedMetadata {
                    oldCanonical.amount = signedAmount
                    oldCanonical.date = tx.date
                    oldCanonical.externalId = scopedExternalID
                    oldCanonical.counterparty = collapsedMetadata.counterparty
                    oldCanonical.comment = collapsedMetadata.comment
                    asset.transactions = (asset.transactions ?? []).filter {
                        $0.id != existingCanonical.id
                    }
                    modelContext.delete(existingCanonical)
                } else {
                    oldCanonical.amount = signedAmount
                    oldCanonical.date = tx.date
                    oldCanonical.externalId = scopedExternalID
                    if oldCanonical.counterparty == nil {
                        oldCanonical.counterparty = tx.counterAddress ?? tx.from ?? tx.to
                    }
                    // This row was quarantined under the old case-folded
                    // namespace. A unique canonical refresh proves it is safe
                    // for auto-allocation and execution contribution.
                    if !oldCanonicalHadLinkedHistory {
                        insertedModels.append(oldCanonical)
                    }
                }

                existingByExternalID.removeValue(forKey: legacyCanonicalExternalID)
                existingByExternalID[scopedExternalID] = oldCanonical
                indexProviderRecord(oldCanonical, from: tx)
                allocationCorrectionPlan?.apply()
                reconciled += 1
                mutatedDurableExternalIDs.insert(scopedExternalID)
                continue
            }

            if existingByExternalID[scopedExternalID] != nil { continue }

            // A freshly returned, asset-filtered canonical transaction proves
            // that a legacy hash-only row belongs to this tracking scope. It
            // is safe to migrate/update that exact hash only when both the
            // canonical movement and the legacy row are unambiguous. Unmatched
            // or multi-movement legacy history remains untouched because a
            // limited page cannot disprove or assign it safely.
            if let legacy = uniquelyOwnedHashOnlyLegacy {
                let legacyHadLinkedHistory =
                    hasLinkedAutoAllocationHistory(for: legacy)
                let allocationCorrectionPlan =
                    try linkedAutoAllocationCorrectionPlan(
                        for: legacy,
                        correctedAmount: signedAmount,
                        correctedDate: tx.date,
                        asset: asset
                    )
                try beginMutationIfNeeded()
                let legacyExternalID = legacy.externalId
                legacy.amount = signedAmount
                legacy.date = tx.date
                legacy.externalId = scopedExternalID
                if legacy.counterparty == nil {
                    legacy.counterparty = tx.counterAddress ?? tx.from ?? tx.to
                }
                if let legacyExternalID {
                    existingByExternalID.removeValue(forKey: legacyExternalID)
                }
                existingByExternalID[scopedExternalID] = legacy
                indexProviderRecord(legacy, from: tx)
                removeLegacyHashIndex(
                    for: legacy,
                    normalizedProviderHashes: normalizedProviderHashes
                )
                if !legacyHadLinkedHistory {
                    insertedModels.append(legacy)
                }
                allocationCorrectionPlan?.apply()
                reconciled += 1
                mutatedDurableExternalIDs.insert(scopedExternalID)
                continue
            }

            try beginMutationIfNeeded()
            let counterparty = tx.counterAddress ?? tx.from ?? tx.to
            let newTransaction = Transaction(
                amount: signedAmount,
                asset: asset,
                date: tx.date,
                source: .onChain,
                externalId: scopedExternalID,
                counterparty: counterparty,
                comment: "On-chain"
            )

            modelContext.insert(newTransaction)

            // Ensure relationship collections update immediately.
            if !(asset.transactions ?? []).contains(where: { $0.id == newTransaction.id }) {
                asset.transactions = (asset.transactions ?? []) + [newTransaction]
            }

            insertedModels.append(newTransaction)
            existingByExternalID[scopedExternalID] = newTransaction
            indexProviderRecord(newTransaction, from: tx)
            inserted += 1
            mutatedDurableExternalIDs.insert(scopedExternalID)
        }

        if inserted > 0 || reconciled > 0 {
            _ = try applyDedicatedAutoAllocationIfNeeded(
                for: asset,
                insertedTransactions: insertedModels
            )
        }

        if inserted > 0 || reconciled > 0 {
                try saveChanges()
        }
        } catch {
            rollbackMutationIfNeeded()
            throw error
        }

        var durableExternalIDs = preexistingDurableExternalIDs
        if inserted > 0 || reconciled > 0 {
            durableExternalIDs.formUnion(mutatedDurableExternalIDs)
        }
        let acceptedTransactions = validMovements.compactMap { movement, _ in
            let canonicalExternalID = scope.externalID(for: movement)
            let resolvedExternalID =
                resolvedExternalIDByCanonicalExternalID[canonicalExternalID]
                ?? canonicalExternalID
            return durableExternalIDs.contains(resolvedExternalID)
                ? movement
                : nil
        }

        return OnChainTransactionImportResult(
            acceptedTransactions: acceptedTransactions,
            mutationCount: inserted + reconciled
        )
    }

    private func linkedAutoAllocationCorrectionPlan(
        for existingTransaction: Transaction,
        correctedAmount: Double,
        correctedDate: Date,
        asset: Asset
    ) throws -> LinkedAutoAllocationCorrectionPlan? {
        let epsilon = 0.0000001
        guard existingTransaction.amount != correctedAmount
                || existingTransaction.date != correctedDate
        else {
            return nil
        }

        let assetHistories = try modelContext
            .fetch(FetchDescriptor<AllocationHistory>())
            .filter { $0.assetId == asset.id }
        let linkedToCorrectedTransaction = assetHistories.filter {
            $0.sourceTransactionId == existingTransaction.id
        }

        guard !linkedToCorrectedTransaction.isEmpty else {
            // A transaction refresh can arrive before its balance refresh.
            // Therefore a volatile cached balance cannot prove that a
            // same-time legacy history is independent. Any unlinked history
            // for a current allocation target makes the correction ambiguous.
            let allocationGoalIDs = Set(
                (asset.allocations ?? []).compactMap { $0.goal?.id }
            )
            if assetHistories.contains(where: {
                $0.sourceTransactionId == nil
                    && $0.timestamp == existingTransaction.date
                    && $0.goalId.map(allocationGoalIDs.contains) == true
            }) {
                throw OnChainTransactionImportError
                    .ambiguousAutoAllocationHistory(
                        transactionID: existingTransaction.id
                    )
            }
            return nil
        }

        guard linkedToCorrectedTransaction.count == 1,
              let linkedHistory = linkedToCorrectedTransaction.first,
              (asset.allocations ?? []).count == 1,
              let allocation = asset.allocations?.first,
              let goal = allocation.goal,
              linkedHistory.goalId == goal.id,
              linkedHistory.timestamp == existingTransaction.date
        else {
            throw OnChainTransactionImportError
                .ambiguousAutoAllocationHistory(
                    transactionID: existingTransaction.id
                )
        }

        let histories = assetHistories.filter { $0.goalId == goal.id }
        let linkedTransactionIDs = Set(
            histories.compactMap(\.sourceTransactionId)
        )
        let transactionsByID = Dictionary(
            uniqueKeysWithValues: (asset.transactions ?? []).map { ($0.id, $0) }
        )
        guard linkedTransactionIDs.allSatisfy({
            transactionsByID[$0] != nil
        }) else {
            throw OnChainTransactionImportError
                .ambiguousAutoAllocationHistory(
                    transactionID: existingTransaction.id
                )
        }

        func ordersBefore(
            _ lhs: AllocationHistory,
            _ rhs: AllocationHistory,
            correctedTimestamp: Date? = nil
        ) -> Bool {
            let lhsTimestamp = lhs.id == linkedHistory.id
                ? (correctedTimestamp ?? lhs.timestamp)
                : lhs.timestamp
            let rhsTimestamp = rhs.id == linkedHistory.id
                ? (correctedTimestamp ?? rhs.timestamp)
                : rhs.timestamp
            if lhsTimestamp != rhsTimestamp {
                return lhsTimestamp < rhsTimestamp
            }
            if lhs.effectiveCreatedAt != rhs.effectiveCreatedAt {
                return lhs.effectiveCreatedAt < rhs.effectiveCreatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let oldOrdered = histories.sorted {
            ordersBefore($0, $1)
        }
        var oldRunningTarget: Double?
        var initialLinkedBaseline: Double?
        for history in oldOrdered {
            if let transactionID = history.sourceTransactionId {
                guard let transaction = transactionsByID[transactionID] else {
                    throw OnChainTransactionImportError
                        .ambiguousAutoAllocationHistory(
                            transactionID: existingTransaction.id
                        )
                }
                if oldRunningTarget == nil {
                    let baseline: Double
                    if let persistedBaseline = history.sourcePreviousAmount {
                        baseline = persistedBaseline
                    } else {
                        guard !(history.amount <= epsilon
                                && transaction.amount < 0) else {
                            throw OnChainTransactionImportError
                                .ambiguousAutoAllocationHistory(
                                    transactionID: existingTransaction.id
                                )
                        }
                        baseline = history.amount - transaction.amount
                    }
                    guard baseline.isFinite, baseline >= -epsilon else {
                        throw OnChainTransactionImportError
                            .ambiguousAutoAllocationHistory(
                                transactionID: existingTransaction.id
                            )
                    }
                    let normalizedBaseline = max(0, baseline)
                    initialLinkedBaseline = normalizedBaseline
                    oldRunningTarget = normalizedBaseline
                } else if let persistedBaseline = history.sourcePreviousAmount {
                    let baselineTolerance = max(
                        epsilon,
                        max(
                            abs(persistedBaseline),
                            abs(oldRunningTarget ?? 0)
                        ) * 0.000001
                    )
                    guard persistedBaseline.isFinite,
                          abs(persistedBaseline - (oldRunningTarget ?? 0))
                            <= baselineTolerance
                    else {
                        throw OnChainTransactionImportError
                            .ambiguousAutoAllocationHistory(
                                transactionID: existingTransaction.id
                            )
                    }
                }
                let expected = max(
                    0,
                    (oldRunningTarget ?? 0) + transaction.amount
                )
                let tolerance = max(
                    epsilon,
                    max(abs(expected), abs(history.amount)) * 0.000001
                )
                guard expected.isFinite,
                      abs(expected - history.amount) <= tolerance
                else {
                    throw OnChainTransactionImportError
                        .ambiguousAutoAllocationHistory(
                            transactionID: existingTransaction.id
                        )
                }
                oldRunningTarget = expected
            } else {
                oldRunningTarget = max(0, history.amount)
            }
        }

        guard let oldFinalTarget = oldRunningTarget else {
            throw OnChainTransactionImportError
                .ambiguousAutoAllocationHistory(
                    transactionID: existingTransaction.id
                )
        }
        let oldTargetTolerance = max(
            epsilon,
            max(abs(oldFinalTarget), abs(allocation.amountValue)) * 0.000001
        )
        guard abs(oldFinalTarget - allocation.amountValue)
                <= oldTargetTolerance
        else {
            throw OnChainTransactionImportError
                .ambiguousAutoAllocationHistory(
                    transactionID: existingTransaction.id
                )
        }

        if linkedHistory.timestamp != correctedDate {
            let lower = min(linkedHistory.timestamp, correctedDate)
            let upper = max(linkedHistory.timestamp, correctedDate)
            let crossesManualHistory = histories.contains {
                $0.sourceTransactionId == nil
                    && $0.timestamp >= lower
                    && $0.timestamp <= upper
            }
            guard !crossesManualHistory else {
                throw OnChainTransactionImportError
                    .ambiguousAutoAllocationHistory(
                        transactionID: existingTransaction.id
                    )
            }
        }

        let correctedOrdered = histories.sorted {
            ordersBefore($0, $1, correctedTimestamp: correctedDate)
        }
        var correctedRunningTarget: Double?
        var updates: [LinkedAutoAllocationHistoryUpdate] = []
        updates.reserveCapacity(linkedTransactionIDs.count)

        for history in correctedOrdered {
            guard let transactionID = history.sourceTransactionId else {
                correctedRunningTarget = max(0, history.amount)
                continue
            }
            guard let transaction = transactionsByID[transactionID] else {
                throw OnChainTransactionImportError
                    .ambiguousAutoAllocationHistory(
                        transactionID: existingTransaction.id
                    )
            }
            if correctedRunningTarget == nil {
                guard let initialLinkedBaseline else {
                    throw OnChainTransactionImportError
                        .ambiguousAutoAllocationHistory(
                            transactionID: existingTransaction.id
                        )
                }
                correctedRunningTarget = initialLinkedBaseline
            }
            let amount = transactionID == existingTransaction.id
                ? correctedAmount
                : transaction.amount
            let nextTarget = max(
                0,
                (correctedRunningTarget ?? 0) + amount
            )
            guard nextTarget.isFinite else {
                throw OnChainTransactionImportError
                    .ambiguousAutoAllocationHistory(
                        transactionID: existingTransaction.id
                    )
            }
            let timestamp = history.id == linkedHistory.id
                ? correctedDate
                : history.timestamp
            updates.append(
                LinkedAutoAllocationHistoryUpdate(
                    history: history,
                    amount: nextTarget,
                    timestamp: timestamp,
                    sourcePreviousAmount: correctedRunningTarget ?? 0
                )
            )
            correctedRunningTarget = nextTarget
        }

        guard let finalTarget = correctedRunningTarget else {
            throw OnChainTransactionImportError
                .ambiguousAutoAllocationHistory(
                    transactionID: existingTransaction.id
                )
        }
        if correctedOrdered.last?.sourceTransactionId != nil {
            let currentBalance = asset.currentAmount
            let tolerance = max(
                epsilon,
                max(abs(currentBalance), abs(finalTarget)) * 0.000001
            )
            guard currentBalance.isFinite,
                  abs(currentBalance - finalTarget) <= tolerance
            else {
                throw OnChainTransactionImportError
                    .ambiguousAutoAllocationHistory(
                        transactionID: existingTransaction.id
                    )
            }
        }

        return LinkedAutoAllocationCorrectionPlan(
            allocation: allocation,
            updates: updates,
            finalAllocationAmount: finalTarget
        )
    }

    private func reconcileIncomingIndexEnrichment(
        _ movements: [(TatumTransaction, Double)],
        scope: OnChainImportScope
    ) throws -> [(TatumTransaction, Double)] {
        let indexedMovements = movements.enumerated().map {
            (
                offset: $0.offset,
                transaction: $0.element.0,
                signedAmount: $0.element.1
            )
        }
        let groupedByProviderBase = Dictionary(
            grouping: indexedMovements,
            by: { scope.canonicalProviderRecordBaseKey(for: $0.transaction) }
        )
        var discardedOffsets = Set<Int>()

        for group in groupedByProviderBase.values {
            var representativeByEventIndex: [
                ProviderEventIndex: (
                    offset: Int,
                    transaction: TatumTransaction,
                    signedAmount: Double
                )
            ] = [:]

            for movement in group {
                let eventIndex = ProviderEventIndex(transaction: movement.transaction)
                if let existing = representativeByEventIndex[eventIndex] {
                    guard existing.transaction.isCanonicalProviderEquivalent(
                        to: movement.transaction
                    ) else {
                        throw OnChainTransactionImportError.ambiguousLegacyMovement(
                            hash: movement.transaction.hash
                        )
                    }
                    discardedOffsets.insert(movement.offset)
                } else {
                    representativeByEventIndex[eventIndex] = movement
                }
            }

            let representatives = Array(representativeByEventIndex.values)
            for firstIndex in representatives.indices {
                for secondIndex in representatives.indices
                where secondIndex > firstIndex {
                    let first = representatives[firstIndex]
                    let second = representatives[secondIndex]
                    let firstEventIndex = ProviderEventIndex(
                        transaction: first.transaction
                    )
                    let secondEventIndex = ProviderEventIndex(
                        transaction: second.transaction
                    )
                    guard !firstEventIndex.conflicts(with: secondEventIndex),
                          !firstEventIndex.isSubset(of: secondEventIndex),
                          !secondEventIndex.isSubset(of: firstEventIndex)
                    else {
                        continue
                    }

                    // A transaction-index-only row and a log-index-only row
                    // could be two events or two incomplete views of one event.
                    // Only a unique complete provider row can prove the join.
                    let commonSupersets = representatives.filter { candidate in
                        let candidateIndex = ProviderEventIndex(
                            transaction: candidate.transaction
                        )
                        return firstEventIndex.isSubset(of: candidateIndex)
                            && secondEventIndex.isSubset(of: candidateIndex)
                    }
                    guard commonSupersets.count == 1 else {
                        throw OnChainTransactionImportError.ambiguousLegacyMovement(
                            hash: first.transaction.hash
                        )
                    }
                }
            }

            for movement in representatives {
                let eventIndex = ProviderEventIndex(transaction: movement.transaction)
                let strictSupersets = representatives.filter {
                    eventIndex.isStrictSubset(
                        of: ProviderEventIndex(transaction: $0.transaction)
                    )
                }
                guard !strictSupersets.isEmpty else { continue }

                let maximalSupersets = strictSupersets.filter { candidate in
                    let candidateIndex = ProviderEventIndex(
                        transaction: candidate.transaction
                    )
                    return !strictSupersets.contains { other in
                        candidate.offset != other.offset
                            && candidateIndex.isStrictSubset(
                                of: ProviderEventIndex(transaction: other.transaction)
                            )
                    }
                }
                guard maximalSupersets.count == 1,
                      let enriched = maximalSupersets.first,
                      movement.transaction
                        .isCanonicalProviderEquivalentIgnoringEventIndexes(
                            to: enriched.transaction
                        )
                else {
                    throw OnChainTransactionImportError.ambiguousLegacyMovement(
                        hash: movement.transaction.hash
                    )
                }
                discardedOffsets.insert(movement.offset)
            }
        }

        return movements.enumerated().compactMap { offset, movement in
            discardedOffsets.contains(offset) ? nil : movement
        }
    }

    /// Implements the redesign rule for on-chain arrivals:
    /// if an asset is fully allocated to exactly one goal, new deposits should keep it fully allocated.
    /// For partially allocated or shared assets, deposits remain unallocated.
    private func applyDedicatedAutoAllocationIfNeeded(
        for asset: Asset,
        insertedTransactions: [Transaction]
    ) throws -> [AllocationHistory] {
        let epsilon = 0.0000001
        guard (asset.allocations ?? []).count == 1,
              let allocation = (asset.allocations ?? []).first,
              let goal = allocation.goal
        else { return [] }

        let latestExistingHistoryDate = try modelContext
            .fetch(FetchDescriptor<AllocationHistory>())
            .filter {
                $0.assetId == asset.id
                    && $0.goalId == goal.id
            }
            .map(\.timestamp)
            .max()
        let deposits = insertedTransactions
            .filter {
                guard $0.amount > epsilon else { return false }
                guard let latestExistingHistoryDate else { return true }
                // A later absolute/manual history already captures the user's
                // allocation intent after this provider event. Auto-allocating
                // a delayed or same-time backfill from the terminal target
                // would rewrite history out of chronological order.
                return $0.date > latestExistingHistoryDate
            }
            .sorted(by: { $0.date < $1.date })
        guard !deposits.isEmpty else { return [] }

        // Only auto-allocate when the newly observed "unallocated" portion matches the new deposits.
        // This avoids guessing for intentionally partially allocated assets.
        let unallocatedNow = max(0, asset.currentAmount - allocation.amountValue)
        let depositsSum = deposits.reduce(0.0) { $0 + $1.amount }
        let tolerance = max(epsilon, max(unallocatedNow, depositsSum) * 0.000001)
        guard abs(unallocatedNow - depositsSum) <= tolerance else { return [] }

        var runningTarget = allocation.amountValue
        var insertedHistories: [AllocationHistory] = []
        insertedHistories.reserveCapacity(deposits.count)
        for deposit in deposits {
            let previousAmount = runningTarget
            runningTarget += deposit.amount
            allocation.updateAmount(runningTarget)
            let history = AllocationHistory(
                asset: asset,
                goal: goal,
                amount: runningTarget,
                timestamp: deposit.date,
                sourceTransactionId: deposit.id,
                sourcePreviousAmount: previousAmount
            )
            modelContext.insert(history)
            insertedHistories.append(history)
        }
        return insertedHistories
    }
}

private struct OnChainImportMutationSnapshot {
    private struct TransactionState {
        let transaction: Transaction
        let amount: Double
        let date: Date
        let sourceRawValue: String
        let externalID: String?
        let counterparty: String?
        let comment: String?
        let asset: Asset?

        init(transaction: Transaction) {
            self.transaction = transaction
            self.amount = transaction.amount
            self.date = transaction.date
            self.sourceRawValue = transaction.sourceRawValue
            self.externalID = transaction.externalId
            self.counterparty = transaction.counterparty
            self.comment = transaction.comment
            self.asset = transaction.asset
        }

        func restoreScalars() {
            transaction.amount = amount
            transaction.date = date
            transaction.sourceRawValue = sourceRawValue
            transaction.externalId = externalID
            transaction.counterparty = counterparty
            transaction.comment = comment
        }
    }

    private struct AllocationState {
        let allocation: AssetAllocation
        let amount: Double
        let lastModifiedDate: Date

        init(allocation: AssetAllocation) {
            self.allocation = allocation
            self.amount = allocation.amount
            self.lastModifiedDate = allocation.lastModifiedDate
        }

        func restore() {
            allocation.amount = amount
            allocation.lastModifiedDate = lastModifiedDate
        }
    }

    private struct AllocationHistoryState {
        let history: AllocationHistory
        let amount: Double
        let timestamp: Date
        let createdAt: Date
        let monthLabel: String
        let assetId: UUID?
        let goalId: UUID?
        let sourceTransactionId: UUID?
        let sourcePreviousAmount: Double?
        let asset: Asset?
        let goal: Goal?

        init(history: AllocationHistory) {
            self.history = history
            self.amount = history.amount
            self.timestamp = history.timestamp
            self.createdAt = history.createdAt
            self.monthLabel = history.monthLabel
            self.assetId = history.assetId
            self.goalId = history.goalId
            self.sourceTransactionId = history.sourceTransactionId
            self.sourcePreviousAmount = history.sourcePreviousAmount
            self.asset = history.asset
            self.goal = history.goal
        }

        func restore() {
            history.amount = amount
            history.timestamp = timestamp
            history.createdAt = createdAt
            history.monthLabel = monthLabel
            history.assetId = assetId
            history.goalId = goalId
            history.sourceTransactionId = sourceTransactionId
            history.sourcePreviousAmount = sourcePreviousAmount
            history.asset = asset
            history.goal = goal
        }
    }

    private struct GoalHistoryRelationship {
        let goal: Goal
        let allocationHistory: [AllocationHistory]?
    }

    private let asset: Asset
    private let assetTransactions: [Transaction]?
    private let assetAllocationHistory: [AllocationHistory]?
    private let transactionStates: [TransactionState]
    private let allocationStates: [AllocationState]
    private let allocationHistoryStates: [AllocationHistoryState]
    private let goalHistoryRelationships: [GoalHistoryRelationship]

    init(
        asset: Asset,
        existingTransactions: [Transaction],
        existingHistories: [AllocationHistory]
    ) {
        self.asset = asset
        self.assetTransactions = asset.transactions
        self.assetAllocationHistory = asset.allocationHistory
        self.transactionStates = existingTransactions.map(TransactionState.init)
        self.allocationStates = (asset.allocations ?? []).map(AllocationState.init)
        self.allocationHistoryStates = existingHistories.map(
            AllocationHistoryState.init
        )

        var seenGoalIDs: Set<UUID> = []
        self.goalHistoryRelationships = (asset.allocations ?? []).compactMap { allocation in
            guard let goal = allocation.goal, seenGoalIDs.insert(goal.id).inserted else {
                return nil
            }
            return GoalHistoryRelationship(goal: goal, allocationHistory: goal.allocationHistory)
        }
    }

    func restore(in modelContext: ModelContext) {
        for state in transactionStates {
            state.restoreScalars()
            state.transaction.asset = state.asset
        }
        for state in allocationStates {
            state.restore()
        }
        for state in allocationHistoryStates {
            state.restore()
        }

        // Reassert only relationships touched by this import. Other pending
        // changes in the shared context remain intact.
        asset.transactions = assetTransactions
        asset.allocationHistory = assetAllocationHistory
        for relationship in goalHistoryRelationships {
            relationship.goal.allocationHistory = relationship.allocationHistory
        }
        modelContext.processPendingChanges()
    }
}

private struct InstalledProviderRecordDescriptor {
    let keys: Set<String>
    let baseKeys: Set<String>
    let eventIndex: ProviderEventIndex
    let canonicalProviderHash: String
    let providerHashAliases: Set<String>
    let hasDurableAliasMetadata: Bool
    let providerHashProvenance: TatumProviderHashProvenance?
}

private struct InstalledProviderDuplicateCollapsePlan {
    let survivor: Transaction
    let removed: [Transaction]
}

private struct IncomingProviderRecordDescriptor: Hashable {
    let externalID: String
    let eventIndex: ProviderEventIndex
}

private struct ProviderEventIndex: Hashable {
    let transactionIndex: Int?
    let logIndex: Int?

    init(transactionIndex: Int?, logIndex: Int?) {
        self.transactionIndex = transactionIndex
        self.logIndex = logIndex
    }

    init(transaction: TatumTransaction) {
        self.init(
            transactionIndex: transaction.transactionIndex,
            logIndex: transaction.logIndex
        )
    }

    func isSubset(of other: ProviderEventIndex) -> Bool {
        if let transactionIndex, other.transactionIndex != transactionIndex {
            return false
        }
        if let logIndex, other.logIndex != logIndex {
            return false
        }
        return true
    }

    func isStrictSubset(of other: ProviderEventIndex) -> Bool {
        self != other && isSubset(of: other)
    }

    func conflicts(with other: ProviderEventIndex) -> Bool {
        if let transactionIndex,
           let otherTransactionIndex = other.transactionIndex,
           transactionIndex != otherTransactionIndex {
            return true
        }
        if let logIndex,
           let otherLogIndex = other.logIndex,
           logIndex != otherLogIndex {
            return true
        }
        return false
    }

    var hasValidSemanticIndexes: Bool {
        (transactionIndex.map { $0 >= 0 } ?? true)
            && (logIndex.map { $0 >= 0 } ?? true)
    }
}

private struct OnChainImportScope {
    private static let providerAliasMarkerV1 = "aliases_v1"
    private static let providerIdentityMarkerV2 = "identity_v2"

    private let value: String
    private let legacyValue: String
    private let route: BalanceRoute
    private let chainId: String
    private let address: String
    private let currency: String
    private let assetID: UUID

    init(asset: Asset, chainId: String, address: String, route: BalanceRoute) {
        self.route = route
        self.chainId = chainId
        self.address = address
        self.currency = asset.currency
        self.assetID = asset.id
        value = [
            OnChainIdentifierPolicy.canonicalNamespace(for: route),
            chainId.lowercased(),
            OnChainIdentifierPolicy.normalizedAddress(address, for: route),
            asset.currency.lowercased(),
            asset.id.uuidString.lowercased()
        ].joined(separator: "|")
        legacyValue = [
            "onchain_v3",
            chainId.lowercased(),
            address.lowercased(),
            asset.currency.lowercased(),
            asset.id.uuidString.lowercased()
        ].joined(separator: "|")
    }

    func externalID(for transaction: TatumTransaction) -> String {
        externalID(
            for: transaction,
            canonicalProviderHash: OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                transaction.hash,
                for: route
            ),
            providerHashAliases: transaction.normalizedProviderHashes(for: route)
                .subtracting([
                    OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                        transaction.hash,
                        for: route
                    )
                ]),
            providerHashProvenance: transaction.providerHashProvenance
        )
    }

    func reconciledExternalID(
        for transaction: TatumTransaction,
        existingExternalID: String?
    ) throws -> String {
        guard let existingExternalID,
              let installed = providerRecordDescriptor(
                  fromCanonicalExternalID: existingExternalID
              )
        else {
            return externalID(for: transaction)
        }
        guard installed.eventIndex.hasValidSemanticIndexes else {
            return externalID(for: transaction)
        }
        guard isUTXO else {
            return externalID(for: transaction)
        }

        let incomingCanonicalHash =
            OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                transaction.hash,
                for: route
            )
        let incomingProviderHashes = transaction.normalizedProviderHashes(for: route)
        let installedProviderHashes = installed.providerHashAliases.union([
            installed.canonicalProviderHash
        ])
        let installedKnowsIncomingCanonical = installedProviderHashes.contains(
            incomingCanonicalHash
        )
        let incomingKnowsInstalledCanonical = incomingProviderHashes.contains(
            installed.canonicalProviderHash
        )
        if installed.canonicalProviderHash != incomingCanonicalHash,
           installed.providerHashProvenance == .explicitTxid,
           transaction.providerHashProvenance == .explicitTxid {
            throw OnChainTransactionImportError.ambiguousLegacyMovement(
                hash: transaction.hash
            )
        }
        if installed.canonicalProviderHash != incomingCanonicalHash,
           !installedKnowsIncomingCanonical,
           !incomingKnowsInstalledCanonical {
            throw OnChainTransactionImportError.ambiguousLegacyMovement(
                hash: transaction.hash
            )
        }

        let canonicalProviderHash: String
        if installed.canonicalProviderHash == incomingCanonicalHash {
            canonicalProviderHash = installed.canonicalProviderHash
        } else if installed.providerHashProvenance == .explicitTxid {
            canonicalProviderHash = installed.canonicalProviderHash
        } else if transaction.providerHashProvenance == .explicitTxid {
            canonicalProviderHash = incomingCanonicalHash
        } else if installed.hasDurableAliasMetadata,
           installedKnowsIncomingCanonical,
           !incomingKnowsInstalledCanonical {
            // A later weak response may expose only a witness hash. Keep the
            // stronger durable identity instead of downgrading it.
            canonicalProviderHash = installed.canonicalProviderHash
        } else if incomingKnowsInstalledCanonical,
                  !installedKnowsIncomingCanonical {
            // The provider has enriched a previously weak identity with a
            // canonical txid that points back to the installed hash.
            canonicalProviderHash = incomingCanonicalHash
        } else if installed.hasDurableAliasMetadata {
            // Both views already know one another. Stability wins so page
            // ordering cannot flip the durable primary identifier.
            canonicalProviderHash = installed.canonicalProviderHash
        } else {
            canonicalProviderHash = incomingCanonicalHash
        }

        let aliases = installedProviderHashes
            .union(incomingProviderHashes)
            .subtracting([canonicalProviderHash])
        let providerHashProvenance: TatumProviderHashProvenance?
        if installed.canonicalProviderHash == incomingCanonicalHash {
            if installed.providerHashProvenance == .explicitTxid
                || transaction.providerHashProvenance == .explicitTxid {
                providerHashProvenance = .explicitTxid
            } else if installed.providerHashProvenance == .fallbackIdentifier
                        || transaction.providerHashProvenance == .fallbackIdentifier {
                providerHashProvenance = .fallbackIdentifier
            } else {
                providerHashProvenance = nil
            }
        } else if canonicalProviderHash == installed.canonicalProviderHash {
            providerHashProvenance = installed.providerHashProvenance
        } else {
            providerHashProvenance = transaction.providerHashProvenance
        }
        return externalID(
            for: transaction,
            canonicalProviderHash: canonicalProviderHash,
            providerHashAliases: aliases,
            providerHashProvenance: providerHashProvenance
        )
    }

    func legacyExternalID(for transaction: TatumTransaction) -> String {
        "\(legacyValue)|\(transaction.legacyCaseFoldedMovementIdentity)"
    }

    func providerRecordKeys(for transaction: TatumTransaction) -> Set<String> {
        var keys = Set(
            transaction.providerRecordIdentities(for: route).map {
                canonicalProviderRecordKey($0)
            }
        )
        keys.formUnion(
            transaction.legacyCaseFoldedProviderRecordIdentities(for: route).map {
                legacyProviderRecordKey($0)
            }
        )
        return keys
    }

    func providerRecordBaseKeys(for transaction: TatumTransaction) -> Set<String> {
        var keys = Set(
            transaction.providerRecordIdentities(for: route).map {
                canonicalProviderRecordBaseKey(
                    providerRecordBaseIdentity($0)
                )
            }
        )
        keys.formUnion(
            transaction.legacyCaseFoldedProviderRecordIdentities(for: route).map {
                legacyProviderRecordBaseKey(
                    providerRecordBaseIdentity($0)
                )
            }
        )
        return keys
    }

    func canonicalProviderRecordBaseKey(for transaction: TatumTransaction) -> String {
        canonicalProviderRecordBaseKey(
            providerRecordBaseIdentity(
                transaction.providerRecordIdentity(for: route)
            )
        )
    }

    func normalizedProviderHashes(for transaction: TatumTransaction) -> Set<String> {
        transaction.normalizedProviderHashes(for: route)
    }

    var isUTXO: Bool {
        if case .utxo = route {
            return true
        }
        return false
    }

    func canPreserveStableNonUTXOExternalID(
        _ existingExternalID: String,
        for transaction: TatumTransaction
    ) -> Bool {
        guard !isUTXO,
              let installed = providerRecordDescriptor(
                  fromCanonicalExternalID: existingExternalID
              ),
              installed.eventIndex.hasValidSemanticIndexes,
              installed.eventIndex == ProviderEventIndex(transaction: transaction)
        else {
            return false
        }
        guard installed.canonicalProviderHash
                == OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                transaction.hash,
                for: route
                )
        else {
            return false
        }
        let exactLegacyExternalIDs: Set<String> = [
            "\(value)|\(transaction.movementIdentity(for: route))",
            legacyExternalID(for: transaction)
        ]
        return exactLegacyExternalIDs.contains(existingExternalID)
    }

    func providerRecordKeys(fromCanonicalExternalID externalID: String) -> Set<String> {
        providerRecordDescriptor(fromCanonicalExternalID: externalID)?.keys ?? []
    }

    func providerRecordDescriptor(
        fromCanonicalExternalID externalID: String
    ) -> InstalledProviderRecordDescriptor? {
        let components = externalID.split(
            separator: "|",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard components.count >= 12,
              components[0].hasPrefix("onchain_"),
              components[1].caseInsensitiveCompare(chainId) == .orderedSame,
              components[3].caseInsensitiveCompare(currency) == .orderedSame,
              components[4].caseInsensitiveCompare(assetID.uuidString) == .orderedSame
        else {
            return nil
        }

        let providerComponents: [String]
        let providerHashAliases: Set<String>
        let hasDurableAliasMetadata: Bool
        let providerHashProvenance: TatumProviderHashProvenance?
        if components[5] == "record_v1" {
            let identityMarkerIndex = [12, 13].first {
                components.indices.contains($0)
                    && (
                        components[$0] == Self.providerAliasMarkerV1
                            || components[$0] == Self.providerIdentityMarkerV2
                    )
            }
            if let identityMarkerIndex {
                providerComponents = Array(components[6..<identityMarkerIndex])
                guard isUTXO,
                      providerComponents.count == 6 || providerComponents.count == 7
                else {
                    return nil
                }
                let rawAliases: [String]
                if components[identityMarkerIndex] == Self.providerAliasMarkerV1 {
                    guard components.indices.contains(identityMarkerIndex + 1),
                          let aliasCount = Int(components[identityMarkerIndex + 1]),
                          aliasCount > 0,
                          components.count == identityMarkerIndex + 2 + aliasCount
                    else {
                        return nil
                    }
                    rawAliases = Array(components.dropFirst(identityMarkerIndex + 2))
                    providerHashProvenance = nil
                } else {
                    guard components.indices.contains(identityMarkerIndex + 2),
                          let aliasCount = Int(components[identityMarkerIndex + 2]),
                          aliasCount >= 0,
                          components.count == identityMarkerIndex + 3 + aliasCount
                    else {
                        return nil
                    }
                    switch components[identityMarkerIndex + 1] {
                    case "explicit_txid":
                        providerHashProvenance = .explicitTxid
                    case "fallback":
                        providerHashProvenance = .fallbackIdentifier
                    case "unknown":
                        providerHashProvenance = nil
                    default:
                        return nil
                    }
                    rawAliases = Array(components.dropFirst(identityMarkerIndex + 3))
                }
                guard rawAliases.allSatisfy(ProviderIdentifierGrammar.isCanonical)
                else {
                    return nil
                }
                providerHashAliases = Set(
                    rawAliases.map {
                        OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                            $0,
                            for: route
                        )
                    }
                )
                guard providerHashAliases.count == rawAliases.count else {
                    return nil
                }
                hasDurableAliasMetadata = true
            } else {
                guard components.count == 12 || components.count == 13 else {
                    return nil
                }
                providerComponents = Array(components[6...])
                providerHashAliases = []
                hasDurableAliasMetadata = false
                providerHashProvenance = nil
            }
        } else {
            // v3/v4 persisted the complete mutable movement identity:
            // 12 fixed fields plus an optional log index. Extract only the
            // provider's immutable record discriminator for migration.
            guard components.count == 17 || components.count == 18 else {
                return nil
            }
            providerComponents = [
                components[5],
                components[6],
                components[7],
                components[8],
                components[9],
                components[10]
            ] + (components.count == 18 ? [components[17]] : [])
            providerHashAliases = []
            hasDurableAliasMetadata = false
            providerHashProvenance = nil
        }

        guard providerComponents.count == 6 || providerComponents.count == 7,
              ProviderIdentifierGrammar.isCanonical(providerComponents[0])
        else {
            return nil
        }

        let normalizedCanonicalProviderHash =
            OnChainIdentifierPolicy.normalizedOpaqueIdentifier(
                providerComponents[0],
                for: route
            )
        let allProviderHashes = providerHashAliases.union([
            normalizedCanonicalProviderHash
        ])
        var keys = Set<String>()
        var baseKeys = Set<String>()
        if OnChainIdentifierPolicy.addressesEqual(
            components[2],
            address,
            for: route
        ) {
            for providerHash in allProviderHashes {
                var canonical = [
                    providerHash,
                    providerComponents[1].lowercased(),
                    OnChainIdentifierPolicy.normalizedAddress(
                        providerComponents[2],
                        for: route
                    ),
                    providerComponents[3],
                    providerComponents[4].lowercased(),
                    OnChainIdentifierPolicy.normalizedTokenIdentifier(
                        providerComponents[5],
                        for: route
                    )
                ]
                if providerComponents.count == 7 {
                    canonical.append(providerComponents[6])
                }
                let canonicalIdentity = canonical.joined(separator: "|")
                keys.insert(canonicalProviderRecordKey(canonicalIdentity))
                baseKeys.insert(
                    canonicalProviderRecordBaseKey(
                        providerRecordBaseIdentity(canonicalIdentity)
                    )
                )
            }
        }

        if components[0] == "onchain_v3",
           components[2].caseInsensitiveCompare(address) == .orderedSame {
            for providerHash in allProviderHashes {
                var legacyComponents = providerComponents
                legacyComponents[0] = providerHash
                let legacyIdentity = legacyComponents
                    .map { $0.lowercased() }
                    .joined(separator: "|")
                keys.insert(
                    legacyProviderRecordKey(legacyIdentity)
                )
                baseKeys.insert(
                    legacyProviderRecordBaseKey(
                        providerRecordBaseIdentity(legacyIdentity)
                    )
                )
            }
        }
        guard !keys.isEmpty, !baseKeys.isEmpty else {
            return nil
        }
        let transactionIndex: Int?
        if providerComponents[3].isEmpty {
            transactionIndex = nil
        } else {
            guard let parsedTransactionIndex = Int(providerComponents[3]) else {
                return nil
            }
            transactionIndex = parsedTransactionIndex
        }
        let logIndex: Int?
        if providerComponents.count == 6 || providerComponents[6].isEmpty {
            logIndex = nil
        } else {
            guard let parsedLogIndex = Int(providerComponents[6]) else {
                return nil
            }
            logIndex = parsedLogIndex
        }
        return InstalledProviderRecordDescriptor(
            keys: keys,
            baseKeys: baseKeys,
            eventIndex: ProviderEventIndex(
                transactionIndex: transactionIndex,
                logIndex: logIndex
            ),
            canonicalProviderHash: normalizedCanonicalProviderHash,
            providerHashAliases: providerHashAliases,
            hasDurableAliasMetadata: hasDurableAliasMetadata,
            providerHashProvenance: providerHashProvenance
        )
    }

    private func externalID(
        for transaction: TatumTransaction,
        canonicalProviderHash: String,
        providerHashAliases: Set<String>,
        providerHashProvenance: TatumProviderHashProvenance?
    ) -> String {
        var providerComponents = transaction.providerRecordIdentity(for: route)
            .split(separator: "|", omittingEmptySubsequences: false)
            .map(String.init)
        guard providerComponents.count == 6 || providerComponents.count == 7 else {
            return "\(value)|record_v1|\(transaction.providerRecordIdentity(for: route))"
        }
        providerComponents[0] = canonicalProviderHash

        var components = value
            .split(separator: "|", omittingEmptySubsequences: false)
            .map(String.init)
        components.append("record_v1")
        components.append(contentsOf: providerComponents)

        let aliases = providerHashAliases
            .map {
                OnChainIdentifierPolicy.normalizedOpaqueIdentifier($0, for: route)
            }
            .filter { $0 != canonicalProviderHash }
            .sorted()
        if isUTXO,
           !aliases.isEmpty || providerHashProvenance != nil {
            components.append(Self.providerIdentityMarkerV2)
            switch providerHashProvenance {
            case .explicitTxid:
                components.append("explicit_txid")
            case .fallbackIdentifier:
                components.append("fallback")
            case nil:
                components.append("unknown")
            }
            components.append(String(aliases.count))
            components.append(contentsOf: aliases)
        }
        return components.joined(separator: "|")
    }

    private func canonicalProviderRecordKey(_ identity: String) -> String {
        "canonical|\(identity)"
    }

    private func legacyProviderRecordKey(_ identity: String) -> String {
        "legacy_v3|\(identity)"
    }

    private func canonicalProviderRecordBaseKey(_ identity: String) -> String {
        "canonical_base|\(identity)"
    }

    private func legacyProviderRecordBaseKey(_ identity: String) -> String {
        "legacy_v3_base|\(identity)"
    }

    private func providerRecordBaseIdentity(_ identity: String) -> String {
        let components = identity.split(
            separator: "|",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard components.count == 6 || components.count == 7 else {
            return identity
        }
        return [
            components[0],
            components[1],
            components[2],
            components[4],
            components[5]
        ].joined(separator: "|")
    }
}

private extension TatumTransaction {
    func signedAmount(
        for route: BalanceRoute,
        trackedAddress: String,
        expectedChainId: String
    ) -> Double? {
        let baseAmount: Double

        switch route {
        case .v4Native(let expectedV4Chain):
            guard transactionType?.lowercased() == "native",
                  chain?.lowercased() == expectedV4Chain.lowercased(),
                  address.map({
                      OnChainIdentifierPolicy.addressesEqual($0, trackedAddress, for: route)
                  }) == true
            else {
                return nil
            }
            baseAmount = abs(Double(amount ?? "") ?? 0)

        case .v4Token(let expectedV4Chain, let canonicalContracts):
            let normalizedContracts = Set(canonicalContracts.map { $0.lowercased() })
            guard transactionType?.lowercased() == "fungible",
                  chain?.lowercased() == expectedV4Chain.lowercased(),
                  address.map({
                      OnChainIdentifierPolicy.addressesEqual($0, trackedAddress, for: route)
                  }) == true,
                  let tokenAddress,
                  normalizedContracts.contains(tokenAddress.lowercased())
            else {
                return nil
            }
            baseAmount = abs(Double(amount ?? "") ?? 0)

        case .utxo:
            guard transactionType?.lowercased() == "utxo",
                  chain?.caseInsensitiveCompare(expectedChainId) == .orderedSame,
                  address.map({
                      OnChainIdentifierPolicy.addressesEqual($0, trackedAddress, for: route)
                  }) == true
            else {
                return nil
            }
            baseAmount = abs(Double(amount ?? "") ?? 0)

        case .xrp, .tron, .cardano, .solana:
            guard chain?.caseInsensitiveCompare(expectedChainId) == .orderedSame,
                  address.map({
                      OnChainIdentifierPolicy.addressesEqual($0, trackedAddress, for: route)
                  }) == true
            else {
                return nil
            }
            baseAmount = abs(Double(amount ?? "") ?? 0)
        }

        guard baseAmount > 0 else { return nil }

        if let subtype = transactionSubtype?.lowercased() {
            if subtype == "incoming" || subtype.contains("receive") { return baseAmount }
            if subtype == "outgoing" || subtype.contains("sent") { return -baseAmount }
        }

        // Fallback: infer direction from from/to fields.
        if let toAddress = to,
           OnChainIdentifierPolicy.addressesEqual(toAddress, trackedAddress, for: route) {
            return baseAmount
        }
        if let fromAddress = from,
           OnChainIdentifierPolicy.addressesEqual(fromAddress, trackedAddress, for: route) {
            return -baseAmount
        }

        return nil
    }
}
